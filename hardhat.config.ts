import { HardhatUserConfig } from 'hardhat/config';
import '@nomicfoundation/hardhat-toolbox';
import '@nomiclabs/hardhat-ethers';
import 'hardhat-deploy';
import Addrs from './keys';

const config: HardhatUserConfig = {
  defaultNetwork: 'hardhat',
  networks: {
    rsk_testnet: {
      url: 'https://public-node.testnet.rsk.co',
      chainId: 31,
      gasPrice: 59300000,
      accounts: [Addrs.PRIVATE_KEY1, Addrs.PRIVATE_KEY2],
    },
    sepolia_testnet: {
      url: 'https://ethereum-sepolia.blockpi.network/v1/rpc/public',
      chainId: 11155111,
      gasPrice: 59300000,
      accounts: [Addrs.PRIVATE_KEY1, Addrs.PRIVATE_KEY2],
    },
    hardhat: {
      forking: {
        url: 'https://mainnet.infura.io/v3/98f137a7f91a4564bc3aedbcbfbb4e06',
        blockNumber: 17518606,
      },
    },
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
  },
  solidity: {
    version: '0.8.19',
    settings: {
      optimizer: {
        enabled: true,
        runs: 100000,
      },
    },
  },
  paths: {
    deployments: './deploy',
  },
};

export default config;
