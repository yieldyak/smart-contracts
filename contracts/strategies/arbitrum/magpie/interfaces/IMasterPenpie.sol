// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IMasterPenpie {
    function stakingInfo(address _stakingToken, address _user)
        external
        view
        returns (uint256 depositAmount, uint256 availableAmount);

    function pendingTokens(address _stakingToken, address _user, address token)
        external
        view
        returns (
            uint256 _pendingPenpie,
            address _bonusTokenAddress,
            string memory _bonusTokenSymbol,
            uint256 _pendingBonusToken
        );

    function multiclaim(address[] calldata _stakingTokens) external;
}
