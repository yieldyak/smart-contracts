// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../lib/AccessControl.sol";

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);

    function balanceOf(address owner) external view returns (uint256);
}

interface IStrategy {
    function updateDevAddr(address newValue) external;

    // Joe
    function setExtraRewardSwapPair(address swapPair) external;

    // JoeLending
    function updateLeverage(uint256 _leverageLevel, uint256 _leverageBips) external;

    // Curve
    function updateCrvAvaxSwapPair(address swapPair) external;

    function updateMaxSwapSlippage(uint256 slippageBips) external;

    function removeReward(address rewardToken) external;

    function addReward(address rewardToken, address swapPair) external;

    // Benqi
    function updateLeverage(
        uint256 _leverageLevel,
        uint256 _leverageBips,
        uint256 _redeemLimitSafetyMargin
    ) external;

    // Aave
    function updateLeverage(
        uint256 _leverageLevel,
        uint256 _safetyFactor,
        uint256 _minMinting,
        uint256 _leverageBips
    ) external;
}

/**
 * @notice Role-based fee collector for YakStrategy contracts
 * @dev YakFeeCollector may be used as `devAddr` on YakStrategy contracts
 */
contract YakFeeCollectorV1 is AccessControl {
    /// @notice Role to sweep funds from this contract
    bytes32 public constant TOKEN_SWEEPER_ROLE = keccak256("TOKEN_SWEEPER_ROLE");

    /// @notice Role to update `devAddr` on YakStrategy
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @notice Role to manage strategy for onlyDev modifier
    bytes32 public constant DEV_ROLE = keccak256("DEV_ROLE");

    event SetDev(address indexed upgrader, address indexed strategy, address newValue);
    event Sweep(address indexed sweeper, address indexed token, uint256 amount);

    constructor(
        address _manager,
        address _tokenSweeper,
        address _upgrader,
        address _dev
    ) {
        _setupRole(DEFAULT_ADMIN_ROLE, _manager);
        _setupRole(TOKEN_SWEEPER_ROLE, _tokenSweeper);
        _setupRole(UPGRADER_ROLE, _upgrader);
        _setupRole(DEV_ROLE, _dev);
    }

    receive() external payable {}

    /**
     * @notice Set new value of `devAddr`
     * @dev Restricted to `UPGRADER_ROLE`
     * @param strategy address
     * @param newDevAddr new value
     */
    function setDev(address strategy, address newDevAddr) external {
        require(hasRole(UPGRADER_ROLE, msg.sender), "setDev::auth");
        IStrategy(strategy).updateDevAddr(newDevAddr);
        emit SetDev(msg.sender, strategy, newDevAddr);
    }

    /**
     * @notice Collect ERC20 from this contract
     * @dev Restricted to `TOKEN_SWEEPER_ROLE`
     * @param tokenAddress address
     * @param tokenAmount amount
     */
    function sweepTokens(address tokenAddress, uint256 tokenAmount) external {
        require(hasRole(TOKEN_SWEEPER_ROLE, msg.sender), "sweepTokens::auth");
        uint256 balance = IERC20(tokenAddress).balanceOf(address(this));
        if (balance < tokenAmount) {
            tokenAmount = balance;
        }
        require(tokenAmount > 0, "sweepTokens::balance");
        require(IERC20(tokenAddress).transfer(msg.sender, tokenAmount), "sweepTokens::transfer failed");
        emit Sweep(msg.sender, tokenAddress, tokenAmount);
    }

    /**
     * @notice Collect ERC20 from this contract
     * @dev Restricted to `TOKEN_SWEEPER_ROLE`
     * @param amount amount
     */
    function sweepAVAX(uint256 amount) external {
        require(hasRole(TOKEN_SWEEPER_ROLE, msg.sender), "sweepAVAX::auth");
        uint256 balance = address(this).balance;
        if (balance < amount) {
            amount = balance;
        }
        require(amount > 0, "sweepAVAX::balance");
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success == true, "sweepAVAX::transfer failed");
        emit Sweep(msg.sender, address(0), amount);
    }

    // DEV functions

    function setExtraRewardSwapPair(address strategy, address swapPair) external {
        require(hasRole(DEV_ROLE, msg.sender), "execute::auth");
        IStrategy(strategy).setExtraRewardSwapPair(swapPair);
    }

    function updateLeverage(
        address strategy,
        uint256 leverageLevel,
        uint256 leverageBips
    ) external {
        require(hasRole(DEV_ROLE, msg.sender), "execute::auth");
        IStrategy(strategy).updateLeverage(leverageLevel, leverageBips);
    }

    function updateLeverage(
        address strategy,
        uint256 leverageLevel,
        uint256 leverageBips,
        uint256 redeemLimitSafetyMargin
    ) external {
        require(hasRole(DEV_ROLE, msg.sender), "execute::auth");
        IStrategy(strategy).updateLeverage(leverageLevel, leverageBips, redeemLimitSafetyMargin);
    }

    function updateLeverage(
        address strategy,
        uint256 leverageLevel,
        uint256 safetyFactor,
        uint256 minMinting,
        uint256 leverageBips
    ) external {
        require(hasRole(DEV_ROLE, msg.sender), "execute::auth");
        IStrategy(strategy).updateLeverage(leverageLevel, safetyFactor, minMinting, leverageBips);
    }

    function updateCrvAvaxSwapPair(address strategy, address swapPair) external {
        require(hasRole(DEV_ROLE, msg.sender), "execute::auth");
        IStrategy(strategy).updateCrvAvaxSwapPair(swapPair);
    }

    function updateMaxSwapSlippage(address strategy, uint256 slippageBips) external {
        require(hasRole(DEV_ROLE, msg.sender), "execute::auth");
        IStrategy(strategy).updateMaxSwapSlippage(slippageBips);
    }

    function removeReward(address strategy, address rewardToken) external {
        require(hasRole(DEV_ROLE, msg.sender), "execute::auth");
        IStrategy(strategy).removeReward(rewardToken);
    }

    function addReward(
        address strategy,
        address rewardToken,
        address swapPair
    ) external {
        require(hasRole(DEV_ROLE, msg.sender), "execute::auth");
        IStrategy(strategy).addReward(rewardToken, swapPair);
    }
}
