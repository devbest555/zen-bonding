'use strict';

import "dotenv/config";

import { HardhatUserConfig } from "hardhat/config";
import { NetworkUserConfig } from "hardhat/types";
import { config as dotenvConfig } from "dotenv";
import { resolve } from "path";
import '@typechain/hardhat';
import "@nomiclabs/hardhat-ethers"
import "@nomiclabs/hardhat-waffle"
import "hardhat-deploy"
import "@nomiclabs/hardhat-etherscan"

dotenvConfig({ path: resolve(__dirname, "./.env") });

const alchemy_api_key = process.env.ALCHEMY_KEY;
const etherScan_api_key = process.env.ETHERSCAN_API_KEY;
const mnemonic = process.env.MNEMONIC;

if (!mnemonic || !alchemy_api_key || !etherScan_api_key) {
  throw new Error("Please set your data in a .env file");
}

const chainIds = {
  ganache: 1337,
  goerli: 5,
  hardhat: 31337,
  kovan: 42,
  mainnet: 1,
  rinkeby: 4,
  ropsten: 3,
};

function nodeAlchemy(network: keyof typeof chainIds): NetworkUserConfig {
  const url: string = "https://eth-" + network + ".alchemyapi.io/v2/" + alchemy_api_key;
  return {
    url: url,
    accounts: { mnemonic },
    chainId: chainIds[network],
    saveDeployments: true,
  };
}

const config: HardhatUserConfig = {
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      accounts: {
        mnemonic,
      },
      chainId: chainIds.rinkeby,
      saveDeployments: true,
      forking: {
        url: "https://eth-rinkeby.alchemyapi.io/v2/khT7j5E7O7LBI-Vf53jsKg9epwhAk2uh",
      },
    },
    kovan: nodeAlchemy("kovan"),
    rinkeby: nodeAlchemy("rinkeby"),
    ropsten: nodeAlchemy('ropsten'),
    mainnet: nodeAlchemy('mainnet'),
  },
  etherscan: {
    apiKey: etherScan_api_key
  },
  paths: {
    sources: "./src",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
    deploy: "deploy",    
    imports: "imports",
    deployments: "deployments"    
  },
  typechain: {
    outDir: 'typechain',
    target: 'ethers-v5',
  },
  namedAccounts: {
    deployer: 0,
  },
  solidity: {
    compilers: [
      {
        version: '0.7.5',
        settings: {
          optimizer: {
            enabled: true,
            runs: 2000,
          },
        },
      },
    ],
  },
  mocha: {
    timeout: 200e3
  },  
};

export default config;
