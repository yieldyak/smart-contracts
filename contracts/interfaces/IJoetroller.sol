// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

// https://github.com/traderjoe-xyz/joe-lending/blob/HEAD/contracts/JoetrollerInterface.sol
interface IJoetroller {
    /*** Assets You Are In ***/
    function enterMarkets(address[] calldata jTokens) external returns (uint256[] memory);

    function exitMarket(address jToken) external returns (uint256);

    /*** Policy Hooks ***/
    function mintAllowed(
        address jToken,
        address minter,
        uint256 mintAmount
    ) external returns (uint256);

    function mintVerify(
        address jToken,
        address minter,
        uint256 mintAmount,
        uint256 mintTokens
    ) external;

    function redeemAllowed(
        address jToken,
        address redeemer,
        uint256 redeemTokens
    ) external returns (uint256);

    function redeemVerify(
        address jToken,
        address redeemer,
        uint256 redeemAmount,
        uint256 redeemTokens
    ) external;

    function borrowAllowed(
        address jToken,
        address borrower,
        uint256 borrowAmount
    ) external returns (uint256);

    function borrowVerify(
        address jToken,
        address borrower,
        uint256 borrowAmount
    ) external;

    function repayBorrowAllowed(
        address jToken,
        address payer,
        address borrower,
        uint256 repayAmount
    ) external returns (uint256);

    function repayBorrowVerify(
        address jToken,
        address payer,
        address borrower,
        uint256 repayAmount,
        uint256 borrowerIndex
    ) external;

    function liquidateBorrowAllowed(
        address jTokenBorrowed,
        address jTokenCollateral,
        address liquidator,
        address borrower,
        uint256 repayAmount
    ) external returns (uint256);

    function liquidateBorrowVerify(
        address jTokenBorrowed,
        address jTokenCollateral,
        address liquidator,
        address borrower,
        uint256 repayAmount,
        uint256 seizeTokens
    ) external;

    function seizeAllowed(
        address jTokenCollateral,
        address jTokenBorrowed,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external returns (uint256);

    function seizeVerify(
        address jTokenCollateral,
        address jTokenBorrowed,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external;

    function transferAllowed(
        address jToken,
        address src,
        address dst,
        uint256 transferTokens
    ) external returns (uint256);

    function transferVerify(
        address jToken,
        address src,
        address dst,
        uint256 transferTokens
    ) external;

    function markets(address jToken) external view returns (bool, uint256);

    /*** Liquidity/Liquidation Calculations ***/
    function liquidateCalculateSeizeTokens(
        address jTokenBorrowed,
        address jTokenCollateral,
        uint256 repayAmount
    ) external view returns (uint256, uint256);

    /*** Reward distribution functions ***/
    function rewardDistributor() external view returns (address);

    function claimReward(uint8 rewardType, address holder) external; //reward type 0 is joe, 1 is avax

    // rewardType  0 = JOE, 1 = AVAX
    function rewardSupplyState(uint8 rewardType, address holder) external view returns (uint224, uint32);

    function rewardBorrowState(uint8 rewardType, address holder) external view returns (uint224, uint32);

    function rewardSupplierIndex(
        uint8 rewardType,
        address contractAddress,
        address holder
    ) external view returns (uint256 supplierIndex);

    function rewardBorrowerIndex(
        uint8 rewardType,
        address contractAddress,
        address holder
    ) external view returns (uint256 borrowerIndex);

    function rewardAccrued(uint8, address) external view returns (uint256);
}
