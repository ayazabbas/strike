// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/ParimutuelPricingLib.sol";
import "../src/ParimutuelTypes.sol";

contract ParimutuelPricingLibHarness {
    function quoteFlat(uint256 netPrincipalAdded) external pure returns (uint256) {
        return ParimutuelPricingLib.quoteFlat(netPrincipalAdded);
    }

    function quotePiecewise(
        uint256 currentPrincipal,
        uint256 netPrincipalAdded,
        ParimutuelPiecewiseBand[] memory bands,
        uint32 tailRateBps
    ) external pure returns (uint256) {
        return ParimutuelPricingLib.quotePiecewise(currentPrincipal, netPrincipalAdded, bands, tailRateBps);
    }

    function quoteIndependentLog(uint256 currentPrincipal, uint256 netPrincipalAdded, uint256 liquidityParam)
        external
        pure
        returns (uint256)
    {
        return ParimutuelPricingLib.quoteIndependentLog(currentPrincipal, netPrincipalAdded, liquidityParam);
    }
}

contract ParimutuelPricingLibTest is Test {
    ParimutuelPricingLibHarness internal harness;

    function setUp() public {
        harness = new ParimutuelPricingLibHarness();
    }

    function _bands() internal pure returns (ParimutuelPiecewiseBand[] memory bands) {
        bands = new ParimutuelPiecewiseBand[](3);
        bands[0] = ParimutuelPiecewiseBand({upperBound: 5_000 ether, rateBps: 10_000});
        bands[1] = ParimutuelPiecewiseBand({upperBound: 20_000 ether, rateBps: 8_500});
        bands[2] = ParimutuelPiecewiseBand({upperBound: 60_000 ether, rateBps: 6_800});
    }

    function _assertIndependentLogGolden(
        uint256 currentPrincipal,
        uint256 netPrincipalAdded,
        uint256 liquidityParam,
        uint256 expected
    ) internal view {
        uint256 quoted = harness.quoteIndependentLog(currentPrincipal, netPrincipalAdded, liquidityParam);
        assertApproxEqAbs(quoted, expected, 1e10);
    }

    function test_QuoteFlat_ReturnsNetPrincipal() public view {
        assertEq(harness.quoteFlat(123 ether), 123 ether);
    }

    function test_QuotePiecewise_WithinFirstBand() public view {
        uint256 quoted = harness.quotePiecewise(0, 1_000 ether, _bands(), 5_200);
        assertEq(quoted, 1_000 ether);
    }

    function test_QuotePiecewise_CrossesBands() public view {
        uint256 quoted = harness.quotePiecewise(4_000 ether, 3_000 ether, _bands(), 5_200);

        uint256 expected = 1_000 ether;
        expected += (2_000 ether * 8_500) / 10_000;

        assertEq(quoted, expected);
    }

    function test_QuotePiecewise_UsesTailRateAfterFinalBand() public view {
        uint256 quoted = harness.quotePiecewise(59_000 ether, 3_000 ether, _bands(), 5_200);

        uint256 expected = (1_000 ether * 6_800) / 10_000;
        expected += (2_000 ether * 5_200) / 10_000;

        assertEq(quoted, expected);
    }

    function test_QuotePiecewise_IsSplitInvariantForCrossBandBuy() public view {
        ParimutuelPiecewiseBand[] memory bands = _bands();

        uint256 oneShot = harness.quotePiecewise(4_000 ether, 21_000 ether, bands, 5_200);
        uint256 firstLeg = harness.quotePiecewise(4_000 ether, 6_000 ether, bands, 5_200);
        uint256 secondLeg = harness.quotePiecewise(10_000 ether, 15_000 ether, bands, 5_200);

        assertEq(oneShot, firstLeg + secondLeg);
    }

    function test_QuoteIndependentLog_MatchesMediumCurveReference() public view {
        uint256 quoted = harness.quoteIndependentLog(0, 10_000 ether, 40_000 ether);

        assertApproxEqAbs(quoted, 8_925_742052568390230651, 1e6);
    }

    function test_QuoteIndependentLog_PenalizesCrowdedOutcome() public view {
        uint256 uncrowded = harness.quoteIndependentLog(0, 1_000 ether, 40_000 ether);
        uint256 crowded = harness.quoteIndependentLog(40_000 ether, 1_000 ether, 40_000 ether);
        uint256 veryCrowded = harness.quoteIndependentLog(100_000 ether, 1_000 ether, 40_000 ether);

        assertGt(uncrowded, crowded);
        assertGt(crowded, veryCrowded);
        assertApproxEqAbs(crowded, 496_900799942286132451, 1e6);
        assertApproxEqAbs(veryCrowded, 284_698710754559187024, 1e6);
    }

    function test_QuoteIndependentLog_IsSplitInvariant() public view {
        uint256 liquidity = 40_000 ether;
        uint256 oneShot = harness.quoteIndependentLog(0, 10_000 ether, liquidity);

        uint256 split;
        uint256 currentPrincipal;
        for (uint256 i = 0; i < 10; i++) {
            split += harness.quoteIndependentLog(currentPrincipal, 1_000 ether, liquidity);
            currentPrincipal += 1_000 ether;
        }

        assertApproxEqAbs(oneShot, split, 1e9);
    }

    function testFuzz_QuoteIndependentLog_MonotonicCrowding(
        uint256 currentPrincipalA,
        uint256 currentPrincipalB,
        uint256 netPrincipalAdded,
        uint256 liquidityParam
    ) public view {
        currentPrincipalA = bound(currentPrincipalA, 0, 1_000_000 ether);
        currentPrincipalB = bound(currentPrincipalB, currentPrincipalA, 1_000_000 ether);
        netPrincipalAdded = bound(netPrincipalAdded, 1, 100_000 ether);
        liquidityParam = bound(liquidityParam, 1 ether, 1_000_000 ether);

        uint256 lessCrowded = harness.quoteIndependentLog(currentPrincipalA, netPrincipalAdded, liquidityParam);
        uint256 moreCrowded = harness.quoteIndependentLog(currentPrincipalB, netPrincipalAdded, liquidityParam);

        assertGe(lessCrowded, moreCrowded);
    }

    function testFuzz_QuoteIndependentLog_PositiveAndNoMoreThanNetPrincipal(
        uint256 currentPrincipal,
        uint256 netPrincipalAdded,
        uint256 liquidityParam
    ) public view {
        currentPrincipal = bound(currentPrincipal, 0, 1_000_000 ether);
        netPrincipalAdded = bound(netPrincipalAdded, 1e12, 100_000 ether);
        liquidityParam = bound(liquidityParam, 1 ether, 1_000_000 ether);

        uint256 quoted = harness.quoteIndependentLog(currentPrincipal, netPrincipalAdded, liquidityParam);

        assertGt(quoted, 0);
        assertLe(quoted, netPrincipalAdded);
    }

    function testFuzz_QuoteIndependentLog_SplitInvariantWithinRoundingTolerance(
        uint256 currentPrincipal,
        uint256 netPrincipalAdded,
        uint256 liquidityParam,
        uint8 rawParts
    ) public view {
        currentPrincipal = bound(currentPrincipal, 0, 1_000_000 ether);
        netPrincipalAdded = bound(netPrincipalAdded, 1 ether, 100_000 ether);
        liquidityParam = bound(liquidityParam, 1 ether, 1_000_000 ether);
        uint256 parts = bound(rawParts, 2, 20);

        uint256 oneShot = harness.quoteIndependentLog(currentPrincipal, netPrincipalAdded, liquidityParam);
        uint256 split;
        uint256 cursor = currentPrincipal;
        uint256 consumed;

        for (uint256 i = 0; i < parts; i++) {
            uint256 leg = i == parts - 1 ? netPrincipalAdded - consumed : netPrincipalAdded / parts;
            split += harness.quoteIndependentLog(cursor, leg, liquidityParam);
            cursor += leg;
            consumed += leg;
        }

        assertApproxEqAbs(oneShot, split, parts * 1e10);
    }

    function test_QuoteIndependentLog_HighPrecisionGoldenVectors() public view {
        _assertIndependentLogGolden(0, 1 ether, 40_000 ether, 999_987500208329427);
        _assertIndependentLogGolden(0, 100 ether, 40_000 ether, 99_875207943487959209);
        _assertIndependentLogGolden(0, 1_000 ether, 40_000 ether, 987_704503614860040572);
        _assertIndependentLogGolden(0, 10_000 ether, 40_000 ether, 8_925_742052568390230651);
        _assertIndependentLogGolden(0, 40_000 ether, 40_000 ether, 27_725_887222397812376689);
        _assertIndependentLogGolden(0, 100_000 ether, 40_000 ether, 50_110_518739814719827524);
        _assertIndependentLogGolden(40_000 ether, 10_000 ether, 40_000 ether, 4_711_321426255338181551);
        _assertIndependentLogGolden(100_000 ether, 10_000 ether, 40_000 ether, 2_759_714859478058058936);
        _assertIndependentLogGolden(0, 10_000 ether, 100_000 ether, 9_531_017980432486004395);
        _assertIndependentLogGolden(500_000 ether, 10_000 ether, 100_000 ether, 1_652_930195121056392092);
        _assertIndependentLogGolden(1_000_000 ether, 100_000 ether, 1_000_000 ether, 48_790_164169432003065374);
    }

    function test_QuoteIndependentLog_RealisticOverflowBounds() public view {
        uint256 quoted = harness.quoteIndependentLog(1_000_000 ether, 100_000 ether, 1_000_000 ether);

        assertGt(quoted, 0);
        assertLe(quoted, 100_000 ether);
    }

    function test_Gas_QuoteCurves_LogsComparison() public {
        ParimutuelPiecewiseBand[] memory bands = _bands();

        uint256 gasBeforePiecewise = gasleft();
        uint256 piecewiseQuote = harness.quotePiecewise(4_000 ether, 10_000 ether, bands, 5_200);
        uint256 piecewiseGas = gasBeforePiecewise - gasleft();

        uint256 gasBeforeLog = gasleft();
        uint256 logQuote = harness.quoteIndependentLog(4_000 ether, 10_000 ether, 40_000 ether);
        uint256 logGas = gasBeforeLog - gasleft();

        assertGt(piecewiseQuote, 0);
        assertGt(logQuote, 0);
        emit log_named_uint("piecewise quote gas", piecewiseGas);
        emit log_named_uint("independent log quote gas", logGas);
    }

    function test_QuoteIndependentLog_RevertOnInvalidLiquidity() public {
        vm.expectRevert("ParimutuelPricingLib: invalid log liquidity");
        harness.quoteIndependentLog(0, 1 ether, 0);
    }

    function test_QuotePiecewise_RevertOnInvalidTailRate() public {
        vm.expectRevert("ParimutuelPricingLib: invalid tail rate");
        harness.quotePiecewise(0, 1 ether, _bands(), 10_001);
    }
}
