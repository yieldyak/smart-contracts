
const sweepTokens = async (tokenList, timelock) => {

    let formattedTokenList = () => {
        var nums = [];
        var entries = tokenList.split(',');
    
        var entry, low, high, range;
    
        for (let i = 0; i < entries.length; i++) {
            entry = entries[i];
    
            //smart way to check if indexOf() returns -1 (aka, no instance of '-' was found in entry)
            if (!~entry.indexOf('-')) {
                nums.push(+entry);
            } else {
                range = entry.split('-');
    
                //force to numbers
                low = +range[0];
                high = +range[1];
    
                //XOR swap, no need for an additional variable. still 3 steps though
                //http://en.wikipedia.org/wiki/XOR_swap_algorithm
                if(high < low){
                    low = low ^ high;
                    high = low ^ high;
                    low = low ^ high;
                }
    
                //push for every number starting from low
                while (low <= high) {
                    nums.push(low++);
                }
            }
        }
        return nums
    }
    
    const ABI = require("../abis/YakTimelockForDexStrategyV2");
    const ABI_ERC20 = require("../abis/IPair");
    const tokens = require("../constants/tokens");

    const accounts = await ethers.provider.listAccounts();
    const account = accounts[1];
    console.log(`Connected as ${account}`);
    let signer = ethers.provider.getSigner(account);

    const timelockContract = new ethers.Contract(timelock, ABI, signer);

    console.log(formattedTokenList());

    let tokensToSweep = [...tokens].filter(token => {
        let tokenSymbols = [...tokens].map(token=>token[0])
        return formattedTokenList().includes(tokenSymbols.indexOf(token[0]))
    })

    console.log(tokensToSweep);

    for (let t of tokensToSweep) {
        let tokenContract = new ethers.Contract(t[1], ABI_ERC20, ethers.provider);
        let balance = await tokenContract.balanceOf(timelock);
        let tx = await timelockContract.sweepTokens(t[1], balance);
        await tx.wait(1);
        console.log(tx.hash);
    }
}

module.exports = sweepTokens;