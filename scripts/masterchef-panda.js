const masterchefPanda = async () => {
    const MASTERCHEF = "0x124737ce6a43A98CAAF095AcCb9A9D6fccBb0E73";

    const ABI_PAIR = require("../abis/IPair");
    const ABI_MASTERCHEF = require("../abis/IBambooChef");

    let masterChefContract = new ethers.Contract(MASTERCHEF, ABI_MASTERCHEF, ethers.provider);

    let pefiPerBlock = await masterChefContract.bambooPerBlock();
    console.log(
      `${ethers.utils.formatUnits(pefiPerBlock)} BAMBOO per Block`
    );

    console.log("masterchef contract: ", MASTERCHEF);
    
    let poolLength = await masterChefContract.poolLength();

    let i = ethers.BigNumber.from("0");
    let poolData = [];
    while (i.lt(poolLength)) {
      let poolInfo = await masterChefContract.poolInfo(i);
      let lpTokenContract = new ethers.Contract(poolInfo.lpToken, ABI_PAIR, ethers.provider);

      try {
        let token0 = await lpTokenContract.token0();
        let token1 = await lpTokenContract.token1();
  
        let token0Contract = new ethers.Contract(token0, ABI_PAIR, ethers.provider);
        let token1Contract = new ethers.Contract(token1, ABI_PAIR, ethers.provider);

        poolData.push({
            token_address: poolInfo.lpToken,
            alloc_point: poolInfo.allocPoint.toString(),
            token_symbol: await lpTokenContract.symbol(),
            token0: await token0Contract.symbol(),
            token1: await token1Contract.symbol()
        })
      }
      catch {

        poolData.push({
            token_address: poolInfo.lpToken,
            alloc_point: poolInfo.allocPoint.toString(),
            token_symbol: await lpTokenContract.symbol(),
            token0: "-",
            token1: "-"
        })

      }

      i = i.add("1");
    }

    console.table(poolData)

    console.log("BAMBOO contract: ", await masterChefContract.bamboo());
}

module.exports = masterchefPanda;