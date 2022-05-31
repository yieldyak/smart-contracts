// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./YakBase.sol";
import "./lib/SafeERC20.sol";
import "./interfaces/IERC20.sol";

/**
 * @notice YakStrategy should be inherited by new strategies
 */
abstract contract YakStrategyV3 is YakBase {
    using SafeERC20 for IERC20;

    struct StrategySettings {
        address reward;
        address timelock;
        uint256 minTokensToReinvest;
        uint256 devFeeBips;
        uint256 reinvestRewardBips;
    }

    address public immutable rewardToken;

    uint256 public MIN_TOKENS_TO_REINVEST;
    uint256 public MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST;

    uint256 public REINVEST_REWARD_BIPS;
    uint256 public DEV_FEE_BIPS;

    uint256 internal constant BIPS_DIVISOR = 10000;

    event Reinvest(uint256 newTotalDeposits, uint256 newTotalSupply);
    event Recovered(address token, uint256 amount);
    event UpdateDevFee(uint256 oldValue, uint256 newValue);
    event UpdateReinvestReward(uint256 oldValue, uint256 newValue);
    event UpdateMinTokensToReinvest(uint256 oldValue, uint256 newValue);
    event UpdateMaxTokensToDepositWithoutReinvest(uint256 oldValue, uint256 newValue);

    /**
     * @notice Throws if called by smart contract
     */
    modifier onlyEOA() {
        require(tx.origin == msg.sender, "YakStrategy::onlyEOA");
        _;
    }

    constructor(BaseSettings memory _baseSettings, StrategySettings memory _strategySettings) YakBase(_baseSettings) {
        rewardToken = _strategySettings.reward;
        updateMinTokensToReinvest(_strategySettings.minTokensToReinvest);
        updateDevFee(_strategySettings.devFeeBips);
        updateReinvestReward(_strategySettings.reinvestRewardBips);
        transferOwnership(_strategySettings.timelock);
    }

    /*//////////////////////////////////////////////////////////////
                            ABSTRACT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Reward tokens avialable to strategy, including balance
     * @return reward tokens
     */
    function checkReward() public view virtual returns (uint256);

    /**
     * @notice Reinvest reward tokens into deposit tokens
     */
    function _reinvest(bool _userDeposit) internal virtual;

    /**
     * @notice Rescue all available deployed deposit tokens back to Strategy
     * @param _minReturnAmountAccepted min deposit tokens to receive
     */
    function _rescueDeployedFunds(uint256 _minReturnAmountAccepted) internal virtual;

    /*//////////////////////////////////////////////////////////////
                              REINVEST
    //////////////////////////////////////////////////////////////*/

    function reinvest() external onlyEOA {
        _reinvest(false);
    }

    /*//////////////////////////////////////////////////////////////
                                ADMIN
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Revoke token allowance
     * @param _token address
     * @param _spender address
     */
    function revokeAllowance(address _token, address _spender) external onlyOwner {
        require(IERC20(_token).approve(_spender, 0));
    }

    /**
     * @notice Update reinvest min threshold
     * @param _newValue threshold
     */
    function updateMinTokensToReinvest(uint256 _newValue) public onlyOwner {
        emit UpdateMinTokensToReinvest(MIN_TOKENS_TO_REINVEST, _newValue);
        MIN_TOKENS_TO_REINVEST = _newValue;
    }

    /**
     * @notice Update reinvest max threshold before a deposit
     * @param _newValue threshold
     */
    function updateMaxTokensToDepositWithoutReinvest(uint256 _newValue) public onlyOwner {
        emit UpdateMaxTokensToDepositWithoutReinvest(MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST, _newValue);
        MAX_TOKENS_TO_DEPOSIT_WITHOUT_REINVEST = _newValue;
    }

    /**
     * @notice Update developer fee
     * @param _newValue fee in BIPS
     */
    function updateDevFee(uint256 _newValue) public onlyOwner {
        require(_newValue + REINVEST_REWARD_BIPS <= BIPS_DIVISOR);
        emit UpdateDevFee(DEV_FEE_BIPS, _newValue);
        DEV_FEE_BIPS = _newValue;
    }

    /**
     * @notice Update reinvest reward
     * @param _newValue fee in BIPS
     */
    function updateReinvestReward(uint256 _newValue) public onlyOwner {
        require(_newValue + DEV_FEE_BIPS <= BIPS_DIVISOR);
        emit UpdateReinvestReward(REINVEST_REWARD_BIPS, _newValue);
        REINVEST_REWARD_BIPS = _newValue;
    }

    /**
     * @notice Update devAddr
     * @param _newValue address
     */
    function updateDevAddr(address _newValue) public onlyDev {
        emit UpdateDevAddr(devAddr, _newValue);
        devAddr = _newValue;
    }

    /**
     * @notice Rescue all available deployed deposit tokens back to Strategy
     * @param minReturnAmountAccepted min deposit tokens to receive
     */
    function rescueDeployedFunds(uint256 minReturnAmountAccepted) external virtual onlyOwner {
        _rescueDeployedFunds(minReturnAmountAccepted);
    }

    /**
     * @notice Recover ERC20 from contract
     * @param _token token address
     * @param _amount amount to recover
     */
    function recoverERC20(address _token, uint256 _amount) external onlyOwner {
        require(_amount > 0);
        require(IERC20(_token).transfer(msg.sender, _amount));
        emit Recovered(_token, _amount);
    }

    /**
     * @notice Recover AVAX from contract
     * @param _amount amount
     */
    function recoverAVAX(uint256 _amount) external onlyOwner {
        require(_amount > 0);
        payable(msg.sender).transfer(_amount);
        emit Recovered(address(0), _amount);
    }

    /*//////////////////////////////////////////////////////////////
                             INFRASTRUCTURE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Estimate reinvest reward
     * @return reward tokens
     */
    function estimateReinvestReward() external view returns (uint256) {
        uint256 unclaimedRewards = checkReward();
        if (unclaimedRewards >= MIN_TOKENS_TO_REINVEST) {
            return (unclaimedRewards * REINVEST_REWARD_BIPS) / BIPS_DIVISOR;
        }
        return 0;
    }

    /*//////////////////////////////////////////////////////////////
                        LEGACY INTERFACE
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Deprecated; Use "asset"
     */
    function depositToken() public view returns (address) {
        return asset;
    }

    /**
     * @dev Deprecated; Use "deposit(uint256 assets, address receiver)"
     */
    function deposit(uint256 _amount) external {
        deposit(_amount, msg.sender);
    }

    /**
     * @dev Deprecated; Use "withdraw(uint256 assets, address receiver, address owner)"
     */
    function withdraw(uint256 shares) external {
        redeem(shares, msg.sender, msg.sender);
    }

    /**
     * @dev Deprecated; Use "totalAssets()"
     */
    function totalDeposits() public view returns (uint256) {
        return totalAssets();
    }

    /**
     * @dev Deprecated; Use "convertToShares()"
     */
    function getSharesForDepositTokens(uint256 _amount) public view returns (uint256) {
        return convertToShares(_amount);
    }

    /**
     * @dev Deprecated; Use "convertToAssets()"
     */
    function getDepositTokensForShares(uint256 _amount) public view returns (uint256) {
        return convertToAssets(_amount);
    }

    function rescueDeployedFunds(uint256 minReturnAmountAccepted, bool) external onlyOwner {
        _rescueDeployedFunds(minReturnAmountAccepted);
    }

    uint256 public ADMIN_FEE_BIPS;
    event UpdateAdminFee(uint256 oldValue, uint256 newValue);

    /**
     * @notice Update admin fee
     * @dev Deprecated; Kept for compatibility
     * @param newValue fee in BIPS; required to be 0
     */
    function updateAdminFee(uint256 newValue) public onlyOwner {
        require(newValue == 0);
        emit UpdateAdminFee(ADMIN_FEE_BIPS, newValue);
        ADMIN_FEE_BIPS = newValue;
    }
}
