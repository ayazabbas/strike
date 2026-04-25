// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "./ParimutuelTypes.sol";

/// @title ParimutuelPricingLib
/// @notice Pure helpers for parimutuel reward-share issuance previews.
/// @dev Principal and reward shares are expected to use the same 1e18 scale in the current contracts.
library ParimutuelPricingLib {
    uint256 internal constant BPS_DENOMINATOR = 10_000;
    uint256 internal constant WAD = 1e18;
    uint256 internal constant LN2_WAD = 693_147_180_559_945_309;

    function quoteFlat(uint256 netPrincipalAdded) internal pure returns (uint256 rewardSharesOut) {
        return netPrincipalAdded;
    }

    function quotePiecewise(
        uint256 currentPrincipal,
        uint256 netPrincipalAdded,
        ParimutuelPiecewiseBand[] memory bands,
        uint32 tailRateBps
    ) internal pure returns (uint256 rewardSharesOut) {
        require(tailRateBps <= BPS_DENOMINATOR, "ParimutuelPricingLib: invalid tail rate");

        uint256 remaining = netPrincipalAdded;
        uint256 cursor = currentPrincipal;
        uint256 previousUpperBound;

        for (uint256 i = 0; i < bands.length && remaining > 0; i++) {
            require(bands[i].rateBps <= BPS_DENOMINATOR, "ParimutuelPricingLib: invalid band rate");
            require(bands[i].upperBound > previousUpperBound, "ParimutuelPricingLib: invalid band bounds");
            previousUpperBound = bands[i].upperBound;

            if (cursor >= bands[i].upperBound) {
                continue;
            }

            uint256 capacity = bands[i].upperBound - cursor;
            uint256 segment = Math.min(remaining, capacity);
            rewardSharesOut += Math.mulDiv(segment, bands[i].rateBps, BPS_DENOMINATOR);
            cursor += segment;
            remaining -= segment;
        }

        if (remaining > 0) {
            rewardSharesOut += Math.mulDiv(remaining, tailRateBps, BPS_DENOMINATOR);
        }
    }

    /// @notice Quote the continuous independent log curve.
    /// @dev Formula: L * ln((L + S + d) / (L + S)).
    ///      `liquidityParam` is L in the same units as principal. The return value is rounded down.
    function quoteIndependentLog(
        uint256 currentPrincipal,
        uint256 netPrincipalAdded,
        uint256 liquidityParam
    ) internal pure returns (uint256 rewardSharesOut) {
        require(liquidityParam > 0, "ParimutuelPricingLib: invalid log liquidity");

        if (netPrincipalAdded == 0) {
            return 0;
        }

        uint256 denominator = liquidityParam + currentPrincipal;
        uint256 ratioWad = Math.mulDiv(denominator + netPrincipalAdded, WAD, denominator);
        uint256 lnRatioWad = _lnWadGteOne(ratioWad);

        rewardSharesOut = Math.mulDiv(liquidityParam, lnRatioWad, WAD);
    }

    /// @notice Natural log for WAD-scaled values greater than or equal to one.
    /// @dev Uses binary logarithm iteration then converts by ln(2). Rounded down.
    function _lnWadGteOne(uint256 xWad) internal pure returns (uint256) {
        require(xWad >= WAD, "ParimutuelPricingLib: ln input < 1");
        return Math.mulDiv(_log2WadGteOne(xWad), LN2_WAD, WAD);
    }

    /// @notice Binary log for WAD-scaled values greater than or equal to one.
    /// @dev Normalizes to [1, 2), then extracts fractional bits. Rounded down.
    function _log2WadGteOne(uint256 xWad) internal pure returns (uint256 resultWad) {
        require(xWad >= WAD, "ParimutuelPricingLib: log2 input < 1");

        uint256 integerPart = Math.log2(xWad / WAD);
        resultWad = integerPart * WAD;

        uint256 y = xWad >> integerPart;

        for (uint256 delta = WAD / 2; delta > 0; delta >>= 1) {
            y = Math.mulDiv(y, y, WAD);

            if (y >= 2 * WAD) {
                resultWad += delta;
                y >>= 1;
            }
        }
    }
}
