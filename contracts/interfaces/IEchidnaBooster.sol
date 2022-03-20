// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface IEchidnaBooster {
    function deposit(
        uint256 _pid,
        uint256 _amount,
        bool _depositToPlatypus,
        uint256 _deadline
    ) external;

    function withdraw(
        uint256 _pid,
        uint256 _amount,
        bool _claim,
        bool unwrap,
        uint256 minOut,
        uint256 deadline
    ) external;

    function withdrawAll(uint256 _pid, bool _claim) external;

    function pools(uint256 _pid)
        external
        view
        returns (
            address _pool,
            address _token,
            address _lpToken,
            address _rewardPool,
            bool _shutdown
        );

    function masterPlatypus() external view returns (address);

    function claimRewards(uint256[] calldata _pids) external;
}
