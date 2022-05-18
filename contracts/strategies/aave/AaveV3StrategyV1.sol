// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../YakStrategyV2.sol";
import "../../interfaces/IWAVAX.sol";
import "../../interfaces/IERC20.sol";
import "../../lib/SafeMath.sol";
import "../../lib/DexLibrary.sol";
import "./interfaces/IAaveV3IncentivesController.sol";
import "./interfaces/ILendingPoolAaveV3.sol";

/**
 * @title Aave strategy for ERC20
 */
contract AaveV3StrategyV1 is YakStrategyV2 {
    using SafeMath for uint256;

    struct Reward {
        address reward;
        uint256 amount;
    }

    struct RewardSwapPairs {
        address reward;
        address swapPair;
    }

    struct LeverageSettings {
        uint256 leverageLevel;
        uint256 safetyFactor;
        uint256 leverageBips;
        uint256 minMinting;
    }

    // reward -> swapPair
    mapping(address => address) public rewardSwapPairs;
    address[] public supportedRewards;
    uint256 public rewardCount;

    uint256 public leverageLevel;
    uint256 public safetyFactor;
    uint256 public leverageBips;
    uint256 public minMinting;

    IAaveV3IncentivesController private rewardController;
    ILendingPoolAaveV3 private tokenDelegator;
    IPair private swapPairToken;
    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    address private avToken;
    address private avDebtToken;

    event AddReward(address rewardToken, address swapPair);
    event RemoveReward(address rewardToken);

    constructor(
        string memory _name,
        address _rewardController,
        address _tokenDelegator,
        address _depositToken,
        address _swapPairToken,
        RewardSwapPairs[] memory _rewardSwapPairs,
        address _avToken,
        address _avDebtToken,
        address _timelock,
        LeverageSettings memory _leverageSettings,
        StrategySettings memory _strategySettings
    ) YakStrategyV2(_strategySettings) {
        name = _name;
        rewardController = IAaveV3IncentivesController(_rewardController);
        tokenDelegator = ILendingPoolAaveV3(_tokenDelegator);
        rewardToken = IERC20(address(WAVAX));
        _updateLeverage(
            _leverageSettings.leverageLevel,
            _leverageSettings.safetyFactor,
            _leverageSettings.minMinting,
            _leverageSettings.leverageBips
        );
        devAddr = msg.sender;
        depositToken = IERC20(_depositToken);
        avToken = _avToken;
        avDebtToken = _avDebtToken;
        assignSwapPairSafely(_swapPairToken);

        for (uint256 i = 0; i < _rewardSwapPairs.length; i++) {
            _addReward(_rewardSwapPairs[i].reward, _rewardSwapPairs[i].swapPair);
        }

        updateDepositsEnabled(true);
        transferOwnership(_timelock);

        emit Reinvest(0, 0);
    }

    function addReward(address _rewardToken, address _swapPair) public onlyDev {
        _addReward(_rewardToken, _swapPair);
    }

    function _addReward(address _rewardToken, address _swapPair) internal {
        if (_rewardToken != address(rewardToken)) {
            require(
                DexLibrary.checkSwapPairCompatibility(IPair(_swapPair), _rewardToken, address(rewardToken)),
                "VariableRewardsStrategy::Swap pair does not contain reward token"
            );
        }
        rewardSwapPairs[_rewardToken] = _swapPair;
        supportedRewards.push(_rewardToken);
        rewardCount = rewardCount.add(1);
        emit AddReward(_rewardToken, _swapPair);
    }

    function removeReward(address _rewardToken) public onlyDev {
        delete rewardSwapPairs[_rewardToken];
        bool found = false;
        for (uint256 i = 0; i < supportedRewards.length; i++) {
            if (_rewardToken == supportedRewards[i]) {
                found = true;
                supportedRewards[i] = supportedRewards[supportedRewards.length - 1];
            }
        }
        require(found, "VariableRewardsStrategy::Reward to delete not found!");
        supportedRewards.pop();
        rewardCount = rewardCount.sub(1);
        emit RemoveReward(_rewardToken);
    }

    function assignSwapPairSafely(address _swapPairToken) private {
        require(_swapPairToken > address(0), "Swap pair is necessary but not supplied");
        swapPairToken = IPair(_swapPairToken);
        require(
            isPairEquals(swapPairToken, depositToken, rewardToken) ||
                isPairEquals(swapPairToken, rewardToken, depositToken),
            "Swap pair does not match depositToken and rewardToken."
        );
    }

    function isPairEquals(
        IPair pair,
        IERC20 left,
        IERC20 right
    ) private pure returns (bool) {
        return pair.token0() == address(left) && pair.token1() == address(right);
    }

    /// @notice Internal method to get account state
    /// @dev Values provided in 1e18 (WAD) instead of 1e27 (RAY)
    function _getAccountData()
        internal
        view
        returns (
            uint256 balance,
            uint256 borrowed,
            uint256 borrowable
        )
    {
        balance = IERC20(avToken).balanceOf(address(this));
        borrowed = IERC20(avDebtToken).balanceOf(address(this));
        borrowable = 0;
        if (balance.mul(leverageLevel.sub(leverageBips)).div(leverageLevel) > borrowed) {
            borrowable = balance.mul(leverageLevel.sub(leverageBips)).div(leverageLevel).sub(borrowed);
        }
    }

    function totalDeposits() public view override returns (uint256) {
        (uint256 balance, uint256 borrowed, ) = _getAccountData();
        return balance.sub(borrowed);
    }

    function _updateLeverage(
        uint256 _leverageLevel,
        uint256 _safetyFactor,
        uint256 _minMinting,
        uint256 _leverageBips
    ) internal {
        leverageLevel = _leverageLevel;
        leverageBips = _leverageBips;
        safetyFactor = _safetyFactor;
        minMinting = _minMinting;
    }

    function updateLeverage(
        uint256 _leverageLevel,
        uint256 _safetyFactor,
        uint256 _minMinting,
        uint256 _leverageBips
    ) external onlyDev {
        _updateLeverage(_leverageLevel, _safetyFactor, _minMinting, _leverageBips);
        (uint256 balance, uint256 borrowed, ) = _getAccountData();
        _unrollDebt(balance.sub(borrowed));
        _rollupDebt();
    }

    function deposit(uint256 amount) external override {
        _deposit(msg.sender, amount);
    }

    function depositFor(address account, uint256 amount) external override {
        _deposit(account, amount);
    }

    function depositWithPermit(
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        depositToken.permit(msg.sender, address(this), amount, deadline, v, r, s);
        _deposit(msg.sender, amount);
    }

    function _deposit(address account, uint256 amount) private onlyAllowedDeposits {
        require(DEPOSITS_ENABLED == true, "AaveV3StrategyV1::_deposit");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            uint256 avaxRewards = checkReward();
            if (avaxRewards > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(true);
            }
        }
        require(depositToken.transferFrom(msg.sender, address(this), amount), "AaveV3StrategyV1::transfer failed");
        _mint(account, getSharesForDepositTokens(amount));
        _stakeDepositTokens(amount);
        emit Deposit(account, amount);
    }

    function withdraw(uint256 amount) external override {
        uint256 depositTokenAmount = getDepositTokensForShares(amount);
        require(depositTokenAmount > minMinting, "AaveV3StrategyV1::below minimum withdraw");
        if (depositTokenAmount > 0) {
            _burn(msg.sender, amount);
            // actual amount withdrawn may change with time.
            uint256 withdrawnAmount = _withdrawDepositTokens(depositTokenAmount);
            _safeTransfer(address(depositToken), msg.sender, withdrawnAmount);
            emit Withdraw(msg.sender, withdrawnAmount);
        }
    }

    function _withdrawDepositTokens(uint256 amount) private returns (uint256) {
        _unrollDebt(amount);
        (uint256 balance, , ) = _getAccountData();
        amount = amount > balance ? type(uint256).max : amount;
        uint256 withdrawn = tokenDelegator.withdraw(address(depositToken), amount, address(this));
        _rollupDebt();
        return withdrawn;
    }

    function reinvest() external override onlyEOA {
        _reinvest(false);
    }

    function _convertRewardsIntoWAVAX() private returns (uint256) {
        uint256 avaxAmount = WAVAX.balanceOf(address(this));
        uint256 count = supportedRewards.length;
        for (uint256 i = 0; i < count; i++) {
            address reward = supportedRewards[i];
            if (reward == address(WAVAX)) {
                uint256 balance = address(this).balance;
                if (balance > 0) {
                    WAVAX.deposit{value: balance}();
                    avaxAmount = avaxAmount.add(balance);
                }
                continue;
            }
            uint256 amount = IERC20(reward).balanceOf(address(this));
            if (amount > 0) {
                address swapPair = rewardSwapPairs[reward];
                if (swapPair > address(0)) {
                    avaxAmount = avaxAmount.add(DexLibrary.swap(amount, reward, address(rewardToken), IPair(swapPair)));
                }
            }
        }
        return avaxAmount;
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from `stakingContract`
     * @param userDeposit Ignores MIN_TOKENS_TO_REINVEST in case of a user deposit
     */
    function _reinvest(bool userDeposit) private {
        address[] memory assets = new address[](2);
        assets[0] = avToken;
        assets[1] = avDebtToken;
        rewardController.claimAllRewards(assets, address(this));

        uint256 amount = _convertRewardsIntoWAVAX();
        if (!userDeposit) {
            require(amount >= MIN_TOKENS_TO_REINVEST, "VariableRewardsStrategy::Reinvest amount too low");
        }

        uint256 devFee = amount.mul(DEV_FEE_BIPS).div(BIPS_DIVISOR);
        if (devFee > 0) {
            _safeTransfer(address(rewardToken), devAddr, devFee);
        }

        uint256 reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {
            _safeTransfer(address(rewardToken), msg.sender, reinvestFee);
        }

        uint256 depositTokenAmount = DexLibrary.swap(
            amount.sub(devFee).sub(reinvestFee),
            address(rewardToken),
            address(depositToken),
            swapPairToken
        );
        _stakeDepositTokens(depositTokenAmount);

        emit Reinvest(totalDeposits(), totalSupply);
    }

    function _rollupDebt() internal {
        (uint256 balance, uint256 borrowed, uint256 borrowable) = _getAccountData();
        uint256 lendTarget = balance.sub(borrowed).mul(leverageLevel.sub(safetyFactor)).div(leverageBips);
        depositToken.approve(address(tokenDelegator), lendTarget);
        while (balance < lendTarget) {
            if (balance.add(borrowable) > lendTarget) {
                borrowable = lendTarget.sub(balance);
            }

            if (borrowable < minMinting) {
                break;
            }

            tokenDelegator.borrow(
                address(depositToken),
                borrowable,
                2, // variable interest model
                0,
                address(this)
            );

            tokenDelegator.supply(address(depositToken), borrowable, address(this), 0);
            (balance, borrowed, borrowable) = _getAccountData();
        }
        depositToken.approve(address(tokenDelegator), 0);
    }

    function _getRedeemable(
        uint256 balance,
        uint256 borrowed,
        uint256 threshold
    ) internal pure returns (uint256) {
        return
            balance.sub(borrowed).mul(1e18).sub(borrowed.mul(13).div(10).mul(1e18).div(threshold).div(100000)).div(
                1e18
            );
    }

    function _unrollDebt(uint256 amountToFreeUp) internal {
        (uint256 balance, uint256 borrowed, ) = _getAccountData();
        uint256 targetBorrow = balance
            .sub(borrowed)
            .sub(amountToFreeUp)
            .mul(leverageLevel.sub(safetyFactor))
            .div(leverageBips)
            .sub(balance.sub(borrowed).sub(amountToFreeUp));
        uint256 toRepay = borrowed.sub(targetBorrow);
        if (toRepay > 0) {
            tokenDelegator.repayWithATokens(address(depositToken), toRepay, 2);
        }
    }

    function _stakeDepositTokens(uint256 amount) private {
        require(amount > 0, "AaveV3StrategyV1::_stakeDepositTokens");
        depositToken.approve(address(tokenDelegator), amount);
        tokenDelegator.supply(address(depositToken), amount, address(this), 0);
        _rollupDebt();
    }

    /**
     * @notice Safely transfer using an anonymous ERC20 token
     * @dev Requires token to return true on transfer
     * @param token address
     * @param to recipient address
     * @param value amount
     */
    function _safeTransfer(
        address token,
        address to,
        uint256 value
    ) private {
        require(IERC20(token).transfer(to, value), "AaveV3StrategyV1::TRANSFER_FROM_FAILED");
    }

    function checkReward() public view override returns (uint256) {
        address[] memory assets = new address[](2);
        assets[0] = avToken;
        assets[1] = avDebtToken;
        (address[] memory rewards, uint256[] memory amounts) = rewardController.getAllUserRewards(
            assets,
            address(this)
        );
        uint256 estimatedTotalReward = WAVAX.balanceOf(address(this));
        estimatedTotalReward.add(address(this).balance);
        for (uint256 i = 0; i < rewards.length; i++) {
            address reward = rewards[i];
            if (reward == address(WAVAX)) {
                estimatedTotalReward = estimatedTotalReward.add(amounts[i]);
            } else {
                uint256 balance = IERC20(reward).balanceOf(address(this));
                uint256 amount = balance.add(amounts[i]);
                address swapPair = rewardSwapPairs[reward];
                if (amount > 0 && swapPair > address(0)) {
                    estimatedTotalReward = estimatedTotalReward.add(
                        DexLibrary.estimateConversionThroughPair(amount, reward, address(WAVAX), IPair(swapPair))
                    );
                }
            }
        }
        return estimatedTotalReward;
    }

    function getActualLeverage() public view returns (uint256) {
        (uint256 balance, uint256 borrowed, ) = _getAccountData();
        return balance.mul(1e18).div(balance.sub(borrowed));
    }

    function estimateDeployedBalance() external view override returns (uint256) {
        return totalDeposits();
    }

    function rescueDeployedFunds(
        uint256 minReturnAmountAccepted,
        bool /*disableDeposits*/
    ) external override onlyOwner {
        uint256 balanceBefore = depositToken.balanceOf(address(this));
        (uint256 balance, uint256 borrowed, ) = _getAccountData();
        _unrollDebt(balance.sub(borrowed));
        tokenDelegator.withdraw(address(depositToken), type(uint256).max, address(this));
        uint256 balanceAfter = depositToken.balanceOf(address(this));
        require(balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted, "AaveV3StrategyV1::rescueDeployedFunds");
        emit Reinvest(totalDeposits(), totalSupply);
        if (DEPOSITS_ENABLED == true) {
            updateDepositsEnabled(false);
        }
    }
}
