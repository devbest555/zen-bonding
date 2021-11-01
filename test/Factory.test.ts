import {expect} from './chai-setup';
import {ethers, deployments, getUnnamedAccounts} from 'hardhat';
import {setupUsers, config, randomAddress} from './utils';
import {Factory, FactoryStorage, SubsidyRouter, MockToken } from '../typechain';
import { BigNumber, BigNumberish, utils } from 'ethers';
const ERC20 = require('./utils/ERC20.json');

// TEST : Rinkeby testnet
const setup = deployments.createFixture(async () => {
  await deployments.fixture('Factory');
  
  const contracts = {
    FactoryContract: <Factory>await ethers.getContract('Factory'),
    FactoryStorageContract: <FactoryStorage>await ethers.getContract('FactoryStorage'),
    SubsidyRouterContract: <SubsidyRouter>await ethers.getContract('SubsidyRouter'),
    MockTokenContract: <MockToken>await ethers.getContract('MockToken')
  };
  
  
  const [deployer, user] = await ethers.getSigners();
  
  return {
    ...contracts, deployer, user
  };
});

const convert = (addr: string) => {
  return addr.toLowerCase();
}

describe('Factory', function () {
  it('Factory-constructor', async function () {
    const {
      deployer, user, 
      FactoryContract, 
      FactoryStorageContract, 
      SubsidyRouterContract
    } = await setup();
    
    expect(await FactoryContract.policy()).eql(deployer.address)
    expect(await FactoryContract.DAO()).eql(config.dao)
    expect(await FactoryContract.TREASURY()).eql(config.treasury)

    const fsc = await FactoryStorageContract.deployed();
    expect(await FactoryContract.FACTORY_STORAGE()).eql(fsc.address)
    const src = await SubsidyRouterContract.deployed();
    expect(await FactoryContract.SUBSIDY_ROUTER()).eql(src.address)
  });
  
  it('createBondAndTreasury', async function () {
    const {
      FactoryContract, 
      MockTokenContract,
      deployer, user
    } = await setup();
    
    const mToken = await MockTokenContract.deployed();
    await FactoryContract.connect(deployer).setTiersAndFees(config.tierCeilings, config.fees);
    const tx = await FactoryContract.connect(user).createBondAndTreasury(
      config.usdcAdress, 
      mToken.address, 
      user.address, 
      {from: user.address}
    )
    
    let events: any = [];
    events = (await tx.wait()).events;
    const customTreasury = events[0].args.treasury;
    const customBond = events[0].args.bond;
    const initialOwner = events[0].args._initialOwner;
    expect(initialOwner).eql(user.address)
  });

  it('createBond', async function () {
    const {
      deployer, user,
      FactoryContract,
      MockTokenContract
    } = await setup();

    const _customTreasury = '0x31F8Cc382c9898b273eff4e0b7626a6987C846E8';
    const mToken = await MockTokenContract.deployed();

    await FactoryContract.connect(deployer).setTiersAndFees(config.tierCeilings, config.fees);

    const tx = await FactoryContract.connect(user).createBond(
      config.usdcAdress, 
      mToken.address, 
      _customTreasury,
      user.address,     
      {from: user.address}
    )
    
    let events: any = [];
    events = (await tx.wait()).events;
    const customTreasury = events[0].args.treasury;
    const customBond = events[0].args.bond;
    const initialOwner = events[0].args._initialOwner;
    expect(_customTreasury).to.deep.equal(customTreasury)
    expect(initialOwner).to.equal(user.address)
  });
});

