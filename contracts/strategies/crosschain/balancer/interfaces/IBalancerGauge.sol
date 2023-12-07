// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IBalancerGauge {
    function balanceOf(address user) external view returns (uint256);
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function reward_count() external view returns (uint256);
    function reward_tokens(uint256 index) external view returns (address);
    function claimable_reward(address user, address rewardToken) external view returns (uint256);
    function claim_rewards() external;
    function bal_token() external view returns (address);
    function working_balances(address user) external view returns (uint256);
    function integrate_inv_supply_of(address user) external view returns (uint256);
    function period() external view returns (uint256);
    function period_timestamp(uint256 period) external view returns (uint256);
    function integrate_inv_supply(uint256 period) external view returns (uint256);
    function is_killed() external view returns (bool);
    function working_supply() external view returns (uint256);
    function inflation_rate(uint256 time) external view returns (uint256);
    function bal_pseudo_minter() external view returns (address);
    function factory() external view returns (address);
    function integrate_fraction(address user) external view returns (uint256);
    function user_checkpoint(address user) external returns (bool);
}
