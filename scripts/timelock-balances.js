const timelockBalances = async (contract) => {

    const ABI_ERC20 = require("../abis/IPair")

    const tokens = require("../constants/tokens");

    for (let [name, address] of tokens) {
        let tokenContract = new ethers.Contract(address, ABI_ERC20, ethers.provider);
        let balance = await tokenContract.balanceOf(contract);
        let decimals = await tokenContract.decimals();
        tokens.set(name, {"address": address, "tokenContract": tokenContract, "balance": balance, "decimals": decimals}); // set a token contract for each token as values of the map
    }

    console.table([...tokens.entries()].map(elem=>{
        return {
            symbol: elem[0], 
            balance: ethers.utils.formatUnits(elem[1].balance, elem[1].decimals)
        }
    }))

    console.log(`timelock address: ${contract}`);

};

module.exports = timelockBalances;
