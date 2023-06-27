import { HardhatUserConfig } from 'hardhat/config';
import '@nomicfoundation/hardhat-toolbox';

const config: HardhatUserConfig = {
  networks: {
    rsk_testnet: {
      url: 'https://public-node.testnet.rsk.co',
      chainId: 31,
      gasPrice: 20000000000,
      accounts: [],
    },
    hardhat: {
      forking: {
        url: 'https://mainnet.infura.io/v3/98f137a7f91a4564bc3aedbcbfbb4e06',
        blockNumber: 17518606,
      },
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
};

export default config;
