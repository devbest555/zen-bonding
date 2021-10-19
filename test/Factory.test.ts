import {expect} from './chai-setup';
import {ethers, deployments, getUnnamedAccounts} from 'hardhat';
import {Factory} from '../typechain';
import {setupUsers} from './utils';

const setup = deployments.createFixture(async () => {
  await deployments.fixture('Factory');
  const contracts = {
    FactoryContract: <Factory>await ethers.getContract('Factory'),
  };
  const users = await setupUsers(await getUnnamedAccounts(), contracts);
  return {
    ...contracts,
    users,
  };
});
describe('Factory', function () {
  it('works', async function () {
    const {users, FactoryContract} = await setup();
    console.log("====user::", users[0].address, FactoryContract.policy())
    expect(await FactoryContract.policy()).eql("0xb10bcC8B508174c761CFB1E7143bFE37c4fBC3a1")
  });
});
