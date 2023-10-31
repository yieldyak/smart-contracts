// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./Exponential.sol";
import "../interfaces/IUnitroller.sol";
import "../interfaces/IERC20Delegator.sol";

library LodestarLibrary {
    function calculateReward(IUnitroller unitroller, IERC20Delegator tokenDelegator, address account)
        internal
        view
        returns (uint256)
    {
        uint256 rewardAccrued = unitroller.compAccrued(account);
        uint256 supplyAccrued = calculateSupplyAccrued(unitroller, tokenDelegator, account);
        uint256 borrowAccrued = calculateBorrowAccrued(unitroller, tokenDelegator, account);
        return rewardAccrued + supplyAccrued + borrowAccrued;
    }

    function calculateSupplyAccrued(IUnitroller unitroller, IERC20Delegator tokenDelegator, address account)
        internal
        view
        returns (uint256)
    {
        (uint224 supplyStateIndex, uint32 supplyStateBlock) = unitroller.compSupplyState(address(tokenDelegator));
        uint256 supplySpeed = unitroller.compSupplySpeeds(address(tokenDelegator));
        uint32 blockNumber = uint32(unitroller.getBlockNumber());
        uint256 deltaBlocks = blockNumber - supplyStateBlock;

        if (deltaBlocks > 0 && supplySpeed > 0) {
            uint256 supplyTokens = tokenDelegator.totalSupply();
            uint256 compAccrued = deltaBlocks * supplySpeed;
            Exponential.Double memory ratio =
                supplyTokens > 0 ? Exponential.fraction(compAccrued, supplyTokens) : Exponential.Double({mantissa: 0});
            supplyStateIndex =
                uint224(Exponential.add_(Exponential.Double({mantissa: supplyStateIndex}), ratio).mantissa);
            supplyStateBlock = blockNumber;
        } else if (deltaBlocks > 0) {
            supplyStateBlock = blockNumber;
        }

        uint256 supplierIndex = unitroller.compSupplierIndex(address(tokenDelegator), account);
        Exponential.Double memory deltaIndex =
            Exponential.Double({mantissa: Exponential.sub_(supplyStateIndex, supplierIndex)});

        return Exponential.mul_(tokenDelegator.balanceOf(account), deltaIndex);
    }

    function calculateBorrowAccrued(IUnitroller unitroller, IERC20Delegator tokenDelegator, address account)
        internal
        view
        returns (uint256 borrowAccrued_)
    {
        Exponential.Double memory borrowIndex = Exponential.Double({mantissa: tokenDelegator.borrowIndex()});
        (uint224 borrowStateIndex, uint32 borrowStateBlock) = unitroller.compBorrowState(address(tokenDelegator));
        uint256 borrowSpeed = unitroller.compBorrowSpeeds(address(tokenDelegator));
        uint32 blockNumber = uint32(unitroller.getBlockNumber());
        uint256 deltaBlocks = Exponential.sub_(uint256(blockNumber), uint256(borrowStateBlock));
        if (deltaBlocks > 0 && borrowSpeed > 0) {
            uint256 borrowAmount = Exponential.div_(tokenDelegator.totalBorrows(), borrowIndex);
            uint256 compAccrued = Exponential.mul_(deltaBlocks, borrowSpeed);
            Exponential.Double memory ratio =
                borrowAmount > 0 ? Exponential.fraction(compAccrued, borrowAmount) : Exponential.Double({mantissa: 0});
            borrowStateIndex =
                uint224(Exponential.add_(Exponential.Double({mantissa: borrowStateIndex}), ratio).mantissa);
            borrowStateBlock = blockNumber;
        } else if (deltaBlocks > 0) {
            borrowStateBlock = blockNumber;
        }

        uint256 borrowerIndex = unitroller.compBorrowerIndex(address(tokenDelegator), account);
        Exponential.Double memory deltaIndex =
            Exponential.Double({mantissa: Exponential.sub_(borrowStateIndex, borrowerIndex)});

        uint256 borrowerAmount = Exponential.div_(tokenDelegator.borrowBalanceStored(account), borrowIndex);
        return Exponential.mul_(borrowerAmount, deltaIndex);
    }
}
