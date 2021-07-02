require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-ethers");
require("hardhat-deploy");
require("hardhat-deploy-ethers");
require('hardhat-abi-exporter');
require('hardhat-contract-sizer');
const dotenv = require("dotenv");
dotenv.config();

const AVALANCHE_MAINNET_URL = process.env.AVALANCHE_MAINNET_URL;
const AVALANCHE_FUJI_URL = process.env.AVALANCHE_FUJI_URL;

const PK_USER = process.env.PK_USER;
const PK_OWNER = process.env.PK_OWNER;
const PK_TEST = process.env.PK_TEST;

// require scripts
const farmData = require("./scripts/farm-data");
const timelockBalances = require("./scripts/timelock-balances");
const sweepTokens = require("./scripts/sweep-tokens");
const masterchefScripts = {
  bird: require("./scripts/masterchef-bird"),
  gondola: require("./scripts/masterchef-gondola"),
  lydia: require("./scripts/masterchef-lydia"),
  olive: require("./scripts/masterchef-olive"),
  panda: require("./scripts/masterchef-panda"),
  penguin: require("./scripts/masterchef-penguin")
}
const writeTimelock = require("./scripts/write-timelock");

// require constants
const { timelockContractAddress } = require("./constants/addresses");

// tasks
task("checkFarmState", "Gives a nice output of the state of the farm")
  .addParam("farm", "Farm address to check the state of")
  .setAction(async ({ farm }) => farmData(farm));

task("timelockBalances", "Displays the token balances in the timelock contract")
  .setAction(async () => timelockBalances(timelockContractAddress))

task("sweepTokens", "Sweeps the tokens given")
  .addParam("tokens", "Token list formatted as hyphenated ranges")
  .setAction(async ({tokens}) => sweepTokens(tokens, timelockContractAddress))

task("masterchef", "Show's pool data for several platforms in different masterchef contracts")
  .addOptionalParam("platforms", "comma-seperated list of platforms to print, see possible platforms in the 'scripts' directory")
  .setAction(async ({platforms}) => {

    if (platforms == undefined) {
      platforms = Object.keys(masterchefScripts)
    } else {
      platforms = platforms.split(',')
    }

    for (let platform of platforms) {
      console.log(`\n\n   ${platform.toUpperCase()} \n`);
      let script;
      try {
        script = masterchefScripts[platform.toLowerCase()];
      } catch (e) {
        console.error("no platform found by the name of " + platform);
        process.exit(1);
      }
      await script();
    }
    
  })

task("writeTimelock", "specify a change in the timelock contract for a given farm")
  .addFlag("set", "if this flag is not supplied, the task will propose whatever change is specified, else, it will set it.")
  .addOptionalParam("value", "value of command to be written in smart contract")
  .addParam("farm", "the farm to apply the changes of the timelock contract to")
  .addParam("command", "DevFee, AdminFee, Owner, ReinvestReward")
  .setAction(async ({farm, set, command, value}) => writeTimelock(farm, set, command, value, timelockContractAddress))


// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */

module.exports = {
  solidity: {
    version: "0.7.3",
    settings: {
      optimizer: {
        enabled: true,
        runs: 999
      }
    }
  },
  defaultNetwork: "hardhat",
  namedAccounts: {
    deployer: {
      default: 1,
    }
  },
  contractSizer: {
    alphaSort: false,
    runOnCompile: false,
    disambiguatePaths: false,
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
      gasPrice: 225000000000,
      throwOnTransactionFailures: false,
      // loggingEnabled: true,
      forking: {
        url: AVALANCHE_MAINNET_URL,
        enabled: true,
      },
    },
    mainnet: {
      chainId: 43114,
      gasPrice: 225000000000,
      url: AVALANCHE_MAINNET_URL,
      accounts: [
        // PK_USER,
        // PK_OWNER
      ]
    },
    // fuji: {
    //   chainId: 43113,
    //   gasPrice: 225000000000,
    //   url: AVALANCHE_FUJI_URL,
    //   accounts: [
    //     PK_TEST
    //   ]
    // },
  },
};
