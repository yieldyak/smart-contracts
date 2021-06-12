const farmData = async (farm) => {

    function getContract(address, name) {
        let abi = require(`../abis/${name}.json`);
        return new ethers.Contract(address, abi, ethers.provider);
    }

    function alignRight(anyType, fineTune = 0) {
        return anyType.toString().padStart(50 + fineTune)
    }

    // initialize main contract
    const contract = getContract(farm, "DexStrategyV4");

    // get sub-contracts addresses
    let depositTokenAddress = await contract.depositToken();
    let rewardTokenAddress = await contract.rewardToken();
    let ownerAddress = await contract.owner();
    let stakingAddress = await contract.stakingContract();


    // initialize token contracts
    const depositTokenContract = getContract(depositTokenAddress, "IPangolinPair");
    const rewardTokenContract = getContract(rewardTokenAddress, "IPangolinERC20");

    // initialize owner contract
    const ownerContract = getContract(ownerAddress, "YakTimelockForDexStrategyV3")

    // initialize staking contract
    const stakingContract = getContract(stakingAddress, "IStakingRewards")

    // get all data to be displayed
    let depositTokenData = {
        address: depositTokenAddress,
        name: await depositTokenContract.name(),
        symbol: await depositTokenContract.symbol(),
        decimals: await depositTokenContract.decimals()
    };
    let rewardTokenData = {
        address: rewardTokenAddress,
        name: await rewardTokenContract.name(),
        symbol: await rewardTokenContract.symbol(),
        decimals: await rewardTokenContract.decimals()
    };
    let ownerData = {
        address: ownerAddress,
        anyChanges: async () => {
            let allChanges = new Map()

            await ownerContract.pendingAdminFees(farm).then(changes => {
                if (changes.toNumber() != 0) allChanges.set("adminFees", changes.toNumber() / 100)
            })
            await ownerContract.pendingDevFees(farm).then(changes => {
                if (changes.toNumber() != 0) allChanges.set("devFees", changes.toNumber() / 100)
            })
            await ownerContract.pendingOwners(farm).then(changes => {
                if (changes != "0x0000000000000000000000000000000000000000") allChanges.set("owners", changes)
            })
            await ownerContract.pendingReinvestRewards(farm).then(changes => {
                if (changes.toNumber() != 0) allChanges.set("reinvestRewards", changes.toNumber() / 100)
            })
            await ownerContract.pendingTokenAddressesToRecover(farm).then(changes => {
                if (changes != "0x0000000000000000000000000000000000000000") allChanges.set("tokenAddresses", changes)
            })
            await ownerContract.pendingTokenAmountsToRecover(farm).then(changes => {
                if (changes.toNumber() != 0) allChanges.set("tokenAmounts", changes)
            })

            return allChanges;

        }
    }
    let adminFees = await contract.ADMIN_FEE_BIPS().then(val => {
        return val.toNumber() / 100
    });
    let devFees = await contract.DEV_FEE_BIPS().then(val => {
        return val.toNumber() / 100
    });
    let reinvestRewards = await contract.REINVEST_REWARD_BIPS().then(val => {
        return val.toNumber() / 100
    });
    let totalFees = adminFees + devFees + reinvestRewards;
    let minTokens = await contract.MIN_TOKENS_TO_REINVEST();
    let totalDeposits = await contract.totalDeposits();
    let totalSupply = await contract.totalSupply();
    let pendingChanges = await ownerData.anyChanges();

    // display data
    console.log("\n                  __FEES INFO__ ");
    console.table([
        { feeType: "admin", amount: `${adminFees}%`, pending: pendingChanges.get("adminFees") ? `${pendingChanges.get("adminFees")}%` : '-' },
        { feeType: "dev", amount: `${devFees}%`, pending: pendingChanges.get("devFees") ? `${pendingChanges.get("devFees")}%` : '-' },
        { feeType: "reinvestRewards", amount: `${reinvestRewards}%`, pending: pendingChanges.get("reinvestRewards") ? `${pendingChanges.get("reinvestRewards")}%` : '-' },
        { feeType: "total", amount: `${totalFees}%`, pending: "" }
    ])
    console.log("\n\n                 __TOKEN INFO__ ");
    console.log("-Deposit Token");
    console.log(`address: ${alignRight(depositTokenData.address, 25)}`);
    console.log(`token: ${alignRight(depositTokenData.name, 3)} (${depositTokenData.symbol}) `);
    console.log(`decimals: ${alignRight(depositTokenData.decimals, -16)}`);
    console.log("\n-Reward Token");
    console.log(`token: ${alignRight(rewardTokenData.name, -9)} (${rewardTokenData.symbol}) `);
    console.log(`decimals: ${alignRight(rewardTokenData.decimals, -16)}`);
    console.log(`min tokens to invest: ${alignRight(ethers.utils.formatUnits(minTokens, rewardTokenData.decimals), -27)}`);
    console.log("\n\n               __CONTRACT INFO__ ");
    console.log(`totalDeposits: ${alignRight(ethers.utils.formatUnits(totalDeposits, depositTokenData.decimals))}`);
    console.log(`totalSupply: ${alignRight(ethers.utils.formatUnits(totalSupply, 18), 2)}`);
    console.log(`staking contract: ${alignRight(stakingContract, -11)}`);
};

module.exports = farmData;

    // #TODO: this structure is way more efficient since it allows to quickly query each category data. 
//   const stats = ["ADMIN_FEE_BIPS", 
//     "DEV_FEE_BIPS", 
//     "REINVEST_REWARD_BIPS",
//     "TOTAL_FEES_BIPS",
//     "MIN_TOKENS_TO_REINVEST",
//     "depositToken", //{address, name, symbol, decimals},
//     "rewardToken", //{address, name, symbol, decimals},
//     "totalDeposits",
//     "totalSupply",
//     "stakingContract", 
//     "owner"];

//   var data = new Map()
//   stats.forEach(stat => {
//     if(stat == "TOTAL_FEES_BIPS") return;
//     console.log(`\nfetching ${stat}...`);
//     let value = contract[stat]() // each value is a promise.
//     data.set(stat, value)
//     console.log(`${stat}: ${data.get(stat)}`);
//   })

//   console.log(Array.from(data.values()));  // array of promises  

//   Promise.all(Array.from(data.values())).then(values => { //this should wait until all promises are fulfilled.
//       console.log("done");
//       console.log(values);
//     })