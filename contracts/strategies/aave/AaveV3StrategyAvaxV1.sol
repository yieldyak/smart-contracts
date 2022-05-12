// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../YakStrategyV2Payable.sol";
import "../../interfaces/IWAVAX.sol";
import "../../interfaces/IERC20.sol";
import "../../lib/SafeMath.sol";
import "../../lib/DexLibrary.sol";
import "../../lib/ReentrancyGuard.sol";
import "./interfaces/IAaveV3IncentivesController.sol";
import "./interfaces/ILendingPoolAaveV3.sol";

/**
 * @title Aave strategy for AVAX
 * @dev No need to _enterMarket() as LendingPool already defaults collateral to true.
 * See https://github.com/aave/protocol-v2/blob/master/contracts/protocol/lendingpool/LendingPool.sol#L123-L126
 */
contract AaveV3StrategyAvaxV1 is YakStrategyV2Payable, ReentrancyGuard {
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
    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    address private avToken;
    address private avDebtToken;

    event AddReward(address rewardToken, address swapPair);
    event RemoveReward(address rewardToken);

    constructor(
        string memory _name,
        address _rewardController,
        address _tokenDelegator,
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
        avToken = _avToken;
        avDebtToken = _avDebtToken;

        for (uint256 i = 0; i < _rewardSwapPairs.length; i++) {
            _addReward(_rewardSwapPairs[i].reward, _rewardSwapPairs[i].swapPair);
        }

        updateDepositsEnabled(true);
        transferOwnership(_timelock);

        emit Reinvest(0, 0);
    }

    receive() external payable {
        require(msg.sender == address(WAVAX), "not allowed");
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

    function setAllowances() public view override onlyOwner {
        revert("setAllowances::deprecated");
    }

    function deposit() external payable override nonReentrant {
        WAVAX.deposit{value: msg.value}();
        _deposit(msg.sender, msg.value);
    }

    function depositFor(address account) external payable override nonReentrant {
        WAVAX.deposit{value: msg.value}();
        _deposit(account, msg.value);
    }

    function deposit(
        uint256 /*amount*/
    ) external pure override {
        revert();
    }

    function depositWithPermit(
        uint256, /*amount*/
        uint256, /*deadline*/
        uint8, /*v*/
        bytes32, /*r*/
        bytes32 /*s*/
    ) external pure override {
        revert();
    }

    function depositFor(
        address, /*account*/
        uint256 /*amount*/
    ) external pure override {
        revert();
    }

    function _deposit(address account, uint256 amount) private onlyAllowedDeposits {
        require(DEPOSITS_ENABLED == true, "AaveStrategyAvaxV1::_deposit");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            uint256 avaxRewards = checkReward();
            if (avaxRewards > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(amount);
            }
        }
        _mint(account, getSharesForDepositTokens(amount));
        _stakeDepositTokens(amount);
        emit Deposit(account, amount);
    }

    function withdraw(uint256 amount) external override nonReentrant {
        uint256 WAVAXAmount = totalDeposits().mul(amount).div(totalSupply);
        require(WAVAXAmount > minMinting, "AaveStrategyAvaxV1::below minimum withdraw");
        if (WAVAXAmount > 0) {
            _burn(msg.sender, amount);
            uint256 avaxAmount = _withdrawDepositTokens(WAVAXAmount);
            (bool success, ) = msg.sender.call{value: avaxAmount}("");
            require(success, "AaveStrategyAvaxV1::transfer failed");
            emit Withdraw(msg.sender, avaxAmount);
        }
    }

    function _withdrawDepositTokens(uint256 amount) private returns (uint256) {
        _unrollDebt(amount);
        (uint256 balance, , ) = _getAccountData();
        if (amount > balance) {
            // withdraws all
            amount = type(uint256).max;
        }
        uint256 withdrawn = tokenDelegator.withdraw(address(WAVAX), amount, address(this));
        WAVAX.withdraw(withdrawn);
        _rollupDebt();
        return withdrawn;
    }

    function reinvest() external override onlyEOA nonReentrant {
        _reinvest(0);
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
     * @param userDeposit deposit amount in case of reinvest on deposit
     */
    function _reinvest(uint256 userDeposit) private {
        address[] memory assets = new address[](2);
        assets[0] = avToken;
        assets[1] = avDebtToken;
        rewardController.claimAllRewards(assets, address(this));

        uint256 amount = _convertRewardsIntoWAVAX();
        amount = amount.sub(userDeposit);
        if (userDeposit == 0) {
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

        _stakeDepositTokens(amount.sub(devFee).sub(reinvestFee));

        emit Reinvest(totalDeposits(), totalSupply);
    }

    function _rollupDebt() internal {
        (uint256 balance, uint256 borrowed, uint256 borrowable) = _getAccountData();
        uint256 lendTarget = balance.sub(borrowed).mul(leverageLevel.sub(safetyFactor)).div(leverageBips);
        WAVAX.approve(address(tokenDelegator), lendTarget);
        while (balance < lendTarget) {
            if (balance.add(borrowable) > lendTarget) {
                borrowable = lendTarget.sub(balance);
            }

            if (borrowable < minMinting) {
                break;
            }

            tokenDelegator.borrow(
                address(WAVAX),
                borrowable,
                2, // variable interest model
                0,
                address(this)
            );

            tokenDelegator.supply(address(WAVAX), borrowable, address(this), 0);
            (balance, borrowed, borrowable) = _getAccountData();
        }
        WAVAX.approve(address(tokenDelegator), 0);
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
            tokenDelegator.repayWithATokens(address(WAVAX), toRepay, 2);
        }
    }

    function _stakeDepositTokens(uint256 amount) private {
        require(amount > 0, "AaveStrategyAvaxV1::_stakeDepositTokens");
        WAVAX.approve(address(tokenDelegator), amount);
        tokenDelegator.supply(address(WAVAX), amount, address(this), 0);
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
        require(IERC20(token).transfer(to, value), "AaveStrategyAvaxV1::TRANSFER_FROM_FAILED");
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
        uint256 balanceBefore = WAVAX.balanceOf(address(this));
        (uint256 balance, uint256 borrowed, ) = _getAccountData();
        _unrollDebt(balance.sub(borrowed));
        tokenDelegator.withdraw(address(WAVAX), type(uint256).max, address(this));
        uint256 balanceAfter = WAVAX.balanceOf(address(this));
        require(balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted, "AaveStrategyAvaxV1::rescueDeployedFunds");
        emit Reinvest(totalDeposits(), totalSupply);
        if (DEPOSITS_ENABLED == true) {
            updateDepositsEnabled(false);
        }
    }
}
