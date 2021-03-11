require("@nomiclabs/hardhat-waffle");
require("hardhat-deploy");
require("hardhat-deploy-ethers");
require('hardhat-abi-exporter');
const dotenv = require("dotenv");
dotenv.config();

const AVALANCHE_URL = process.env.AVALANCHE_URL;
const PRIVATE_KEY_5 = process.env.PRIVATE_KEY_5;
const PK_OWNER = process.env.PK_OWNER;

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */

module.exports = {
  solidity: "0.7.3",
  defaultNetwork: "mainnet",
  namedAccounts: {
    deployer: {
      default: 1,
    }
  },
  paths: {
    deploy: 'deploy',
    deployments: 'deployments'
  },
  abiExporter: {
    path: './abis',
    clear: true,
    flat: true
  },
  networks: {
    hardhat: {
      chainId: 43114,
      gasPrice: 470000000000,
      throwOnTransactionFailures: false,
      loggingEnabled: true,
      forking: {
        url: AVALANCHE_URL,
        enabled: true,
      },
    },
    mainnet: {
      chainId: 43114,
      gasPrice: 470000000000,
      url: AVALANCHE_URL,
      accounts: [
        PRIVATE_KEY_5,
        PK_OWNER
      ]
    },
  },
};
