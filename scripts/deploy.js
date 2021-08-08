const { ethers } = require("hardhat");
const { TASK_ETHERSCAN_VERIFY } = require("hardhat-deploy");

async function main() {
  const someContractAbi1 = require("./deployments/mainnet/CNR-WAVAX.json");
  const someContractAbi2 = require("./deployments/mainnet/stakingContract.json");
  let stakingContractExt1 = new ethers.Contract("0x967fEA7074BA54E8DaD60A9512b1ECDc89D98453", someContractAbi2, provider);

  //const [deployer] = await ethers.getSigners();
  //const accounts = await ethers.getSigners();
  const [owner,addr1] = await ethers.getSigners();
  console.log(
    "Deploying contracts with the account:",
    owner.address
  );
  //.allowance(address(this), spenders[i]);
  const provider = new ethers.providers.JsonRpcProvider("https://api.avax.network/ext/bc/C/rpc");
  await hre.network.provider.request({method: "hardhat_impersonateAccount",params: ["0xdcedf06fd33e1d7b6eb4b309f779a0e9d3172e44"]});
  const signer = hre.ethers.provider.getSigner("0xdcedf06fd33e1d7b6eb4b309f779a0e9d3172e44");
  const provider = await ethers.getDefaultProvider();
  let stakingContract = new ethers.Contract("0x1fc1f7A0943c589EDFf4A3650E40C0821B41901d", someContractAbi1.abi, provider);
  console.log("Account balance:", (await owner.getBalance()).toString());

  const Token = await ethers.getContractFactory("AvaxZap");
  // const token = await Token.deploy("Yield Yak: Compounding AVAX", "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7","0x0000000000000000000000000000000000000000", "0x8d88e48465f30acfb8dac0b3e35c9d6d7d36abaf", 
  //                                     "0x967fea7074ba54e8dad60a9512b1ecdc89d98453","0x0000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000000","0x8d36c5c6947adccd25ef49ea1aac2ceacfff0bd7", "100000000000000000", 200,300,500);
  const myContract = await Token.deploy();
  //const token = await Token.deploy("Yield Yak: Compounding AVAX", "AVAX_CNR", "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7", "0x8d88e48465f30acfb8dac0b3e35c9d6d7d36abaf","0x967fea7074ba54e8dad60a9512b1ecdc89d98453","0x5a2Be3Aa5Ed59cc120C1Aee2f03146dE02DfC280","0x8d36c5c6947adccd25ef49ea1aac2ceacfff0bd7", "1000000000000000000000", 200,300,500);
   //var weiValue = ethers.toWei(4,'ether');
   await myContract.connect(signer).depositAVAX( stakingContract.address, {from: signer.address, value: "40000000000000000000"});
   const deposits = await stakingContract.balanceOf("0xdcedf06fd33e1d7b6eb4b309f779a0e9d3172e44");
   console.log(
    "Balance in the staking contract:",
    deposits
  );
  await stakingContract.connect(signer).approve(myContract.address,"40000000000000000000");
  await myContract.connect(signer).withdraw(stakingContract.address,"0x8d88e48465f30acfb8dac0b3e35c9d6d7d36abaf", "40000000000000000000");
  //const tx = signer.sendTransaction({to: token.address ,value: ethers.utils.parseEther("4.0")});

  console.log("Token address:", myContract.address);
  
}

async function matic () {
  const [owner,addr1] = await ethers.getSigners();
  const someContractAbi1 = require("./deployments/matic/UniSwapV2Pair.json");
  const provider = new ethers.providers.JsonRpcProvider("https://polygon-mainnet.g.alchemy.com/v2/nGUNl3upCawPa6Rd0E97kpmOLte8HTNX");
  let stakingContract = new ethers.Contract("0x160532D2536175d65C03B97b0630A9802c274daD", someContractAbi1, provider);
  const WMATIC = "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270";
  const Token = await ethers.getContractFactory("QuickSwapStrategy");
  // const token = await Token.deploy("Yield Yak: USDC-WETH",
  //   "0x853Ee4b2A13f8a742d64C8F088bE7bA2131f670d",
  //   "0x831753dd7087cac61ab5644b308642cc1c33dc13",
  //   "0x4A73218eF2e820987c59F838906A82455F42D98b", 
  //   "0x1f1e4c845183ef6d50e9609f16f6f9cae43bc9cb",
  //   "0x1bd06b96dd42ada85fdd0795f3b4a79db914add5",
  //   "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
  //   "100000000000000000", 200,300,500);
  const token1 = await Token.deploy("Yield Yak: USDC-WETH","0x853Ee4b2A13f8a742d64C8F088bE7bA2131f670d","0x831753dd7087cac61ab5644b308642cc1c33dc13","0x4A73218eF2e820987c59F838906A82455F42D98b","0x1f1e4c845183ef6d50e9609f16f6f9cae43bc9cb","0x1bd06b96dd42ada85fdd0795f3b4a79db914add5","0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266","100000000000000000", 200,300,500);
  await network.provider.send("hardhat_setBalance", ["0x0E43245f7Af3cFb1D4838E6704F27D09A8b4b072","0x1000",]);
  await network.provider.send("evm_setNextBlockTimestamp", [1625097600])
  await network.provider.send("evm_mine")
  const trace = await hre.network.provider.send("debug_traceTransaction", ["0x0535925ebda0e076861748fd5c6d091715ad834705749300930fc356c514e6d1",]);
}

// const token = await Token.deploy("Yield Yak: USDC-WETH",depositLP1.address,"0x831753dd7087cac61ab5644b308642cc1c33dc13",stakingContract.address,swapPair0.address,swapPair1.address,"0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266","1000", 200,300,500);


main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });