// SPDX-License-Identifier: MIT
pragma solidity 0.7.3;

interface IVectorMainStaking {
    /// @notice Get the information of a pool
    /// @param _address the address of the deposit token to fetch information for
    /// @return pid the pid of the pool
    /// @return isActive true if the pool is active
    /// @return token the deposit Token
    /// @return lp the address of the PTP Lp token
    /// @return sizeLp the total number of LP tokens of this pool
    /// @return receipt - the address of the receipt token of this pool
    /// @return size the total number of stable staked by this pool
    /// @return rewards_addr the address of the rewarder
    /// @return helper the address of the poolHelper
    function getPoolInfo(address _address)
        external
        view
        returns (
            uint256 pid,
            bool isActive,
            address token,
            address lp,
            uint256 sizeLp,
            address receipt,
            uint256 size,
            address rewards_addr,
            address helper
        );
}
