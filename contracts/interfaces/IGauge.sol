// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IGauge {
    function balanceOf(address account) external view returns (uint256);

    function derivedBalance(address account) external view returns (uint256);

    function derivedBalances(address) external view returns (uint256);

    function derivedSupply() external view returns (uint256);

    function earned(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function deposit(uint256 amount) external;

    function depositAll() external;

    function depositFor(uint256 amount, address account) external;

    function exit() external;

    function getReward() external;

    function kick(address account) external;

    function notifyRewardAmount(uint256 reward) external;

    function withdraw(uint256 amount) external;

    function withdrawAll() external;
}
