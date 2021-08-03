const {expect} = require("chai")
const {ethers, run} = require("hardhat")
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
    let WAVAX
    let ELK
    let ELK_ROUTER
    let elkPair
    let stakingContract
    beforeEach(async () => {
        let accounts = await ethers.getSigners()
        owner = accounts[0]
        account1 = accounts[1]
        account2 = accounts[2]
        timelock_address = "0x8d36C5c6947ADCcd25Ef49Ea1aAC2ceACFff0bD7"
        elkPair = await ethers.getContractAt(elk_pair, "0x2612dA8fc26Efbca3cC3F8fD543BCBa72b10aB59");
        ELK_ROUTER = await ethers.getContractAt(elk_router, "0x9E4AAbd2B3E60Ee1322E94307d0776F2c8e6CFbb");
        stakingContract = await ethers.getContractAt(staking_contract, "0xA811738E247b27ec3C82873b4273425b5355bd71");
        const elkILPStrategyV5Factory = await ethers.getContractFactory("ELKILPStrategyV5")
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
            // We approve addresses
            await WAVAX.approve(ELK_ROUTER.address, BigNumber.from("1000000000000000000000000"));
            await ELK.approve(ELK_ROUTER.address, BigNumber.from("1000000000000000000000000"));
            await elkPair.approve(elkILPStrategyV5.address, BigNumber.from("1000000000000000000000000"));

            await ELK_ROUTER.swapExactTokensForTokens(BigNumber.from("10000000000000000"), BigNumber.from("5000000000000000"), [WAVAX.address, ELK.address], owner.address, 1807909162115)
            await ELK_ROUTER.addLiquidity(WAVAX.address, ELK.address, await WAVAX.balanceOf(owner.address), await ELK.balanceOf(owner.address), 0, 0, owner.address, 1807909162115)
        })

        it('Deposit correct amount of ELK Liquidity token into the strategy', async () => {
            // We get the amount of ELK token we have
            const amount = (await elkPair.balanceOf(owner.address)).toString();
            // We get the 'totalDeposit' before we deposit into the strategy
            const totalDepositsBefore = (await elkILPStrategyV5.totalDeposits()).toString();

            // We deposit our ELP tokens into the strategy
            await elkILPStrategyV5.deposit(BigNumber.from((await elkPair.balanceOf(owner.address)).toString()))
            // We get the 'totalDeposit' after our deposit
            const totalDepositsAfter = (await elkILPStrategyV5.totalDeposits()).toString();

            // Our balance should be equal to the amount of ELP token we deposited
            expect((await elkILPStrategyV5.balanceOf(owner.address)).toString()).to.equal(amount)
            // The strategy contract should have correct balance on the staking contract
            expect((await stakingContract.balanceOf(elkILPStrategyV5.address)).toString()).to.equal(amount)

            // We check if the totalDeposit has grown after our deposit
            expect(BigNumber.from(totalDepositsAfter)).gt(BigNumber.from(totalDepositsBefore));
        })
    })

    describe("Test withdraw functionality", async () => {
        beforeEach(async () => {
            await WAVAX.approve(ELK_ROUTER.address, BigNumber.from("1000000000000000000000000"));
            await ELK.approve(ELK_ROUTER.address, BigNumber.from("1000000000000000000000000"));
            await elkPair.approve(elkILPStrategyV5.address, BigNumber.from("1000000000000000000000000"));

            await ELK_ROUTER.swapExactTokensForTokens(BigNumber.from("10000000000000000"), BigNumber.from("5000000000000000"), [WAVAX.address, ELK.address], owner.address, 1807909162115)
            await ELK_ROUTER.addLiquidity(WAVAX.address, ELK.address, await WAVAX.balanceOf(owner.address), await ELK.balanceOf(owner.address), 0, 0, owner.address, 1807909162115)
        })

        it('Withdraw correctly our ELP tokens from the Strategy', async () => {
            // We get the amount of ELK token we have
            const amount = (await elkPair.balanceOf(owner.address)).toString();
            // We get the 'totalDeposit' before we deposit into the strategy
            const totalDepositsBefore = (await elkILPStrategyV5.totalDeposits()).toString();

            // We deposit into the staking contract our ELP tokens
            await elkILPStrategyV5.deposit(BigNumber.from((await elkPair.balanceOf(owner.address)).toString()))
            // We get the 'totalDeposit' after our deposit into the strategy
            const totalDepositsAfter = (await elkILPStrategyV5.totalDeposits()).toString();

            // We make sure all balances are correct .
            expect((await elkILPStrategyV5.balanceOf(owner.address)).toString()).to.equal(amount)
            expect((await stakingContract.balanceOf(elkILPStrategyV5.address)).toString()).to.equal(amount)
            expect(BigNumber.from(totalDepositsAfter)).gt(BigNumber.from(totalDepositsBefore));

            // We withdraw from the strategy all tokens we deposited
            await elkILPStrategyV5.withdraw(BigNumber.from((await elkILPStrategyV5.balanceOf(owner.address)).toString()))

            // We check if balances are correct
            expect((await elkILPStrategyV5.balanceOf(owner.address)).toString()).to.equal("0")
            expect((await stakingContract.balanceOf(elkILPStrategyV5.address)).toString()).to.equal("0")
            expect(BigNumber.from(totalDepositsAfter)).gt(BigNumber.from(totalDepositsBefore));
            expect(await elkPair.balanceOf(owner.address)).gt("0");
        })
    })

    describe("Test coverage on withdraw", async () => {

        beforeEach(async () => {
            await WAVAX.approve(ELK_ROUTER.address, BigNumber.from("1000000000000000000000000"));
            await ELK.approve(ELK_ROUTER.address, BigNumber.from("1000000000000000000000000"));
            await elkPair.approve(elkILPStrategyV5.address, BigNumber.from("1000000000000000000000000"));

            await ELK_ROUTER.swapExactTokensForTokens(BigNumber.from("10000000000000000"), BigNumber.from("5000000000000000"), [WAVAX.address, ELK.address], owner.address, 1807909162115)
            await ELK_ROUTER.addLiquidity(WAVAX.address, ELK.address, await WAVAX.balanceOf(owner.address), await ELK.balanceOf(owner.address), 0, 0, owner.address, 1807909162115)
        })

        it('Withdraw correct amount of ELK Liquidity token from the strategy', async () => {
            // We get the amount of ELK token we have
            const amount = (await elkPair.balanceOf(owner.address)).toString();
            // We get the 'totalDeposit' before we deposit into the strategy
            const totalDepositsBefore = (await elkILPStrategyV5.totalDeposits()).toString();

            // We deposit into the staking contract our ELP tokens
            await elkILPStrategyV5.deposit(BigNumber.from((await elkPair.balanceOf(owner.address)).toString()))
            // We get the 'totalDeposit' after our deposit into the strategy
            const totalDepositsAfter = (await elkILPStrategyV5.totalDeposits()).toString();

            // We check all balances
            expect((await elkILPStrategyV5.balanceOf(owner.address)).toString()).to.equal(amount)
            expect((await stakingContract.balanceOf(elkILPStrategyV5.address)).toString()).to.equal(amount)
            expect(BigNumber.from(totalDepositsAfter)).gt(BigNumber.from(totalDepositsBefore));
            expect((await stakingContract.coverageOf(elkILPStrategyV5.address)).toString()).to.equal("0")

            // We impersonate the 'owner' of the WAVAX-ELK StakingRewardsILP contract
            await ethers.provider.send('hardhat_impersonateAccount', ['0xba49776326A1ca54EB4F406C94Ae4e1ebE458E19']);
            admin = await ethers.provider.getSigner('0xba49776326A1ca54EB4F406C94Ae4e1ebE458E19')

            const stakingcontract = await ethers.getContractAt(staking_contract, "0xA811738E247b27ec3C82873b4273425b5355bd71", admin);
            // We set the coverage amount for our Strategy
            await stakingcontract.setCoverageAmount(elkILPStrategyV5.address, 100000000);

            await hre.network.provider.request({
                method: "hardhat_stopImpersonatingAccount",
                params: ["0xba49776326A1ca54EB4F406C94Ae4e1ebE458E19"],
            });

            // We check the amount of coverage the Strategy contract address currently has
            expect((await stakingContract.coverageOf(elkILPStrategyV5.address)).toString()).to.equal('100000000')
            expect((await elkILPStrategyV5.checkCoverage()).toString()).to.equal('100000000')
        })
    })
})
