// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface IRewardRouter {
    function feeQlpTracker() external view returns (address);

    function qlpManager() external view returns (address);

    function mintAndStakeQlpETH(uint256 _minUsdg, uint256 _minQlp) external payable returns (uint256);

    function mintAndStakeQlp(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minQlp)
        external
        returns (uint256);

    function handleRewards(bool _shouldClaimWeth, bool _shouldConvertWethToEth, bool _shouldAddIntoQLP) external;
}
