import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy, get },
    ethers: { getSigners },
  } = hre;

  const deployer = (await getSigners())[0];

  await deploy('SubsidyRouter', {
    from: deployer.address,
    args: [],
    log: true,    
    skipIfAlreadyDeployed: true,
    autoMine: true, // speed up deployment on local network (ganache, hardhat), no effect on live networks
  });
};

func.id = 'deploy_subsidy_router'; // id required to prevent reexecution
func.tags = ['SubsidyRouter'];

export default func;