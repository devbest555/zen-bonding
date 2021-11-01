import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {
    deployments: { deploy, get },
    ethers: { getSigners },
  } = hre;

  const deployer = (await getSigners())[0];
  console.log("====deployer::", deployer.address);
  
  await deploy('MockToken', {
    from: deployer.address,
    args: ["Mock Token", "sTao", 18],
    log: true,    
    skipIfAlreadyDeployed: true,
    autoMine: true, // speed up deployment on local network (ganache, hardhat), no effect on live networks
  });
};

func.id = 'deploy_mock_token'; // id required to prevent reexecution
func.tags = ['MockToken'];

export default func;