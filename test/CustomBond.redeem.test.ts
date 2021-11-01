import {expect} from './chai-setup';
import {ethers, deployments} from 'hardhat';
import {config, randomAddress} from './utils';
import {Factory, FactoryStorage, SubsidyRouter, MockToken} from '../typechain';
import { BigNumber, utils } from 'ethers';
const ERC20 = require('./utils/ERC20.json');


const setup = deployments.createFixture(async () => {
    await deployments.fixture('Factory');
    
    const contracts = {
        FactoryContract: <Factory>await ethers.getContract('Factory'),
        FactoryStorageContract: <FactoryStorage>await ethers.getContract('FactoryStorage'),
        SubsidyRouterContract: <SubsidyRouter>await ethers.getContract('SubsidyRouter'),
        MockTokenContract: <MockToken>await ethers.getContract('MockToken'),
    };
    
    const [deployer, user] = await ethers.getSigners();
    const principleToken = await contracts.MockTokenContract.deployed();

    await contracts.FactoryContract.connect(deployer).setTiersAndFees(config.tierCeilings, config.fees);

    const tx = await contracts.FactoryContract.connect(user).createBondAndTreasury(
      config.usdcAdress, 
      principleToken.address, 
      user.address, 
      {from:user.address}
    )

    const TreasuryFactory = await ethers.getContractFactory('CustomTreasury');
    const BondFactory = await ethers.getContractFactory('CustomBond');
    let events: any = [];
    events = (await tx.wait()).events;    
    const customTreasuryAddr = events[0].args.treasury;
    const customBondAddr = events[0].args.bond;
    const TreasuryContract = TreasuryFactory.attach(customTreasuryAddr);//0xa47079A1f2Ad851f049fB41ee69c66a1bD09E2
    const BondContract = BondFactory.attach(customBondAddr);//0xCb37185a629590622De9d45a0376B0687Cf3b412
    
    // set bond terms
    await BondContract.connect(user).setBondTerms(0, 20000, {from: user.address})//_input >= 10000, terms.vestingTerm
    await BondContract.connect(user).setBondTerms(1, 150, {from: user.address})  //_input <= 1000,  terms.maxPayout
    await BondContract.connect(user).setBondTerms(2, 2000, {from: user.address}) //                 terms.maxDebt

    return {
        ...contracts, deployer, user, principleToken, TreasuryContract, BondContract
    };
});

const convert = (addr: string) => {
  return addr.toLowerCase();
}

describe('CustomBond-redeem', async function () {
  it('redeem(user) with lpTokenAsFeeFlag=true', async function () {      
    const {
      deployer, user,
      FactoryContract,
      MockTokenContract,
      principleToken, 
      TreasuryContract, 
      BondContract
    } = await setup();

    // initialization bond
    const controlVariable = BigNumber.from(825000);
    const vestingTerm = BigNumber.from(1);
    const minimumPrice = BigNumber.from(36760);
    const maxPayout = BigNumber.from(4);
    const maxDebt = utils.parseEther('1250');
    const initialDebt = utils.parseEther('400')
    await BondContract.connect(user).initializeBond(controlVariable, vestingTerm, minimumPrice, maxPayout, maxDebt, initialDebt, {from:user.address})
    
    // payoutTokenContract=USDC(decimals:6), 
    // principleToken=tokenContract(decimals:18)     

    // payoutToken
    const payoutTokenContract = new ethers.Contract(config.usdcAdress, JSON.stringify(ERC20), ethers.provider)
    await payoutTokenContract.connect(deployer).transfer(user.address, utils.parseUnits('1000', await payoutTokenContract.decimals()), {from: deployer.address});
    const payoutTokenBalanceDeployer = Number(await payoutTokenContract.balanceOf(deployer.address));//0.5*10**18
    const payoutTokenBalanceToUser = Number(await payoutTokenContract.balanceOf(user.address));//1500000000040000000, decimal=6
    const payoutTokenBalanceToUser1 = await payoutTokenContract.balanceOf(user.address);

    // principleToken
    const tokenContract = new ethers.Contract(principleToken.address, JSON.stringify(ERC20), ethers.provider)
    await tokenContract.connect(deployer).transfer(user.address, utils.parseEther('20'), {from: deployer.address});
    const tokenBalanceDeployer = Number(await tokenContract.balanceOf(deployer.address));//9.999998e+25
    const tokenBalanceUser = Number(await tokenContract.balanceOf(user.address));//20*10**18, decimal=18
            
    //Approve(principleToken) to deposit in frontend(user)
    const tokenSupply = await tokenContract.totalSupply();//1e+26
    await tokenContract.connect(user).approve(BondContract.address, tokenSupply, {from: user.address});
    
    // Allow to deposit from user
    await TreasuryContract.connect(user).toggleBondContract(BondContract.address, {from:user.address})

    const amount = utils.parseEther('1');// principleToken amount for deposit
    const maxPrice = 50000;//>= nativePrice(37682)
    
    // Transfer(payoutToken) to TreasuryContract for testing
    const transferAmount = utils.parseUnits('500', await payoutTokenContract.decimals());
    await payoutTokenContract.connect(user).transfer(TreasuryContract.address, transferAmount, {from: user.address});

    // Depoist principleToken(lp token) from user
    const txd = await BondContract.connect(user).deposit(amount, maxPrice, user.address, {from:user.address});
    let events = (await txd.wait()).events;   

    const bondCreatedEvent = events[7].args;
    const deposit = Number(BigNumber.from(bondCreatedEvent.deposit))//100000000000000000
    const payout = Number(BigNumber.from(bondCreatedEvent.payout)) //27203482
    const expires = Number(BigNumber.from(bondCreatedEvent.expires))//9573882
    expect(Number(amount)).to.equal(deposit);

    const blockNum = await ethers.provider.getBlockNumber()
    const expiresSol = BigNumber.from(blockNum).add(vestingTerm);
    expect(Number(expiresSol)).to.equal(expires);
    
    const bondPriceChangedEvent = events[8].args;
    const internalPrice = Number(BigNumber.from(bondPriceChangedEvent.internalPrice))//36760 
    const debtRatio = Number(BigNumber.from(bondPriceChangedEvent.debtRatio))//0

    const debtRatioSol = await BondContract.connect(user).debtRatio({from:user.address});
    expect(Number(debtRatioSol)).to.equal(debtRatio)

    // debtRatio=0 so that price = terms.minimumPrice;
    const priceSol = minimumPrice;
    expect(Number(priceSol)).to.equal(internalPrice)

    // Set timestamp
    const currentDate = new Date()
    const afterFiveDays = new Date(currentDate.setDate(currentDate.getDate() + 5))
    const afterFiveDaysTimeStampUTC = new Date(afterFiveDays.toUTCString()).getTime() / 1000
    await ethers.provider.send("evm_setNextBlockTimestamp", [afterFiveDaysTimeStampUTC])
    await ethers.provider.send("evm_mine", [])

    const tx = await BondContract.connect(user).redeem(user.address, {from: user.address})
    events = (await tx.wait()).events
    const recipient = events[0].args.recipient;
    const payoutRedeem = events[0].args.payout;
    const remaining = events[0].args.remaining;
    
    const payoutTokenBalanceToUserAfterRedeem = Number(await payoutTokenContract.balanceOf(user.address));//500000000067203460
    const calcPayoutTokenBalanceToUser = payoutTokenBalanceToUser1.sub(transferAmount).add(payoutRedeem);
    expect(payoutTokenBalanceToUserAfterRedeem).to.equal(Number(calcPayoutTokenBalanceToUser));
    expect(convert(user.address)).to.equal(convert(recipient));
  });

  it('redeem(user) with lpTokenAsFeeFlag=false', async function () {      
    const {
      deployer, user,
      FactoryContract,
      MockTokenContract,
      principleToken, 
      TreasuryContract, 
      BondContract
    } = await setup();

    // initialization bond
    const controlVariable = BigNumber.from(825000);
    const vestingTerm = BigNumber.from(1);
    const minimumPrice = BigNumber.from(36760);
    const maxPayout = BigNumber.from(4);
    const maxDebt = utils.parseEther('1250');
    const initialDebt = utils.parseEther('400')
    await BondContract.connect(user).initializeBond(controlVariable, vestingTerm, minimumPrice, maxPayout, maxDebt, initialDebt, {from:user.address})
    
    // change lpTokenAsFeeFlag as false
    await BondContract.connect(user).setLPtokenAsFee(false, {from: user.address});

    // payoutTokenContract=Dai(decimals:6), 
    // principleToken=tokenContract(decimals:18)     

    // payoutToken
    const payoutTokenContract = new ethers.Contract(config.usdcAdress, JSON.stringify(ERC20), ethers.provider)
    await payoutTokenContract.connect(deployer).transfer(user.address, utils.parseUnits('1000', await payoutTokenContract.decimals()), {from: deployer.address});
    const payoutTokenBalanceDeployer = Number(await payoutTokenContract.balanceOf(deployer.address));//0.5*10**18
    const payoutTokenBalanceToUser = Number(await payoutTokenContract.balanceOf(user.address));//1500000000040000000, decimal=6
    const payoutTokenBalanceToUser1 = await payoutTokenContract.balanceOf(user.address);

    // principleToken
    const tokenContract = new ethers.Contract(principleToken.address, JSON.stringify(ERC20), ethers.provider)
    await tokenContract.connect(deployer).transfer(user.address, utils.parseEther('20'), {from: deployer.address});
    const tokenBalanceDeployer = Number(await tokenContract.balanceOf(deployer.address));//9.999998e+25
    const tokenBalanceUser = Number(await tokenContract.balanceOf(user.address));//20*10**18, decimal=18
            
    //Approve(principleToken) to deposit in frontend(user)
    const tokenSupply = await tokenContract.totalSupply();//1e+26
    await tokenContract.connect(user).approve(BondContract.address, tokenSupply, {from: user.address});
    
    // Allow to deposit from user
    await TreasuryContract.connect(user).toggleBondContract(BondContract.address, {from:user.address})

    const amount = utils.parseEther('1');// principleToken amount for deposit
    const maxPrice = 50000;//>= nativePrice(37682)
    
    // Transfer(payoutToken) to TreasuryContract for testing
    const transferAmount = utils.parseUnits('500', await payoutTokenContract.decimals());
    await payoutTokenContract.connect(user).transfer(TreasuryContract.address, transferAmount, {from: user.address});

    // Depoist principleToken(lp token) from user
    const txd = await BondContract.connect(user).deposit(amount, maxPrice, user.address, {from:user.address});
    let events = (await txd.wait()).events;   

    const bondCreatedEvent = events[7].args;
    const deposit = Number(BigNumber.from(bondCreatedEvent.deposit))//100000000000000000
    const payout = Number(BigNumber.from(bondCreatedEvent.payout)) //27203482
    const expires = Number(BigNumber.from(bondCreatedEvent.expires))//9573882
    expect(Number(amount)).to.equal(deposit);

    const blockNum = await ethers.provider.getBlockNumber()
    const expiresSol = BigNumber.from(blockNum).add(vestingTerm);
    expect(Number(expiresSol)).to.equal(expires);
    
    const bondPriceChangedEvent = events[8].args;
    const internalPrice = Number(BigNumber.from(bondPriceChangedEvent.internalPrice))//36760 
    const debtRatio = Number(BigNumber.from(bondPriceChangedEvent.debtRatio))//0

    const debtRatioSol = await BondContract.connect(user).debtRatio({from:user.address});
    expect(Number(debtRatioSol)).to.equal(debtRatio)

    // debtRatio=0 so that price = terms.minimumPrice;
    const priceSol = minimumPrice;
    expect(Number(priceSol)).to.equal(internalPrice)

    // Set timestamp
    const currentDate = new Date()
    const afterFiveDays = new Date(currentDate.setDate(currentDate.getDate() + 5))
    const afterFiveDaysTimeStampUTC = new Date(afterFiveDays.toUTCString()).getTime() / 1000
    await ethers.provider.send("evm_setNextBlockTimestamp", [afterFiveDaysTimeStampUTC])
    await ethers.provider.send("evm_mine", [])

    const tx = await BondContract.connect(user).redeem(user.address, {from: user.address})
    events = (await tx.wait()).events
    const recipient = events[0].args.recipient;
    const payoutRedeem = events[0].args.payout;
    const remaining = events[0].args.remaining;
    
    const payoutTokenBalanceToUserAfterRedeem = Number(await payoutTokenContract.balanceOf(user.address));//500000000067203460
    const calcPayoutTokenBalanceToUser = payoutTokenBalanceToUser1.sub(transferAmount).add(payoutRedeem);
    expect(payoutTokenBalanceToUserAfterRedeem).to.equal(Number(calcPayoutTokenBalanceToUser));
    expect(convert(user.address)).to.equal(convert(recipient));
  });
});

