// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface IStakeDaoController {
    function strategies(address token) external view returns (address);
}
