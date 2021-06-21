// #TODO: I need a valid signer address to complete this task. for now its WIP.

const masterchefXava = async () => {
    const MASTERCHEF = "0xE82AAE7fc62547BdFC36689D0A83dE36FF034A68";

    const ABI_PAIR = require("../abis/IPair");
    const ABI_MASTERCHEF = require("../abis/IXavaChef");

    let masterChefContract = new ethers.Contract(MASTERCHEF, ABI_MASTERCHEF, ethers.provider);

    let pefiPerBlock = await masterChefContract.pefiPerBlock();
    console.log(
      `${ethers.utils.formatUnits(pefiPerBlock)} PEFI per Block`
    );
    
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
            withdraw_fee: poolInfo.withdrawFeeBP.toString(),
            token_symbol: await lpTokenContract.symbol(),
            token0: await token0Contract.symbol(),
            token1: await token1Contract.symbol()
        })
      }
      catch {

        poolData.push({
            token_address: poolInfo.lpToken,
            alloc_point: poolInfo.allocPoint.toString(),
            withdraw_fee: poolInfo.withdrawFeeBP.toString(),
            token_symbol: await lpTokenContract.symbol(),
            token0: "-",
            token1: "-"
        })

      }

      i = i.add("1");
    }

    console.table(poolData)

    console.log("pefi()", await masterChefContract.pefi());
}

module.exports = masterchefPenguin;