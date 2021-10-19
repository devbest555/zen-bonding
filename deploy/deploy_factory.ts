import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {deployments, getNamedAccounts} = hre;
  const {deploy} = deployments;

  const {deployer} = await getNamedAccounts();

  const treasury = '0x31f8cc382c9898b273eff4e0b7626a6987c846e8'; 
  const factoryStorage = '0x6828d71014d797533c3b49b6990ca1781656b71f'; 
  const subsidyRouter = '0x97fac4ea361338eab5c89792ee196da8712c9a4a';
  const dao = '0x245cc372c84b3645bf0ffe6538620b04a217988b';
  
        
  await deploy('Factory', {
    from: deployer,
    args: [treasury, factoryStorage, subsidyRouter, dao],
    log: true,
    autoMine: true, // speed up deployment on local network (ganache, hardhat), no effect on live networks
  });
};
export default func;
func.id = 'deploy_factory'; // id required to prevent reexecution
func.tags = ['Factory'];
