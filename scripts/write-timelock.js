const writeTimelock = async (farm, set=false, command, value, timelock) => {
    await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: ["0xdcedf06fd33e1d7b6eb4b309f779a0e9d3172e44"]
    })

    // const accounts = await ethers.provider.listAccounts();
    // const account = accounts[1];
    // const signer = ethers.provider.getSigner(account);
    const signer = ethers.provider.getSigner("0xdcedf06fd33e1d7b6eb4b309f779a0e9d3172e44");

    const ABI = require("../abis/YakTimelockForDexStrategyV3");
    const timelockContract = new ethers.Contract(timelock, ABI, signer);

    command = command.charAt(0).toUpperCase() + command.slice(1); //capitalize first letter to include camel-case style
    let prefix = set ? "set" : "propose";

    let tx = await timelockContract[prefix+command](farm, value);
    await tx.wait(1)
    console.log(tx.hash);
    
}

module.exports = writeTimelock;