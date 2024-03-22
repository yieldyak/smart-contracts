// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface ILamaPay {
    function token() external view returns (address);
    function createStream(address to, uint216 amountPerSec) external;
    function deposit(uint256 amount) external;
    function withdrawable(address from, address to, uint216 amountPerSec)
        external
        view
        returns (uint256 withdrawableAmount, uint256 lastUpdate, uint256 owed);
    function withdraw(address from, address to, uint216 amountPerSec) external;
    function modifyStream(address oldTo, uint216 oldAmountPerSec, address to, uint216 amountPerSec) external;
}
