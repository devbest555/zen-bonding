import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import {config} from '../test/utils';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy, get },
    ethers: { getSigners },
  } = hre;

  const deployer = (await getSigners())[0]; 
        
  await deploy('Helper', {
    from: deployer.address,
    args: [
      config.uniswap.factory,
      config.uniswap.router, 
      config.sushiswapRinkeby.factory,
      config.sushiswapRinkeby.router
    ],
    log: true,    
    skipIfAlreadyDeployed: true,
    autoMine: true, // speed up deployment on local network (ganache, hardhat), no effect on live networks
  });
};

func.id = 'deploy_helper'; // id required to prevent reexecution
func.tags = ['Helper'];

export default func;