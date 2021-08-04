const {expect} = require("chai")
const {ethers, run} = require("hardhat")
const {BigNumber} = ethers

const ONE_EXPONENT_17 = "10000000000000000";
const FIVE_EXPONENT_16 = "5000000000000000";

async function setupForTwoAccounts(wavaxTokenContract, elkRouterContract, elkTokenContract, elkPairContract, elkIlpStrategyV5, owner, account1) {
    // Setup approval for one account
    await wavaxTokenContract.approve(elkRouterContract.address, ethers.constants.MaxUint256)
    await elkTokenContract.approve(elkRouterContract.address, ethers.constants.MaxUint256)
    await elkPairContract.approve(elkIlpStrategyV5.address, ethers.constants.MaxUint256)

    await elkRouterContract.swapExactTokensForTokens(BigNumber.from(ONE_EXPONENT_17), BigNumber.from(FIVE_EXPONENT_16), [wavaxTokenContract.address, elkTokenContract.address], owner.address, 1807909162115)
    await elkRouterContract.addLiquidity(wavaxTokenContract.address, elkTokenContract.address, await wavaxTokenContract.balanceOf(owner.address), await elkTokenContract.balanceOf(owner.address), 0, 0, owner.address, 1807909162115)

    // Setup approval for the other account
    await wavaxTokenContract.connect(account1).approve(elkRouterContract.address, ethers.constants.MaxUint256)
    await elkTokenContract.connect(account1).approve(elkRouterContract.address, ethers.constants.MaxUint256)
    await elkPairContract.connect(account1).approve(elkIlpStrategyV5.address, ethers.constants.MaxUint256)
    await elkRouterContract.connect(account1).swapExactTokensForTokens(BigNumber.from(ONE_EXPONENT_17), BigNumber.from(FIVE_EXPONENT_16), [wavaxTokenContract.address, elkTokenContract.address], account1.address, 1807909162115)
    await elkRouterContract.connect(account1).addLiquidity(wavaxTokenContract.address, elkTokenContract.address, await wavaxTokenContract.balanceOf(account1.address), await elkTokenContract.balanceOf(account1.address), 0, 0, account1.address, 1807909162115)
}

async function setupForOneAccount(wavaxTokenContract, elkRouterContract, elkTokenContract, elkPairContract, elkIlpStrategyV5, owner) {
    await wavaxTokenContract.approve(elkRouterContract.address, ethers.constants.MaxUint256);
    await elkTokenContract.approve(elkRouterContract.address, ethers.constants.MaxUint256);
    await elkPairContract.approve(elkIlpStrategyV5.address, ethers.constants.MaxUint256);

    await elkRouterContract.swapExactTokensForTokens(BigNumber.from(ONE_EXPONENT_17), BigNumber.from(FIVE_EXPONENT_16), [wavaxTokenContract.address, elkTokenContract.address], owner.address, 1807909162115)
    await elkRouterContract.addLiquidity(wavaxTokenContract.address, elkTokenContract.address, await wavaxTokenContract.balanceOf(owner.address), await elkTokenContract.balanceOf(owner.address), 0, 0, owner.address, 1807909162115)
}

describe("ElkIlpStrategyV5", function () {

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
        
        elkPairContract = await ethers.getContractAt('IPair', depositTokenAddress);
        elkRouterContract = await ethers.getContractAt('IRouter', elkRouterAddress);
        stakingContract = await ethers.getContractAt('IStakingRewardsILPV2', elpStakingRewardAddress);
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
        elkTokenContract = await ethers.getContractAt("contracts/interfaces/IERC20.sol:IERC20", elkTokenAddress)
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
        expect(await elkPairContract.allowance(elkIlpStrategyV5.address, elpStakingRewardAddress)).to.equal(ethers.constants.MaxUint256)
    })

    });

    describe("Test deposit functionality", async () => {

        beforeEach(async () => {
            await setupForOneAccount(wavaxTokenContract, elkRouterContract, elkTokenContract, elkPairContract, elkIlpStrategyV5, owner);
        })

        it('Deposit correct amount of ELK Liquidity token into the strategy', async () => {
            // We get the amount of ELK token we have
            const amount = await elkPairContract.balanceOf(owner.address)
            // We get the 'totalDeposit' before we deposit into the strategy
            const totalDepositsBefore = await elkIlpStrategyV5.totalDeposits()

            // We deposit our ELP tokens into the strategy
            await elkIlpStrategyV5.deposit(await elkPairContract.balanceOf(owner.address))
            // We get the 'totalDeposit' after our deposit
            const totalDepositsAfter = await elkIlpStrategyV5.totalDeposits()

            // Our balance should be equal to the amount of ELP token we deposited
            expect(await elkIlpStrategyV5.balanceOf(owner.address)).to.equal(amount)
            // The strategy contract should have correct balance on the staking contract
            expect(await stakingContract.balanceOf(elkIlpStrategyV5.address)).to.equal(amount)

            // We check if the totalDeposit has grown after our deposit
            expect(totalDepositsAfter).gt(totalDepositsBefore);
        })
    })

    describe("Test withdraw functionality", async () => {
        beforeEach(async () => {
            await setupForOneAccount(wavaxTokenContract, elkRouterContract, elkTokenContract, elkPairContract, elkIlpStrategyV5, owner);
        })

        it('Withdraw correctly our ELP tokens from the Strategy', async () => {
            // We get the amount of ELK token we have
            const amount = await elkPairContract.balanceOf(owner.address)
            // We get the 'totalDeposit' before we deposit into the strategy
            const totalDepositsBefore = await elkIlpStrategyV5.totalDeposits()

            // We deposit into the staking contract our ELP tokens
            await elkIlpStrategyV5.deposit(await elkPairContract.balanceOf(owner.address))
            // We get the 'totalDeposit' after our deposit into the strategy
            let totalDepositsAfter = await elkIlpStrategyV5.totalDeposits()

            // We make sure all balances are correct .
            expect(await elkIlpStrategyV5.balanceOf(owner.address)).to.equal(amount)
            expect(await stakingContract.balanceOf(elkIlpStrategyV5.address)).to.equal(amount)
            expect(totalDepositsAfter).gt(totalDepositsBefore)

            // Advance the time to 1 week
            await hre.ethers.provider.send('evm_increaseTime', [7 * 24 * 60 * 60]);
            await network.provider.send("evm_mine")

            // We check the amount we earned so far
            expect(await stakingContract.earned(elkIlpStrategyV5.address)).to.not.equal(0)

            // We withdraw from the strategy all tokens we deposited
            await elkIlpStrategyV5.withdraw(await elkIlpStrategyV5.balanceOf(owner.address))

            // We get the 'totalDeposit' after withdrawing from the strategy
            totalDepositsAfter = await elkIlpStrategyV5.totalDeposits()

            // We check if balances are correct
            expect(await elkIlpStrategyV5.balanceOf(owner.address)).to.equal(0)
            expect(await stakingContract.balanceOf(elkIlpStrategyV5.address)).to.equal(0)
            expect(totalDepositsAfter).eq(totalDepositsBefore);
            expect(await elkPairContract.balanceOf(owner.address)).gt(0)
        })
    })

    describe("Test coverage on withdraw - only one depositor", async () => {

        beforeEach(async () => {
            await setupForOneAccount(wavaxTokenContract, elkRouterContract, elkTokenContract, elkPairContract, elkIlpStrategyV5, owner);
        })

        it('Withdraw correct amount of ELK Liquidity token from the strategy', async () => {
            // We get the amount of ELK token we have
            const amount = await elkPairContract.balanceOf(owner.address)
            // We get the 'totalDeposit' before we deposit into the strategy
            const totalDepositsBefore = await elkIlpStrategyV5.totalDeposits()

            // We deposit into the staking contract our ELP tokens
            await elkIlpStrategyV5.deposit(await elkPairContract.balanceOf(owner.address))
            // We get the 'totalDeposit' after our deposit into the strategy
            const totalDepositsAfter = await elkIlpStrategyV5.totalDeposits()

            // We check all balances
            expect(await elkIlpStrategyV5.balanceOf(owner.address)).to.equal(amount)
            expect(await stakingContract.balanceOf(elkIlpStrategyV5.address)).to.equal(amount)
            expect(totalDepositsAfter).gt(totalDepositsBefore)
            expect(await stakingContract.coverageOf(elkIlpStrategyV5.address)).to.equal(0)

            // We impersonate the 'owner' of the WAVAX-ELK StakingRewardsILP contract
            await ethers.provider.send('hardhat_impersonateAccount', ['0xba49776326A1ca54EB4F406C94Ae4e1ebE458E19']);
            const admin = await ethers.provider.getSigner('0xba49776326A1ca54EB4F406C94Ae4e1ebE458E19')

            const stakingcontract = await ethers.getContractAt('IStakingRewardsILPV2', elpStakingRewardAddress, admin);
            // We set the coverage amount for our Strategy
            await stakingcontract.setCoverageAmount(elkIlpStrategyV5.address, 1000000000000);

            await hre.network.provider.request({
                method: "hardhat_stopImpersonatingAccount",
                params: ["0xba49776326A1ca54EB4F406C94Ae4e1ebE458E19"],
            });

            // We check the amount of coverage the Strategy contract address currently has
            expect(await stakingContract.coverageOf(elkIlpStrategyV5.address)).to.equal(1000000000000)

            // We should check now if, upon withdrawal, we get a bigger amount of ELP tokens
            // We withdraw from the strategy all tokens we deposited
            await elkIlpStrategyV5.withdraw(await elkIlpStrategyV5.balanceOf(owner.address))
            const totalDepositsAfterWithdraw = await elkIlpStrategyV5.totalDeposits()

            // We check if balances are correct
            // Since we have only one depositor, strategy contract and staking contract should both be back at 0
            expect((await elkIlpStrategyV5.balanceOf(owner.address))).eq(0)
            expect((await stakingContract.balanceOf(elkIlpStrategyV5.address))).eq(0)
            // The total deposit should be back to its previous value
            expect(totalDepositsAfterWithdraw).eq(totalDepositsBefore);
            // We should get a slightly bigger amount of ELP tokens since we got the coverage as well
            expect(await elkPairContract.balanceOf(owner.address)).gt(amount);
        })
    })

    describe("Test reinvesting - two depositors", async () => {

        beforeEach(async () => {
            await setupForTwoAccounts(wavaxTokenContract, elkRouterContract, elkTokenContract, elkPairContract, elkIlpStrategyV5, owner, account1);
        })

        it('Reinvest correct amount for 2 depositors', async () => {
            // We get the amount of ELK token we have
            const amount = await elkPairContract.balanceOf(owner.address)
            // We get the 'totalDeposit' before we deposit into the strategy
            const totalDepositsBefore = await elkIlpStrategyV5.totalDeposits()

            // We deposit into the staking contract our ELP tokens
            await elkIlpStrategyV5.deposit(await elkPairContract.balanceOf(owner.address))
            // We get the 'totalDeposit' after our deposit into the strategy
            const totalDepositsAfterDeposit = await elkIlpStrategyV5.totalDeposits()

            // We check all balances
            expect(await elkIlpStrategyV5.balanceOf(owner.address)).to.equal(amount)
            expect(await stakingContract.balanceOf(elkIlpStrategyV5.address)).to.equal(amount)
            expect(totalDepositsAfterDeposit).gt(totalDepositsBefore);
            expect(await stakingContract.coverageOf(elkIlpStrategyV5.address)).to.equal("0")

            // Advance the time to 1 week so we get some reward
            await hre.ethers.provider.send('evm_increaseTime', [7 * 24 * 60 * 60]);
            await network.provider.send("evm_mine")

            // We check the amount we earned so far
            expect(await stakingContract.earned(elkIlpStrategyV5.address)).to.not.equal('0')

            // We should check now if, upon withdrawal, we get a bigger amount of ELP tokens
            // We withdraw from the strategy all tokens we deposited
            await elkIlpStrategyV5.reinvest()
            const totalDepositsAfterReinvest = await elkIlpStrategyV5.totalDeposits()

            // The total deposit should be back to its previous value
            expect(totalDepositsAfterReinvest).gt(totalDepositsAfterDeposit)
        })
    })

    describe("Test coverage on withdraw - two depositor", async () => {

        beforeEach(async () => {
            await setupForTwoAccounts(wavaxTokenContract, elkRouterContract, elkTokenContract, elkPairContract, elkIlpStrategyV5, owner, account1);
        })

        it('Withdraw correct elp_balance_account1 of ELK Liquidity token from the strategy', async () => {
            // We get the elpBalanceAccount1 of ELK token we have
            const elpBalanceAccount1 = await elkPairContract.balanceOf(owner.address);
            const elpBalanceAccount2 = await elkPairContract.balanceOf(account1.address);
            // We get the 'totalDeposit' before we deposit into the strategy
            const totalDepositsBefore = await elkIlpStrategyV5.totalDeposits();

            // We deposit into the staking contract our ELP tokens
            await elkIlpStrategyV5.deposit(await elkPairContract.balanceOf(owner.address))
            await elkIlpStrategyV5.connect(account1).deposit(await elkPairContract.balanceOf(account1.address))
            // We get the 'totalDeposit' after our deposit into the strategy
            const totalDepositsAfter = await elkIlpStrategyV5.totalDeposits();

            // We check all balances
            expect(await elkIlpStrategyV5.balanceOf(owner.address)).to.equal(elpBalanceAccount1)
            expect(await elkIlpStrategyV5.balanceOf(account1.address)).to.equal(elpBalanceAccount2)
            expect(totalDepositsAfter).gt(totalDepositsBefore);
            expect(await stakingContract.coverageOf(elkIlpStrategyV5.address)).to.equal(0)

            // We impersonate the 'owner' of the WAVAX-ELK StakingRewardsILP contract
            await ethers.provider.send('hardhat_impersonateAccount', ['0xba49776326A1ca54EB4F406C94Ae4e1ebE458E19']);
            const admin = await ethers.provider.getSigner('0xba49776326A1ca54EB4F406C94Ae4e1ebE458E19')

            const stakingcontract = await ethers.getContractAt('IStakingRewardsILPV2', elpStakingRewardAddress, admin);
            // We set the coverage elpBalanceAccount1 for our Strategy
            await stakingcontract.setCoverageAmount(elkIlpStrategyV5.address, 1000000000000);

            await hre.network.provider.request({
                method: "hardhat_stopImpersonatingAccount",
                params: ["0xba49776326A1ca54EB4F406C94Ae4e1ebE458E19"],
            });

            // We check the elpBalanceAccount1 of coverage the Strategy contract address currently has
            expect(await stakingContract.coverageOf(elkIlpStrategyV5.address)).to.equal(1000000000000)

            // We should check now if, upon withdrawal, we get a bigger elpBalanceAccount1 of ELP tokens
            // We withdraw from the strategy all tokens we deposited
            await elkIlpStrategyV5.withdraw(await elkIlpStrategyV5.balanceOf(owner.address))
            const totalDepositsAfterWithdraw = await elkIlpStrategyV5.totalDeposits();

            // We check if balances are correct
            // Since we have only one depositor, strategy contract and staking contract should both be back at 0
            expect((await elkIlpStrategyV5.balanceOf(owner.address))).eq(0)
            expect((await elkIlpStrategyV5.balanceOf(account1.address))).eq(elpBalanceAccount2)
            expect((await stakingContract.balanceOf(elkIlpStrategyV5.address))).gt(elpBalanceAccount2)
            // The total deposit should be back to its previous value
            expect(totalDepositsAfterWithdraw).gt(totalDepositsBefore);
            // We should get a slightly bigger elpBalanceAccount1 of ELP tokens since we got the coverage as well
            expect(await elkPairContract.balanceOf(owner.address)).gt(elpBalanceAccount1);
        })
    })
})
