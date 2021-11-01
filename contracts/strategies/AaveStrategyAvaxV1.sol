// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "../YakStrategyV2Payable.sol";
import "../interfaces/IAaveIncentivesController.sol";
import "../interfaces/ILendingPool.sol";
import "../interfaces/IWAVAX.sol";
import "../interfaces/IERC20.sol";
import "../lib/SafeMath.sol";
import "../lib/DexLibrary.sol";
import "../lib/ReentrancyGuard.sol";

/**
 * @title Aave strategy for AVAX
 * @dev No need to _enterMarket() as LendingPool already defaults collateral to true.
 * See https://github.com/aave/protocol-v2/blob/master/contracts/protocol/lendingpool/LendingPool.sol#L123-L126
 */
contract AaveStrategyAvaxV1 is YakStrategyV2Payable, ReentrancyGuard {
    using SafeMath for uint256;

    IAaveIncentivesController private rewardController;
    ILendingPool private tokenDelegator;
    IWAVAX private constant WAVAX = IWAVAX(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
    uint256 private leverageLevel;
    uint256 private safetyFactor;
    uint256 private leverageBips;
    uint256 private minMinting;
    address private avToken;
    address private avDebtToken;

    constructor(
        string memory _name,
        address _rewardController,
        address _tokenDelegator,
        address _avToken,
        address _avDebtToken,
        address _timelock,
        uint256 _leverageLevel,
        uint256 _safetyFactor,
        uint256 _leverageBips,
        uint256 _minMinting,
        uint256 _minTokensToReinvest,
        uint256 _adminFeeBips,
        uint256 _devFeeBips,
        uint256 _reinvestRewardBips
    ) {
        name = _name;
        rewardController = IAaveIncentivesController(_rewardController);
        tokenDelegator = ILendingPool(_tokenDelegator);
        rewardToken = IERC20(address(WAVAX));
        _updateLeverage(_leverageLevel, _safetyFactor, _minMinting, _leverageBips);
        devAddr = msg.sender;
        avToken = _avToken;
        avDebtToken = _avDebtToken;

        setAllowances();
        updateMinTokensToReinvest(_minTokensToReinvest);
        updateAdminFee(_adminFeeBips);
        updateDevFee(_devFeeBips);
        updateReinvestReward(_reinvestRewardBips);
        updateDepositsEnabled(true);
        transferOwnership(_timelock);

        emit Reinvest(0, 0);
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

    receive() external payable {
        require(msg.sender == address(WAVAX), "not allowed");
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

    function setAllowances() public override onlyOwner {
        WAVAX.approve(address(tokenDelegator), type(uint256).max);
        IERC20(avToken).approve(address(tokenDelegator), type(uint256).max);
    }

    function deposit() external payable override nonReentrant {
        WAVAX.deposit{value: msg.value}();
        _deposit(msg.sender, msg.value);
    }

    function depositFor(address account) external payable override nonReentrant {
        WAVAX.deposit{value: msg.value}();
        _deposit(account, msg.value);
    }

    function deposit(uint256 amount) external override {
        revert();
    }

    function depositWithPermit(
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        revert();
    }

    function depositFor(address account, uint256 amount) external override {
        revert();
    }

    function _deposit(address account, uint256 amount) private onlyAllowedDeposits {
        require(DEPOSITS_ENABLED == true, "AaveStrategyAvaxV1::_deposit");
        if (MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST > 0) {
            uint256 avaxRewards = _checkRewards();
            if (avaxRewards > MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST) {
                _reinvest(avaxRewards);
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
        uint256 avaxRewards = _checkRewards();
        require(avaxRewards >= MIN_TOKENS_TO_REINVEST, "AaveStrategyAvaxV1::reinvest");
        _reinvest(avaxRewards);
    }

    /**
     * @notice Reinvest rewards from staking contract to deposit tokens
     * @dev Reverts if the expected amount of tokens are not returned from `stakingContract`
     * @param amount deposit tokens to reinvest
     */
    function _reinvest(uint256 amount) private {
        address[] memory assets = new address[](2);
        assets[0] = avToken;
        assets[1] = avDebtToken;
        rewardController.claimRewards(assets, amount, address(this));

        uint256 devFee = amount.mul(DEV_FEE_BIPS).div(BIPS_DIVISOR);
        if (devFee > 0) {
            _safeTransfer(address(rewardToken), devAddr, devFee);
        }

        uint256 adminFee = amount.mul(ADMIN_FEE_BIPS).div(BIPS_DIVISOR);
        if (adminFee > 0) {
            _safeTransfer(address(rewardToken), owner(), adminFee);
        }

        uint256 reinvestFee = amount.mul(REINVEST_REWARD_BIPS).div(BIPS_DIVISOR);
        if (reinvestFee > 0) {
            _safeTransfer(address(rewardToken), msg.sender, reinvestFee);
        }

        _stakeDepositTokens(amount.sub(devFee).sub(adminFee).sub(reinvestFee));

        emit Reinvest(totalDeposits(), totalSupply);
    }

    function _rollupDebt() internal {
        (uint256 balance, uint256 borrowed, uint256 borrowable) = _getAccountData();
        uint256 lendTarget = balance.sub(borrowed).mul(leverageLevel.sub(safetyFactor)).div(leverageBips);
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

            tokenDelegator.deposit(address(WAVAX), borrowable, address(this), 0);
            (balance, borrowed, borrowable) = _getAccountData();
        }
    }

    function _unrollDebt(uint256 amountToFreeUp) internal {
        (uint256 balance, uint256 borrowed, uint256 borrowable) = _getAccountData();
        uint256 targetBorrow = balance
            .sub(borrowed)
            .sub(amountToFreeUp)
            .mul(leverageLevel.sub(safetyFactor))
            .div(leverageBips)
            .sub(balance.sub(borrowed).sub(amountToFreeUp));
        uint256 toRepay = borrowed.sub(targetBorrow);

        while (toRepay > 0) {
            uint256 unrollAmount = borrowable;
            if (unrollAmount > borrowed) {
                unrollAmount = borrowed;
            }
            tokenDelegator.withdraw(address(WAVAX), unrollAmount, address(this));
            tokenDelegator.repay(address(WAVAX), unrollAmount, 2, address(this));
            (balance, borrowed, borrowable) = _getAccountData();
            if (targetBorrow >= borrowed) {
                break;
            }
            toRepay = borrowed.sub(targetBorrow);
        }
    }

    function _stakeDepositTokens(uint256 amount) private {
        require(amount > 0, "AaveStrategyAvaxV1::_stakeDepositTokens");
        tokenDelegator.deposit(address(WAVAX), amount, address(this), 0);
        _rollupDebt();
    }

    /**
     * @notice Safely transfer using an anonymosu ERC20 token
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

    function _checkRewards() internal view returns (uint256 avaxAmount) {
        address[] memory assets = new address[](2);
        assets[0] = avToken;
        assets[1] = avDebtToken;
        return rewardController.getRewardsBalance(assets, address(this));
    }

    function checkReward() public view override returns (uint256) {
        return _checkRewards();
    }

    function getActualLeverage() public view returns (uint256) {
        (uint256 balance, uint256 borrowed, ) = _getAccountData();
        return balance.mul(1e18).div(balance.sub(borrowed));
    }

    function estimateDeployedBalance() external view override returns (uint256) {
        return totalDeposits();
    }

    function rescueDeployedFunds(uint256 minReturnAmountAccepted, bool disableDeposits) external override onlyOwner {
        uint256 balanceBefore = WAVAX.balanceOf(address(this));
        (uint256 balance, uint256 borrowed, ) = _getAccountData();
        _unrollDebt(balance.sub(borrowed));
        tokenDelegator.withdraw(address(WAVAX), type(uint256).max, address(this));
        uint256 balanceAfter = WAVAX.balanceOf(address(this));
        require(balanceAfter.sub(balanceBefore) >= minReturnAmountAccepted, "AaveStrategyAvaxV1::rescueDeployedFunds");
        emit Reinvest(totalDeposits(), totalSupply);
        if (DEPOSITS_ENABLED == true && disableDeposits == true) {
            updateDepositsEnabled(false);
        }
    }
}
