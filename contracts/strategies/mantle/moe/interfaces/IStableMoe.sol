// SPDX-License-Identifier: MIT

interface IStableMoe {
    function getPendingRewards(address account) external view returns (address[] memory, uint256[] memory);
}
