// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IBooster {
    struct PoolInfo {
        address lptoken;
        address token;
        address gauge;
        address crvRewards;
        bool shutdown;
    }

    function poolInfo(uint256 _pid) external view returns (PoolInfo memory);

    function customMintRatio(uint256 _pid) external view returns (uint256);

    function mintRatio() external view returns (uint256);

    function penaltyShare() external view returns (uint256);

    function reservoirMinter() external view returns (address);

    function cvx() external view returns (address);
}
