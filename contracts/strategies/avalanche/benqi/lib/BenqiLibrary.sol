// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../../lib/SafeMath.sol";
import "./Exponential.sol";
import "../interfaces/IBenqiUnitroller.sol";
import "../interfaces/IBenqiERC20Delegator.sol";

library BenqiLibrary {
    using SafeMath for uint256;

    function calculateReward(
        IBenqiUnitroller rewardController,
        IBenqiERC20Delegator tokenDelegator,
        uint8 tokenIndex,
        address account
    ) internal view returns (uint256) {
        uint256 rewardAccrued = rewardController.rewardAccrued(tokenIndex, account);
        return
            rewardAccrued.add(supplyAccrued(rewardController, tokenDelegator, tokenIndex, account)).add(
                borrowAccrued(rewardController, tokenDelegator, tokenIndex, account)
            );
    }

    function supplyAccrued(
        IBenqiUnitroller rewardController,
        IBenqiERC20Delegator tokenDelegator,
        uint8 tokenIndex,
        address account
    ) internal view returns (uint256) {
        Exponential.Double memory supplyIndex = Exponential.Double({
            mantissa: _supplyIndex(rewardController, tokenDelegator, tokenIndex)
        });
        Exponential.Double memory supplierIndex = Exponential.Double({
            mantissa: rewardController.rewardSupplierIndex(tokenIndex, address(tokenDelegator), account)
        });

        if (supplierIndex.mantissa == 0 && supplyIndex.mantissa > 0) {
            supplierIndex.mantissa = 1e36;
        }
        Exponential.Double memory deltaIndex = supplyIndex.mantissa > 0
            ? Exponential.sub_(supplyIndex, supplierIndex)
            : Exponential.Double({mantissa: 0});
        return Exponential.mul_(tokenDelegator.balanceOf(account), deltaIndex);
    }

    function borrowAccrued(
        IBenqiUnitroller rewardController,
        IBenqiERC20Delegator tokenDelegator,
        uint8 tokenIndex,
        address account
    ) internal view returns (uint256 borrowAccrued_) {
        Exponential.Double memory borrowerIndex = Exponential.Double({
            mantissa: rewardController.rewardBorrowerIndex(tokenIndex, address(tokenDelegator), account)
        });
        borrowAccrued_ = 0;
        if (borrowerIndex.mantissa > 0) {
            Exponential.Exp memory marketBorrowIndex = Exponential.Exp({mantissa: tokenDelegator.borrowIndex()});
            Exponential.Double memory borrowIndex = Exponential.Double({
                mantissa: _borrowIndex(rewardController, tokenDelegator, tokenIndex, marketBorrowIndex)
            });
            if (borrowIndex.mantissa > 0) {
                Exponential.Double memory deltaIndex = Exponential.sub_(borrowIndex, borrowerIndex);
                uint256 borrowerAmount = Exponential.div_(
                    tokenDelegator.borrowBalanceStored(address(this)),
                    marketBorrowIndex
                );
                borrowAccrued_ = Exponential.mul_(borrowerAmount, deltaIndex);
            }
        }
    }

    function _supplyIndex(
        IBenqiUnitroller rewardController,
        IBenqiERC20Delegator tokenDelegator,
        uint8 rewardType
    ) private view returns (uint224) {
        (uint224 supplyStateIndex, uint256 supplyStateTimestamp) = rewardController.rewardSupplyState(
            rewardType,
            address(tokenDelegator)
        );

        uint256 supplySpeed = rewardController.supplyRewardSpeeds(rewardType, address(tokenDelegator));
        uint256 deltaTimestamps = Exponential.sub_(block.timestamp, uint256(supplyStateTimestamp));
        if (deltaTimestamps > 0 && supplySpeed > 0) {
            uint256 supplyTokens = IERC20(tokenDelegator).totalSupply();
            uint256 qiAccrued = Exponential.mul_(deltaTimestamps, supplySpeed);
            Exponential.Double memory ratio = supplyTokens > 0
                ? Exponential.fraction(qiAccrued, supplyTokens)
                : Exponential.Double({mantissa: 0});
            Exponential.Double memory index = Exponential.add_(Exponential.Double({mantissa: supplyStateIndex}), ratio);
            return Exponential.safe224(index.mantissa, "new index exceeds 224 bits");
        }
        return 0;
    }

    function _borrowIndex(
        IBenqiUnitroller rewardController,
        IBenqiERC20Delegator tokenDelegator,
        uint8 rewardType,
        Exponential.Exp memory marketBorrowIndex
    ) private view returns (uint224) {
        (uint224 borrowStateIndex, uint256 borrowStateTimestamp) = rewardController.rewardBorrowState(
            rewardType,
            address(tokenDelegator)
        );
        uint256 borrowSpeed = rewardController.borrowRewardSpeeds(rewardType, address(tokenDelegator));
        uint256 deltaTimestamps = Exponential.sub_(block.timestamp, uint256(borrowStateTimestamp));
        if (deltaTimestamps > 0 && borrowSpeed > 0) {
            uint256 borrowAmount = Exponential.div_(tokenDelegator.totalBorrows(), marketBorrowIndex);
            uint256 qiAccrued = Exponential.mul_(deltaTimestamps, borrowSpeed);
            Exponential.Double memory ratio = borrowAmount > 0
                ? Exponential.fraction(qiAccrued, borrowAmount)
                : Exponential.Double({mantissa: 0});
            Exponential.Double memory index = Exponential.add_(Exponential.Double({mantissa: borrowStateIndex}), ratio);
            return Exponential.safe224(index.mantissa, "new index exceeds 224 bits");
        }
        return 0;
    }
}
