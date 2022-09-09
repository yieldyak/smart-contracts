// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "../../../../lib/SafeMath.sol";
import "./DSMath.sol";
import "../interfaces/IPlatypusPool.sol";
import "../interfaces/IPlatypusAsset.sol";

library PlatypusLibrary {
    using SafeMath for uint256;
    using DSMath for uint256;

    uint256 internal constant WAD = 10**18;
    uint256 internal constant RAY = 10**27;

    function calculateDepositFee(
        address pool,
        address asset,
        uint256 amount
    ) internal view returns (uint256 fee) {
        return
            _depositFee(
                IPlatypusPool(pool).getSlippageParamK(),
                IPlatypusPool(pool).getSlippageParamN(),
                IPlatypusPool(pool).getC1(),
                IPlatypusPool(pool).getXThreshold(),
                IPlatypusAsset(asset).cash(),
                IPlatypusAsset(asset).liability(),
                amount
            );
    }

    function _depositFee(
        uint256 k,
        uint256 n,
        uint256 c1,
        uint256 xThreshold,
        uint256 cash,
        uint256 liability,
        uint256 amount
    ) private pure returns (uint256) {
        // cover case where the asset has no liquidity yet
        if (liability == 0) {
            return 0;
        }

        uint256 covBefore = cash.wdiv(liability);
        if (covBefore <= 10**18) {
            return 0;
        }

        uint256 covAfter = (cash.add(amount)).wdiv(liability.add(amount));
        uint256 slippageBefore = _slippageFunc(k, n, c1, xThreshold, covBefore);
        uint256 slippageAfter = _slippageFunc(k, n, c1, xThreshold, covAfter);

        // (Li + Di) * g(cov_after) - Li * g(cov_before)
        return ((liability.add(amount)).wmul(slippageAfter)) - (liability.wmul(slippageBefore));
    }

    function _slippageFunc(
        uint256 k,
        uint256 n,
        uint256 c1,
        uint256 xThreshold,
        uint256 x
    ) private pure returns (uint256) {
        if (x < xThreshold) {
            return c1.sub(x);
        } else {
            return k.wdiv((((x.mul(RAY)).div(WAD)).rpow(n).mul(WAD)).div(RAY)); // k / (x ** n)
        }
    }

    function depositTokenToAsset(
        address asset,
        uint256 amount,
        uint256 depositFee
    ) internal view returns (uint256 liquidity) {
        if (IPlatypusAsset(asset).liability() == 0) {
            liquidity = amount.sub(depositFee);
        } else {
            liquidity = ((amount.sub(depositFee)).mul(IPlatypusAsset(asset).totalSupply())).div(
                IPlatypusAsset(asset).liability()
            );
        }
    }
}
