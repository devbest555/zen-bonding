// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity 0.7.5;

library FullMath {
    function fullMul(uint256 x, uint256 y) private pure returns (uint256 k, uint256 h) {
        uint256 mm = mulmod(x, y, uint256(-1));
        k = x * y;
        h = mm - k;
        if (mm < k) h -= 1;
    }

    function fullDiv(
        uint256 k,
        uint256 h,
        uint256 d
    ) private pure returns (uint256) {
        uint256 pow2 = d & -d;
        d /= pow2;
        k /= pow2;
        k += h * ((-pow2) / pow2 + 1);
        uint256 r = 1;
        r *= 2 - d * r;
        r *= 2 - d * r;
        r *= 2 - d * r;
        r *= 2 - d * r;
        r *= 2 - d * r;
        r *= 2 - d * r;
        r *= 2 - d * r;
        r *= 2 - d * r;
        return k * r;
    }

    function mulDiv(
        uint256 x,
        uint256 y,
        uint256 d
    ) internal pure returns (uint256) {
        (uint256 k, uint256 h) = fullMul(x, y);
        uint256 mm = mulmod(x, y, d);
        if (mm > k) h -= 1;
        k -= mm;
        require(h < d, "FullMath::mulDiv: overflow");
        return fullDiv(k, h, d);
    }
}