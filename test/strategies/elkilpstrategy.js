const {expect} = require("chai")
const {ethers, run} = require("hardhat")
const staking_contract = require("../resources/abis/StakingRewardsILPV2.json");
const {BigNumber} = ethers

const MAX_UINT = "115792089237316195423570985008687907853269984665640564039457584007913129639935";

describe("elk_ilp_strategy_v5", function () {

    const elk_pair = require("../resources/abis/ElkPair.json");
    const elk_router = require("../resources/abis/ElkRouter.json");

    before(async () => {
        await run("compile")
    })

    let owner
    let account1
    let account2
    const timelockAddress = "0x8d36C5c6947ADCcd25Ef49Ea1aAC2ceACFff0bD7"
    const depositTokenAddress = "0x2612dA8fc26Efbca3cC3F8fD543BCBa72b10aB59"
    const elkTokenAddress = "0xE1C110E1B1b4A1deD0cAf3E42BfBdbB7b5d7cE1C"
    const wavaxTokenAddress = "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7"
    const elkRouterAddress = "0x9E4AAbd2B3E60Ee1322E94307d0776F2c8e6CFbb"
    const elpStakingRewardAddress = "0xA811738E247b27ec3C82873b4273425b5355bd71"
    
    let wavaxTokenContract
    let elkTokenContract
    let elkRouterContract
    let elkPairContract
    let stakingContract
    let elkIlpStrategyV5
    beforeEach(async () => {
        let accounts = await ethers.getSigners()
        owner = accounts[0]
        account1 = accounts[1]
        account2 = accounts[2]
        
        elkPairContract = await ethers.getContractAt(elk_pair, depositTokenAddress);
        elkRouterContract = await ethers.getContractAt(elk_router, elkRouterAddress);
        stakingContract = await ethers.getContractAt(staking_contract, elpStakingRewardAddress);
        const elkILPStrategyV5Factory = await ethers.getContractFactory("ELKILPStrategyV5")
        elkIlpStrategyV5 = await elkILPStrategyV5Factory.deploy(
            "ElkIlpStrategy-Test",
            depositTokenAddress, // Deposit token is the ELK-WAVAX liquidity pool address
            elkTokenAddress, // Address for ELK Token
            elpStakingRewardAddress, // Address of the StakingRewardsILPV2 for ELK-WAVAX farm
            wavaxTokenAddress, // Address of swapPair token 1 (WAVAX),
            elkTokenAddress, // Address of swapPair token 0 (ELK)
            timelockAddress, // Timelock contract for YY
            1,
            1,
            1,
            1
        )
        await elkIlpStrategyV5.deployed()
        wavaxTokenContract = await ethers.getContractAt("IWAVAX", wavaxTokenAddress)
        elkTokenContract = await ethers.getContractAt("IWAVAX", elkTokenAddress)
        //makes sure owner has enough WAVAX balance
        if ((await wavaxTokenContract.balanceOf(owner.address)).lt("1000000000000000000000")) {
            wavaxTokenContract.connect(owner).deposit({
                value: BigNumber.from("1000000000000000000000")
                    .sub(await wavaxTokenContract.balanceOf(owner.address))
            })
        }
        if ((await wavaxTokenContract.balanceOf(account1.address)).lt("1000000000000000000000")) {
            wavaxTokenContract.connect(account1).deposit({
                value: BigNumber.from("1000000000000000000000")
                    .sub(await wavaxTokenContract.balanceOf(account1.address))
            })
        }
    })

    describe("Test basic functionalities", async () => {

    it('Can deploy', async () => {
        expect(await elkIlpStrategyV5.owner()).to.equal(timelockAddress)
    })

    it('Set correctly the _minTokensToReinvest', async () => {
        expect(await elkIlpStrategyV5.MIN_TOKENS_TO_REINVEST()).to.equal(1)
    })

    it('Set correctly the _adminFeeBips', async () => {
        expect(await elkIlpStrategyV5.ADMIN_FEE_BIPS()).to.equal(1)
    })

    it('Set correctly the _devFeeBips', async () => {
        expect(await elkIlpStrategyV5.DEV_FEE_BIPS()).to.equal(1)
    })

    it('Set correctly the _reinvestRewardBips', async () => {
        expect(await elkIlpStrategyV5.REINVEST_REWARD_BIPS()).to.equal(1)
    })

    it('Set correctly the devAddr', async () => {
        expect(await elkIlpStrategyV5.devAddr()).to.equal(owner.address)
    })

    it('Set correctly the allowance on the deposit token', async () => {
        expect(await elkPairContract.allowance(elkIlpStrategyV5.address, elpStakingRewardAddress)).to.equal(MAX_UINT)
    })

    });

    describe("Test deposit functionality", async () => {

        beforeEach(async () => {
            // We approve addresses
            await wavaxTokenContract.approve(elkRouterContract.address, BigNumber.from("1000000000000000000000000"));
            await elkTokenContract.approve(elkRouterContract.address, BigNumber.from("1000000000000000000000000"));
            await elkPairContract.approve(elkIlpStrategyV5.address, BigNumber.from("1000000000000000000000000"));

            await elkRouterContract.swapExactTokensForTokens(BigNumber.from("10000000000000000"), BigNumber.from("5000000000000000"), [wavaxTokenContract.address, elkTokenContract.address], owner.address, 1807909162115)
            await elkRouterContract.addLiquidity(wavaxTokenContract.address, elkTokenContract.address, await wavaxTokenContract.balanceOf(owner.address), await elkTokenContract.balanceOf(owner.address), 0, 0, owner.address, 1807909162115)
        })

        it('Deposit correct amount of ELK Liquidity token into the strategy', async () => {
            // We get the amount of ELK token we have
            const amount = (await elkPairContract.balanceOf(owner.address)).toString();
            // We get the 'totalDeposit' before we deposit into the strategy
            const totalDepositsBefore = (await elkIlpStrategyV5.totalDeposits()).toString();

            // We deposit our ELP tokens into the strategy
            await elkIlpStrategyV5.deposit(BigNumber.from((await elkPairContract.balanceOf(owner.address)).toString()))
            // We get the 'totalDeposit' after our deposit
            const totalDepositsAfter = (await elkIlpStrategyV5.totalDeposits()).toString();

            // Our balance should be equal to the amount of ELP token we deposited
            expect((await elkIlpStrategyV5.balanceOf(owner.address)).toString()).to.equal(amount)
            // The strategy contract should have correct balance on the staking contract
            expect((await stakingContract.balanceOf(elkIlpStrategyV5.address)).toString()).to.equal(amount)

            // We check if the totalDeposit has grown after our deposit
            expect(BigNumber.from(totalDepositsAfter)).gt(BigNumber.from(totalDepositsBefore));
        })
    })

    describe("Test withdraw functionality", async () => {
        beforeEach(async () => {
            await wavaxTokenContract.approve(elkRouterContract.address, BigNumber.from("1000000000000000000000000"));
            await elkTokenContract.approve(elkRouterContract.address, BigNumber.from("1000000000000000000000000"));
            await elkPairContract.approve(elkIlpStrategyV5.address, BigNumber.from("1000000000000000000000000"));

            await elkRouterContract.swapExactTokensForTokens(BigNumber.from("10000000000000000"), BigNumber.from("5000000000000000"), [wavaxTokenContract.address, elkTokenContract.address], owner.address, 1807909162115)
            await elkRouterContract.addLiquidity(wavaxTokenContract.address, elkTokenContract.address, await wavaxTokenContract.balanceOf(owner.address), await elkTokenContract.balanceOf(owner.address), 0, 0, owner.address, 1807909162115)
        })

        it('Withdraw correctly our ELP tokens from the Strategy', async () => {
            // We get the amount of ELK token we have
            const amount = (await elkPairContract.balanceOf(owner.address)).toString();
            // We get the 'totalDeposit' before we deposit into the strategy
            const totalDepositsBefore = (await elkIlpStrategyV5.totalDeposits()).toString();

            // We deposit into the staking contract our ELP tokens
            await elkIlpStrategyV5.deposit(BigNumber.from((await elkPairContract.balanceOf(owner.address)).toString()))
            // We get the 'totalDeposit' after our deposit into the strategy
            const totalDepositsAfter = (await elkIlpStrategyV5.totalDeposits()).toString();

            // We make sure all balances are correct .
            expect((await elkIlpStrategyV5.balanceOf(owner.address)).toString()).to.equal(amount)
            expect((await stakingContract.balanceOf(elkIlpStrategyV5.address)).toString()).to.equal(amount)
            expect(BigNumber.from(totalDepositsAfter)).gt(BigNumber.from(totalDepositsBefore));

            // We withdraw from the strategy all tokens we deposited
            await elkIlpStrategyV5.withdraw(BigNumber.from((await elkIlpStrategyV5.balanceOf(owner.address)).toString()))

            // We check if balances are correct
            expect((await elkIlpStrategyV5.balanceOf(owner.address)).toString()).to.equal("0")
            expect((await stakingContract.balanceOf(elkIlpStrategyV5.address)).toString()).to.equal("0")
            expect(BigNumber.from(totalDepositsAfter)).gt(BigNumber.from(totalDepositsBefore));
            expect(await elkPairContract.balanceOf(owner.address)).gt("0");
        })
    })

    describe("Test coverage on withdraw - only one depositor", async () => {

        beforeEach(async () => {
            await wavaxTokenContract.approve(elkRouterContract.address, BigNumber.from("1000000000000000000000000"));
            await elkTokenContract.approve(elkRouterContract.address, BigNumber.from("1000000000000000000000000"));
            await elkPairContract.approve(elkIlpStrategyV5.address, BigNumber.from("1000000000000000000000000"));

            await elkRouterContract.swapExactTokensForTokens(BigNumber.from("10000000000000000"), BigNumber.from("5000000000000000"), [wavaxTokenContract.address, elkTokenContract.address], owner.address, 1807909162115)
            await elkRouterContract.addLiquidity(wavaxTokenContract.address, elkTokenContract.address, await wavaxTokenContract.balanceOf(owner.address), await elkTokenContract.balanceOf(owner.address), 0, 0, owner.address, 1807909162115)
        })

        it('Withdraw correct amount of ELK Liquidity token from the strategy', async () => {
            // We get the amount of ELK token we have
            const amount = (await elkPairContract.balanceOf(owner.address)).toString();
            // We get the 'totalDeposit' before we deposit into the strategy
            const totalDepositsBefore = (await elkIlpStrategyV5.totalDeposits()).toString();

            // We deposit into the staking contract our ELP tokens
            await elkIlpStrategyV5.deposit(BigNumber.from((await elkPairContract.balanceOf(owner.address)).toString()))
            // We get the 'totalDeposit' after our deposit into the strategy
            const totalDepositsAfter = (await elkIlpStrategyV5.totalDeposits()).toString();

            // We check all balances
            expect((await elkIlpStrategyV5.balanceOf(owner.address)).toString()).to.equal(amount)
            expect((await stakingContract.balanceOf(elkIlpStrategyV5.address)).toString()).to.equal(amount)
            expect(BigNumber.from(totalDepositsAfter)).gt(BigNumber.from(totalDepositsBefore));
            expect((await stakingContract.coverageOf(elkIlpStrategyV5.address)).toString()).to.equal("0")

            // We impersonate the 'owner' of the WAVAX-ELK StakingRewardsILP contract
            await ethers.provider.send('hardhat_impersonateAccount', ['0xba49776326A1ca54EB4F406C94Ae4e1ebE458E19']);
            const admin = await ethers.provider.getSigner('0xba49776326A1ca54EB4F406C94Ae4e1ebE458E19')

            const stakingcontract = await ethers.getContractAt(staking_contract, elpStakingRewardAddress, admin);
            // We set the coverage amount for our Strategy
            await stakingcontract.setCoverageAmount(elkIlpStrategyV5.address, 1000000000000);

            await hre.network.provider.request({
                method: "hardhat_stopImpersonatingAccount",
                params: ["0xba49776326A1ca54EB4F406C94Ae4e1ebE458E19"],
            });

            // We check the amount of coverage the Strategy contract address currently has
            expect((await stakingContract.coverageOf(elkIlpStrategyV5.address)).toString()).to.equal('1000000000000')
            // expect((await elk_ilp_strategy_v5.checkCoverage()).toString()).to.equal('1000000000000')

            // We should check now if, upon withdrawal, we get a bigger amount of ELP tokens
            // We withdraw from the strategy all tokens we deposited
            await elkIlpStrategyV5.withdraw(BigNumber.from((await elkIlpStrategyV5.balanceOf(owner.address)).toString()))
            const totalDepositsAfterWithdraw = (await elkIlpStrategyV5.totalDeposits()).toString();

            // We check if balances are correct
            // Since we have only one depositor, strategy contract and staking contract should both be back at 0
            expect((await elkIlpStrategyV5.balanceOf(owner.address))).eq(0)
            expect((await stakingContract.balanceOf(elkIlpStrategyV5.address))).eq(0)
            // The total deposit should be back to its previous value
            expect(BigNumber.from(totalDepositsAfterWithdraw)).eq(BigNumber.from(totalDepositsBefore));
            // We should get a slightly bigger amount of ELP tokens since we got the coverage as well
            expect(await elkPairContract.balanceOf(owner.address)).gt(amount);
        })
    })

    describe("Test coverage on withdraw - two depositor", async () => {

        beforeEach(async () => {
            // Setup approval for one account
            await wavaxTokenContract.approve(elkRouterContract.address, BigNumber.from("1000000000000000000000000"))
            await elkTokenContract.approve(elkRouterContract.address, BigNumber.from("1000000000000000000000000"))
            await elkPairContract.approve(elkIlpStrategyV5.address, BigNumber.from("1000000000000000000000000"))

            await elkRouterContract.swapExactTokensForTokens(BigNumber.from("10000000000000000"), BigNumber.from("5000000000000000"), [wavaxTokenContract.address, elkTokenContract.address], owner.address, 1807909162115)
            await elkRouterContract.addLiquidity(wavaxTokenContract.address, elkTokenContract.address, await wavaxTokenContract.balanceOf(owner.address), await elkTokenContract.balanceOf(owner.address), 0, 0, owner.address, 1807909162115)

            // Setup approval for the other account
            await wavaxTokenContract.connect(account1).approve(elkRouterContract.address, BigNumber.from("1000000000000000000000000"))
            await elkTokenContract.connect(account1).approve(elkRouterContract.address, BigNumber.from("1000000000000000000000000"))
            await elkPairContract.connect(account1).approve(elkIlpStrategyV5.address, BigNumber.from("1000000000000000000000000"))
            await elkRouterContract.connect(account1).swapExactTokensForTokens(BigNumber.from("10000000000000000"), BigNumber.from("5000000000000000"), [wavaxTokenContract.address, elkTokenContract.address], account1.address, 1807909162115)
            await elkRouterContract.connect(account1).addLiquidity(wavaxTokenContract.address, elkTokenContract.address, await wavaxTokenContract.balanceOf(account1.address), await elkTokenContract.balanceOf(account1.address), 0, 0, account1.address, 1807909162115)
        })

        it('Withdraw correct elp_balance_account1 of ELK Liquidity token from the strategy', async () => {
            // We get the elp_balance_account1 of ELK token we have
            const elp_balance_account1 = (await elkPairContract.balanceOf(owner.address)).toString();
            const elp_balance_account2 = (await elkPairContract.balanceOf(account1.address)).toString();
            // We get the 'totalDeposit' before we deposit into the strategy
            const totalDepositsBefore = (await elkIlpStrategyV5.totalDeposits()).toString();

            // We deposit into the staking contract our ELP tokens
            await elkIlpStrategyV5.deposit(BigNumber.from((await elkPairContract.balanceOf(owner.address)).toString()))
            await elkIlpStrategyV5.connect(account1).deposit(BigNumber.from((await elkPairContract.balanceOf(account1.address)).toString()))
            // We get the 'totalDeposit' after our deposit into the strategy
            const totalDepositsAfter = (await elkIlpStrategyV5.totalDeposits()).toString();

            // We check all balances
            expect((await elkIlpStrategyV5.balanceOf(owner.address)).toString()).to.equal(elp_balance_account1)
            expect((await elkIlpStrategyV5.balanceOf(account1.address)).toString()).to.equal(elp_balance_account2)
            expect(BigNumber.from(totalDepositsAfter)).gt(BigNumber.from(totalDepositsBefore));
            expect((await stakingContract.coverageOf(elkIlpStrategyV5.address)).toString()).to.equal("0")

            // We impersonate the 'owner' of the WAVAX-ELK StakingRewardsILP contract
            await ethers.provider.send('hardhat_impersonateAccount', ['0xba49776326A1ca54EB4F406C94Ae4e1ebE458E19']);
            const admin = await ethers.provider.getSigner('0xba49776326A1ca54EB4F406C94Ae4e1ebE458E19')

            const stakingcontract = await ethers.getContractAt(staking_contract, elpStakingRewardAddress, admin);
            // We set the coverage elp_balance_account1 for our Strategy
            await stakingcontract.setCoverageAmount(elkIlpStrategyV5.address, 1000000000000);

            await hre.network.provider.request({
                method: "hardhat_stopImpersonatingAccount",
                params: ["0xba49776326A1ca54EB4F406C94Ae4e1ebE458E19"],
            });

            // We check the elp_balance_account1 of coverage the Strategy contract address currently has
            expect((await stakingContract.coverageOf(elkIlpStrategyV5.address)).toString()).to.equal('1000000000000')
            // expect((await elk_ilp_strategy_v5.checkCoverage()).toString()).to.equal('1000000000000')

            // We should check now if, upon withdrawal, we get a bigger elp_balance_account1 of ELP tokens
            // We withdraw from the strategy all tokens we deposited
            await elkIlpStrategyV5.withdraw(BigNumber.from((await elkIlpStrategyV5.balanceOf(owner.address)).toString()))
            const totalDepositsAfterWithdraw = (await elkIlpStrategyV5.totalDeposits()).toString();

            // We check if balances are correct
            // Since we have only one depositor, strategy contract and staking contract should both be back at 0
            expect((await elkIlpStrategyV5.balanceOf(owner.address))).eq(0)
            expect((await elkIlpStrategyV5.balanceOf(account1.address))).eq(elp_balance_account2)
            expect((await stakingContract.balanceOf(elkIlpStrategyV5.address))).gt(elp_balance_account2)
            // The total deposit should be back to its previous value
            expect(BigNumber.from(totalDepositsAfterWithdraw)).gt(BigNumber.from(totalDepositsBefore));
            // We should get a slightly bigger elp_balance_account1 of ELP tokens since we got the coverage as well
            expect(await elkPairContract.balanceOf(owner.address)).gt(elp_balance_account1);
        })
    })
})
