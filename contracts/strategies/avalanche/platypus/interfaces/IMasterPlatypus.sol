// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IMasterPlatypus {
    function poolLength() external view returns (uint256);

    function pendingTokens(uint256 _pid, address _user)
        external
        view
        returns (
            uint256 pendingPtp,
            address bonusTokenAddress,
            string memory bonusTokenSymbol,
            uint256 pendingBonusToken
        );

    function rewarderBonusTokenInfo(uint256 _pid)
        external
        view
        returns (address bonusTokenAddress, string memory bonusTokenSymbol);

    function massUpdatePools() external;

    function updatePool(uint256 _pid) external;

    function deposit(uint256 _pid, uint256 _amount) external returns (uint256, uint256);

    function multiClaim(uint256[] memory _pids)
        external
        returns (
            uint256,
            uint256[] memory,
            uint256[] memory
        );

    function withdraw(uint256 _pid, uint256 _amount) external returns (uint256, uint256);

    function emergencyWithdraw(uint256 _pid) external;

    function migrate(uint256[] calldata _pids) external;

    function depositFor(
        uint256 _pid,
        uint256 _amount,
        address _user
    ) external;

    function updateFactor(address _user, uint256 _newVePtpBalance) external;

    function userInfo(uint256 _pid, address _user)
        external
        view
        returns (
            uint256 _amount,
            uint256 _rewardDebt,
            uint256 _factor
        );

    function poolInfo(uint256 _pid)
        external
        view
        returns (
            address _lpToken,
            uint256 _allocPoint,
            uint256 _lastRewardTimestamp,
            uint256 _accPtpPerShare,
            address _rewarder,
            uint256 _sumOfFactors,
            uint256 _accPtpPerFactorShare
        );
}
