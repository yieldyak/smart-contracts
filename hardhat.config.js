require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-ethers");
require("hardhat-deploy");
require("hardhat-deploy-ethers");
require("hardhat-abi-exporter");
require("hardhat-contract-sizer");
require("@nomiclabs/hardhat-etherscan");
const dotenv = require("dotenv");
const {task} = require("hardhat/config");
dotenv.config();

const AVALANCHE_MAINNET_URL = process.env.AVALANCHE_MAINNET_URL;
const AVALANCHE_FUJI_URL = process.env.AVALANCHE_FUJI_URL;

const PK_USER = process.env.PK_USER;
const PK_OWNER = process.env.PK_OWNER;
const PK_TEST = process.env.PK_TEST;

const SNOWTRACE_API_KEY = process.env.SNOWTRACE_API_KEY;

// require scripts
const farmData = require("./scripts/farm-data");
const verifyContract = require("./scripts/verify-contract");

// tasks
task("checkFarmState", "Gives a nice output of the state of the farm")
    .addParam("farm", "Farm to check the state of")
    .setAction(async ({farm}) => farmData(farm));

// to verify all contracts use
// find ./deployments/mainnet -maxdepth 1 -type f -not -path '*/\.*' -path "*.json" | xargs -L1 npx hardhat verifyContract --deployment-file-path
task("verifyContract", "Verifies the contract in the snowtrace")
    .addParam("deploymentFilePath", "Deployment file path")
    .setAction(async ({deploymentFilePath}, hre) => verifyContract(deploymentFilePath, hre));

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

/**
 * @type import('hardhat/config').HardhatUserConfig
 */

module.exports = {
    mocha: {
        timeout: 1e10,
    },
    solidity: {
        version: "0.8.13",
        settings: {
            optimizer: {
                enabled: true,
                runs: 999,
            },
        },
    },
    defaultNetwork: "mainnet",
    namedAccounts: {
        deployer: {
            default: 1,
        },
    },
    contractSizer: {
        alphaSort: false,
        runOnCompile: false,
        disambiguatePaths: false,
    },
    paths: {
        deploy: "deploy",
        deployments: "deployments",
    },
    abiExporter: {
        path: "./abis",
        clear: true,
        flat: true,
    },
    etherscan: {
        apiKey: SNOWTRACE_API_KEY,
    },
    networks: {
        hardhat: {
            chainId: 43114,
            // gasPrice: 25000000000,
            throwOnTransactionFailures: false,
            loggingEnabled: true,
            forking: {
                url: AVALANCHE_MAINNET_URL,
                enabled: true,
            },
        },
        mainnet: {
            chainId: 43114,
            gasPrice: 25000000000,
            url: AVALANCHE_MAINNET_URL,
            accounts: [PK_USER, PK_OWNER],
        },
        fuji: {
            chainId: 43113,
            gasPrice: 25000000000,
            url: AVALANCHE_FUJI_URL,
            accounts: [PK_TEST],
        },
    },
};
