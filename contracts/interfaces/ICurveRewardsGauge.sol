// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface ICurveRewardsGauge {
    function deposit(uint256 _amount) external;

    function withdraw(uint256 _amount) external;

    function balanceOf(address _address) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function reward_contract() external view returns (address);

    function reward_tokens(uint256 token) external view returns (address);

    function reward_balances(address token) external view returns (uint256);

    function reward_integral(address token) external view returns (uint256);

    function reward_integral_for(address token, address user) external view returns (uint256);

    function claimable_reward_write(address user, address token) external returns (uint256);

    function claimable_reward(address user, address token) external view returns (uint256);

    function claim_rewards() external;

    function claim_sig() external view returns (bytes memory);
}
