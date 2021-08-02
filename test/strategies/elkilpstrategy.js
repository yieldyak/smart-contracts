const {expect} = require("chai")
const {ethers, run} = require("hardhat")
const elk_pair = require("../resources/abis/ElkPair.json");
const elk_router = require("../resources/abis/ElkRouter.json");
const staking_contract = require("../resources/abis/StakingRewardsILPV2.json");
const {BigNumber} = ethers

const MAX_UINT = "115792089237316195423570985008687907853269984665640564039457584007913129639935";

describe("ELKILPStrategyV5", function () {

    const elk_pair = require("../resources/abis/ElkPair.json");
    const elk_router = require("../resources/abis/ElkRouter.json");


    before(async () => {
        await run("compile")
    })

    let owner
    let account1
    let account2
    let timelock_address
    let tokenFeeCollector
    let WAVAX
    let ELK
    let ELK_ROUTER
    let elkPair
    let StakingRewardsILPV2
    let stakingContract
    beforeEach(async () => {
        let accounts = await ethers.getSigners()
        owner = accounts[0]
        account1 = accounts[1]
        account2 = accounts[2]
        timelock_address = "0x8d36C5c6947ADCcd25Ef49Ea1aAC2ceACFff0bD7"
        // 0xfEbf47CF89F766E6c24317b17F862bA5d4d82f8c is the address of ELK-WAVAX liquidity pool
        elkPair = await ethers.getContractAt(elk_pair, "0x2612dA8fc26Efbca3cC3F8fD543BCBa72b10aB59");
        ELK_ROUTER = await ethers.getContractAt(elk_router, "0x9E4AAbd2B3E60Ee1322E94307d0776F2c8e6CFbb");
        stakingContract = await ethers.getContractAt(staking_contract, "0xA811738E247b27ec3C82873b4273425b5355bd71");
        // console.log(elkPairFactory);
        // console.log(await elkPairFactory.getReserves());
        // console.log(elkPairFactory.address);
        const elkILPStrategyV5Factory = await ethers.getContractFactory("ELKILPStrategyV5")
        // string memory _name,
        //     address _depositToken, An ELKP Token
        //     address _rewardToken,  ElkToken address
        //     address _stakingContract, StakingReward Address
        //     address _swapPairToken0, ELKP.0
        //     address _swapPairToken1, ELKP.1
        //     address _timelock,
        //     uint _minTokensToReinvest,
        //     uint _adminFeeBips,
        //     uint _devFeeBips,
        //     uint _reinvestRewardBips
        elkILPStrategyV5 = await elkILPStrategyV5Factory.deploy(
            "ElkIlpStrategy-Test",
            "0x2612dA8fc26Efbca3cC3F8fD543BCBa72b10aB59", // Deposit token is the ELK-WAVAX liquidity pool address
            "0xE1C110E1B1b4A1deD0cAf3E42BfBdbB7b5d7cE1C", // Address for ELK Token
            "0xA811738E247b27ec3C82873b4273425b5355bd71", // Address of the StakingRewardsILPV2 for ELK-WAVAX farm
            "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7", // Address of swapPair token 1 (WAVAX),
            "0xE1C110E1B1b4A1deD0cAf3E42BfBdbB7b5d7cE1C", // Address of swapPair token 0 (ELK)
            "0x8d36C5c6947ADCcd25Ef49Ea1aAC2ceACFff0bD7", // Timelock contract for YY
            1,
            1,
            1,
            1
        )
        await elkILPStrategyV5.deployed()
        WAVAX = await ethers.getContractAt("IWAVAX", "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7")
        ELK = await ethers.getContractAt("IWAVAX", "0xE1C110E1B1b4A1deD0cAf3E42BfBdbB7b5d7cE1C")
        //makes sure owner has enough WAVAX balance
        if ((await WAVAX.balanceOf(owner.address)).lt("1000000000000000000000")) {
            WAVAX.connect(owner).deposit({
                value: BigNumber.from("1000000000000000000000")
                    .sub(await WAVAX.balanceOf(owner.address))
            })
        }
        //
        // //makes sure other accounts are clean
        // if ((await WAVAX.balanceOf(account1.address)).gt(0)) {
        //     await WAVAX.connect(account1).withdraw((await WAVAX.balanceOf(account1.address)))
        // }
        // if ((await WAVAX.balanceOf(account2.address)).gt(0)) {
        //     await WAVAX.connect(account2).withdraw((await WAVAX.balanceOf(account2.address)))
        // }
    })

    describe("Test basic functionalities", async () => {

        it('Can deploy', async () => {
            expect(await elkILPStrategyV5.owner()).to.equal(timelock_address)
        })

        it('Set correctly the _minTokensToReinvest', async () => {
            expect(await elkILPStrategyV5.MIN_TOKENS_TO_REINVEST()).to.equal(1)
        })

        it('Set correctly the _adminFeeBips', async () => {
            expect(await elkILPStrategyV5.ADMIN_FEE_BIPS()).to.equal(1)
        })

        it('Set correctly the _devFeeBips', async () => {
            expect(await elkILPStrategyV5.DEV_FEE_BIPS()).to.equal(1)
        })

        it('Set correctly the _reinvestRewardBips', async () => {
            expect(await elkILPStrategyV5.REINVEST_REWARD_BIPS()).to.equal(1)
        })

        it('Set correctly the devAddr', async () => {
            expect(await elkILPStrategyV5.devAddr()).to.equal(owner.address)
        })

        it('Set correctly the allowance on the deposit token', async () => {
            expect(await elkPair.allowance(elkILPStrategyV5.address, "0xA811738E247b27ec3C82873b4273425b5355bd71")).to.equal(MAX_UINT)
        })

    });

    describe("Test deposit functionality", async () => {

        beforeEach(async () => {
            // We need to get some ELK tokens

            console.log("AAA");
            console.log((await WAVAX.balanceOf(owner.address)).toString());
            console.log("BBB");
            console.log((await ELK.balanceOf(owner.address)).toString());
            console.log("CCC");
            console.log((await elkPair.balanceOf(owner.address)).toString());
            await WAVAX.approve(ELK_ROUTER.address, BigNumber.from("1000000000000000000000000"));
            await WAVAX.approve(elkPair.address, BigNumber.from("1000000000000000000000000"));
            await WAVAX.approve(elkILPStrategyV5.address, BigNumber.from("1000000000000000000000000"));
            await ELK.approve(elkPair.address, BigNumber.from("1000000000000000000000000"));
            await ELK.approve(ELK_ROUTER.address, BigNumber.from("1000000000000000000000000"));
            await ELK.approve(elkILPStrategyV5.address, BigNumber.from("1000000000000000000000000"));
            await elkPair.approve(ELK_ROUTER.address, BigNumber.from("1000000000000000000000000"));
            await elkPair.approve(elkPair.address, BigNumber.from("1000000000000000000000000"));
            await elkPair.approve(owner.address, BigNumber.from("1000000000000000000000000"));
            await elkPair.approve(elkILPStrategyV5.address, BigNumber.from("1000000000000000000000000"));
            await elkILPStrategyV5.approve(ELK_ROUTER.address, BigNumber.from("1000000000000000000000000"));
            await elkILPStrategyV5.approve(elkPair.address, BigNumber.from("1000000000000000000000000"));
            await ELK_ROUTER.swapExactTokensForTokens(BigNumber.from("10000000000000000"), BigNumber.from("5000000000000000"), [WAVAX.address, ELK.address], owner.address, 1807909162115)
            // address tokenA,
            //     address tokenB,
            //     uint amountADesired,
            //     uint amountBDesired,
            //     uint amountAMin,
            //     uint amountBMin,
            //     address to,
            //     uint deadline
            const lptokens = await ELK_ROUTER.addLiquidity(WAVAX.address, ELK.address, await WAVAX.balanceOf(owner.address), await ELK.balanceOf(owner.address), 0, 0, owner.address, 1807909162115)
            console.dir(lptokens);
        })

        it('Deposit correct amount of ELK Liquidity token into the strategy', async () => {
            // const signer = await ethers.provider.getSigner(
            //     "0xfEbf47CF89F766E6c24317b17F862bA5d4d82f8c"
            // );
            // signer.se
            // await elkILPStrategyV5.deposit()
            // expect().to.equal(MAX_UINT)
            console.log("EEE");
            console.log((await WAVAX.balanceOf(owner.address)).toString());
            console.log("FFF");
            console.log((await ELK.balanceOf(owner.address)).toString());
            console.log("GGG");
            console.log((await elkPair.balanceOf(owner.address)).toString());
            const amount = (await elkPair.balanceOf(owner.address)).toString();
            const totalDepositsBefore = (await elkILPStrategyV5.totalDeposits()).toString();
            console.log("HHH");
            console.log((await elkILPStrategyV5.balanceOf(owner.address)).toString());
            await elkILPStrategyV5.approve(elkILPStrategyV5.address, BigNumber.from((await elkPair.balanceOf(owner.address)).toString()));
            await elkILPStrategyV5.deposit(BigNumber.from((await elkPair.balanceOf(owner.address)).toString()))
            const totalDepositsAfter = (await elkILPStrategyV5.totalDeposits()).toString();

            console.log("III");
            console.log((await elkPair.balanceOf(owner.address)).toString());
            console.log("JJJ");
            console.log((await elkILPStrategyV5.balanceOf(owner.address)).toString());
            expect((await elkILPStrategyV5.balanceOf(owner.address)).toString()).to.equal(amount)
            expect((await stakingContract.balanceOf(elkILPStrategyV5.address)).toString()).to.equal(amount)
            expect(BigNumber.from(totalDepositsAfter)).gt(BigNumber.from(totalDepositsBefore));
        })
    })

    describe("Test withdraw functionality", async () => {

        let admin

        beforeEach(async () => {
            // We need to get some ELK tokens
            // 0xba49776326A1ca54EB4F406C94Ae4e1ebE458E19
            console.log("AAA");
            console.log((await WAVAX.balanceOf(owner.address)).toString());
            console.log("BBB");
            console.log((await ELK.balanceOf(owner.address)).toString());
            console.log("CCC");
            console.log((await elkPair.balanceOf(owner.address)).toString());
            await WAVAX.approve(ELK_ROUTER.address, BigNumber.from("1000000000000000000000000"));
            await WAVAX.approve(elkPair.address, BigNumber.from("1000000000000000000000000"));
            await WAVAX.approve(elkILPStrategyV5.address, BigNumber.from("1000000000000000000000000"));
            await ELK.approve(elkPair.address, BigNumber.from("1000000000000000000000000"));
            await ELK.approve(ELK_ROUTER.address, BigNumber.from("1000000000000000000000000"));
            await ELK.approve(elkILPStrategyV5.address, BigNumber.from("1000000000000000000000000"));
            await elkPair.approve(ELK_ROUTER.address, BigNumber.from("1000000000000000000000000"));
            await elkPair.approve(elkPair.address, BigNumber.from("1000000000000000000000000"));
            await elkPair.approve(owner.address, BigNumber.from("1000000000000000000000000"));
            await elkPair.approve(elkILPStrategyV5.address, BigNumber.from("1000000000000000000000000"));
            await elkILPStrategyV5.approve(ELK_ROUTER.address, BigNumber.from("1000000000000000000000000"));
            await elkILPStrategyV5.approve(elkPair.address, BigNumber.from("1000000000000000000000000"));
            await ELK_ROUTER.swapExactTokensForTokens(BigNumber.from("10000000000000000"), BigNumber.from("5000000000000000"), [WAVAX.address, ELK.address], owner.address, 1807909162115)
            // address tokenA,
            //     address tokenB,
            //     uint amountADesired,
            //     uint amountBDesired,
            //     uint amountAMin,
            //     uint amountBMin,
            //     address to,
            //     uint deadline
            const lptokens = await ELK_ROUTER.addLiquidity(WAVAX.address, ELK.address, await WAVAX.balanceOf(owner.address), await ELK.balanceOf(owner.address), 0, 0, owner.address, 1807909162115)
            console.dir(lptokens);
        })

        it('Deposit correct amount of ELK Liquidity token into the strategy', async () => {
            // const signer = await ethers.provider.getSigner(
            //     "0xfEbf47CF89F766E6c24317b17F862bA5d4d82f8c"
            // );
            // signer.se
            // await elkILPStrategyV5.deposit()
            // expect().to.equal(MAX_UINT)
            console.log("EEE");
            console.log((await WAVAX.balanceOf(owner.address)).toString());
            console.log("FFF");
            console.log((await ELK.balanceOf(owner.address)).toString());
            console.log("GGG");
            console.log((await elkPair.balanceOf(owner.address)).toString());
            const amount = (await elkPair.balanceOf(owner.address)).toString();
            const totalDepositsBefore = (await elkILPStrategyV5.totalDeposits()).toString();
            console.log("HHH");
            console.log((await elkILPStrategyV5.balanceOf(owner.address)).toString());
            await elkILPStrategyV5.approve(elkILPStrategyV5.address, BigNumber.from((await elkPair.balanceOf(owner.address)).toString()));
            await elkILPStrategyV5.deposit(BigNumber.from((await elkPair.balanceOf(owner.address)).toString()))
            const totalDepositsAfter = (await elkILPStrategyV5.totalDeposits()).toString();

            console.log("III");
            console.log((await elkPair.balanceOf(owner.address)).toString());
            console.log("JJJ");
            console.log((await elkILPStrategyV5.balanceOf(owner.address)).toString());
            expect((await elkILPStrategyV5.balanceOf(owner.address)).toString()).to.equal(amount)
            expect((await stakingContract.balanceOf(elkILPStrategyV5.address)).toString()).to.equal(amount)
            expect(BigNumber.from(totalDepositsAfter)).gt(BigNumber.from(totalDepositsBefore));
            await elkILPStrategyV5.withdraw(BigNumber.from((await elkILPStrategyV5.balanceOf(owner.address)).toString()))
            expect((await elkILPStrategyV5.balanceOf(owner.address)).toString()).to.equal("0")
            expect((await stakingContract.balanceOf(elkILPStrategyV5.address)).toString()).to.equal("0")
            expect(BigNumber.from(totalDepositsAfter)).gt(BigNumber.from(totalDepositsBefore));
        })
    })

    describe("Test coverage on withdraw", async () => {

        beforeEach(async () => {
            // We need to get some ELK tokens

            console.log("AAA");
            console.log((await WAVAX.balanceOf(owner.address)).toString());
            console.log("BBB");
            console.log((await ELK.balanceOf(owner.address)).toString());
            console.log("CCC");
            console.log((await elkPair.balanceOf(owner.address)).toString());
            await WAVAX.approve(ELK_ROUTER.address, BigNumber.from("1000000000000000000000000"));
            await WAVAX.approve(elkPair.address, BigNumber.from("1000000000000000000000000"));
            await WAVAX.approve(elkILPStrategyV5.address, BigNumber.from("1000000000000000000000000"));
            await ELK.approve(elkPair.address, BigNumber.from("1000000000000000000000000"));
            await ELK.approve(ELK_ROUTER.address, BigNumber.from("1000000000000000000000000"));
            await ELK.approve(elkILPStrategyV5.address, BigNumber.from("1000000000000000000000000"));
            await elkPair.approve(ELK_ROUTER.address, BigNumber.from("1000000000000000000000000"));
            await elkPair.approve(elkPair.address, BigNumber.from("1000000000000000000000000"));
            await elkPair.approve(owner.address, BigNumber.from("1000000000000000000000000"));
            await elkPair.approve(elkILPStrategyV5.address, BigNumber.from("1000000000000000000000000"));
            await elkILPStrategyV5.approve(ELK_ROUTER.address, BigNumber.from("1000000000000000000000000"));
            await elkILPStrategyV5.approve(elkPair.address, BigNumber.from("1000000000000000000000000"));
            await ELK_ROUTER.swapExactTokensForTokens(BigNumber.from("10000000000000000"), BigNumber.from("5000000000000000"), [WAVAX.address, ELK.address], owner.address, 1807909162115)
            // address tokenA,
            //     address tokenB,
            //     uint amountADesired,
            //     uint amountBDesired,
            //     uint amountAMin,
            //     uint amountBMin,
            //     address to,
            //     uint deadline
            const lptokens = await ELK_ROUTER.addLiquidity(WAVAX.address, ELK.address, await WAVAX.balanceOf(owner.address), await ELK.balanceOf(owner.address), 0, 0, owner.address, 1807909162115)
            console.dir(lptokens);
        })

        it('Deposit correct amount of ELK Liquidity token into the strategy', async () => {
            // const signer = await ethers.provider.getSigner(
            //     "0xfEbf47CF89F766E6c24317b17F862bA5d4d82f8c"
            // );
            // signer.se
            // await elkILPStrategyV5.deposit()
            // expect().to.equal(MAX_UINT)
            console.log("EEE");
            console.log((await WAVAX.balanceOf(owner.address)).toString());
            console.log("FFF");
            console.log((await ELK.balanceOf(owner.address)).toString());
            console.log("GGG");
            console.log((await elkPair.balanceOf(owner.address)).toString());
            const amount = (await elkPair.balanceOf(owner.address)).toString();
            const totalDepositsBefore = (await elkILPStrategyV5.totalDeposits()).toString();
            console.log("HHH");
            console.log((await elkILPStrategyV5.balanceOf(owner.address)).toString());
            await elkILPStrategyV5.approve(elkILPStrategyV5.address, BigNumber.from((await elkPair.balanceOf(owner.address)).toString()));
            await elkILPStrategyV5.deposit(BigNumber.from((await elkPair.balanceOf(owner.address)).toString()))
            const totalDepositsAfter = (await elkILPStrategyV5.totalDeposits()).toString();

            console.log("III");
            console.log((await elkPair.balanceOf(owner.address)).toString());
            console.log("JJJ");
            console.log((await elkILPStrategyV5.balanceOf(owner.address)).toString());
            expect((await elkILPStrategyV5.balanceOf(owner.address)).toString()).to.equal(amount)
            expect((await stakingContract.balanceOf(elkILPStrategyV5.address)).toString()).to.equal(amount)
            expect(BigNumber.from(totalDepositsAfter)).gt(BigNumber.from(totalDepositsBefore));
            expect((await stakingContract.coverageOf(elkILPStrategyV5.address)).toString()).to.equal("0")
            await ethers.provider.send('hardhat_impersonateAccount', ['0xba49776326A1ca54EB4F406C94Ae4e1ebE458E19']);
            admin = await ethers.provider.getSigner('0xba49776326A1ca54EB4F406C94Ae4e1ebE458E19')

            const stakingcontract = await ethers.getContractAt(staking_contract, "0xA811738E247b27ec3C82873b4273425b5355bd71", admin);
            await stakingcontract.setCoverageAmount(elkILPStrategyV5.address, 100000000);

            await hre.network.provider.request({
                method: "hardhat_stopImpersonatingAccount",
                params: ["0xba49776326A1ca54EB4F406C94Ae4e1ebE458E19"],
            });

            expect((await stakingContract.coverageOf(elkILPStrategyV5.address)).toString()).to.equal('100000000')

            expect((await elkILPStrategyV5.checkCoverage()).toString()).to.equal('100000000')

        })
    })

})
