// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../lib/Ownable.sol";
import "../../../interfaces/IERC20.sol";
import "../../../interfaces/IYakStrategy.sol";
import "../../crosschain/gmx/interfaces/IGmxDepositor.sol";
import "./interfaces/IGmxRewardRouter.sol";
import "./interfaces/IGmxRewardTracker.sol";

/**
 * @notice Withdrawal-only integration for the legacy Avalanche GLP strategy.
 * @dev GMX rewards belong to the owner; they are not compounded into GLP.
 */
contract GmxProxy is Ownable {
    address internal constant GMX = 0x62edc0692BD897D2295872a9FFCac5425011c661;
    address internal constant fsGLP = 0x5643F4b25E36478eE1E90418d5343cb6591BcB9d;
    IGmxDepositor public immutable gmxDepositor;
    address public immutable gmxRewardRouter;
    address public immutable glpStrategy;
    IGmxRewardTracker public immutable gmxRewardTracker;
    IGmxRewardTracker public immutable feeGlpTracker;

    event RewardsClaimed(address indexed receiver, uint256 amount);

    constructor(address _gmxDepositor, address _gmxRewardRouter, address _glpStrategy, address _owner) {
        require(_gmxDepositor.code.length > 0, "GmxProxy::invalid depositor");
        require(IYakStrategy(_glpStrategy).depositToken() == fsGLP, "GmxProxy::invalid strategy");
        gmxDepositor = IGmxDepositor(_gmxDepositor);
        gmxRewardRouter = _gmxRewardRouter;
        glpStrategy = _glpStrategy;
        gmxRewardTracker = IGmxRewardTracker(IGmxRewardRouter(_gmxRewardRouter).extendedGmxTracker());
        require(gmxRewardTracker.rewardToken() == GMX, "GmxProxy::invalid reward token");
        feeGlpTracker = IGmxRewardTracker(IGmxRewardRouter(_gmxRewardRouter).feeGlpTracker());
        transferOwnership(_owner);
    }

    /**
     * @notice Legacy selector retained for strategy share accounting.
     */
    function totalDeposits(address) external view returns (uint256) {
        return feeGlpTracker.stakedAmounts(address(gmxDepositor));
    }

    /**
     * @notice No rewards are offered to the deprecated compounding strategy.
     */
    function pendingRewards(address) external pure returns (uint256) {
        return 0;
    }

    function withdrawGlp(uint256 amount) external {
        require(msg.sender == glpStrategy, "GmxProxy::onlyGLPStrategy");
        bytes memory result = _execute(fsGLP, abi.encodeWithSelector(IERC20.transfer.selector, msg.sender, amount));
        require(abi.decode(result, (bool)), "GmxProxy::transfer failed");
    }

    /**
     * @notice Claim the depositor's liquid GMX rewards directly to the current owner.
     */
    function claimRewards() external onlyOwner returns (uint256 amount) {
        bytes memory result =
            _execute(address(gmxRewardTracker), abi.encodeWithSelector(IGmxRewardTracker.claim.selector, owner()));
        amount = abi.decode(result, (uint256));
        emit RewardsClaimed(owner(), amount);
    }

    function _execute(address target, bytes memory data) private returns (bytes memory result) {
        bool success;
        (success, result) = gmxDepositor.execute(target, 0, data);
        require(success, "GmxProxy::execute failed");
    }
}
