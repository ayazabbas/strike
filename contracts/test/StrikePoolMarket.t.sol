// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/MockStrikeToken.sol";
import "../src/ParimutuelTypes.sol";
import "../src/StrikeCreditReserve.sol";
import "../src/StrikeParimutuelFactory.sol";
import "../src/StrikePoolManager.sol";
import "../src/StrikePoolRedemption.sol";
import "../src/StrikePoolVault.sol";

contract StrikePoolMarketTest is Test {
    StrikeParimutuelFactory public factory;
    StrikePoolManager public manager;
    StrikePoolRedemption public redemption;
    StrikePoolVault public vault;
    StrikeCreditReserve public creditReserve;
    MockStrikeToken public strike;

    uint256 internal constant EVENT_ID = 20260503;
    uint256 internal signerKey = 0xA11CE;
    address public signer;
    address public admin = address(0x1);
    address public creator = address(0x2);
    address public alice = address(0x3);
    address public bob = address(0x4);
    address public feeRecipient = address(0x5);

    function setUp() public {
        signer = vm.addr(signerKey);

        strike = new MockStrikeToken();
        factory = new StrikeParimutuelFactory(admin);
        vault = new StrikePoolVault(admin, address(strike));
        creditReserve = new StrikeCreditReserve(admin, address(strike));
        manager = new StrikePoolManager(admin, address(factory), address(vault), address(creditReserve), feeRecipient);
        redemption = new StrikePoolRedemption(admin, address(manager), address(vault), address(creditReserve));

        vm.startPrank(admin);
        factory.setPoolManager(address(manager));
        factory.grantRole(factory.MARKET_CREATOR_ROLE(), creator);
        manager.grantRole(manager.REDEMPTION_ROLE(), address(redemption));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(manager));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(redemption));
        creditReserve.grantRole(creditReserve.CREDIT_SIGNER_ROLE(), signer);
        creditReserve.grantRole(creditReserve.SPENDER_ROLE(), address(manager));
        creditReserve.grantRole(creditReserve.SPENDER_ROLE(), address(redemption));
        creditReserve.createEvent(EVENT_ID, uint64(block.timestamp), uint64(block.timestamp + 2 days));
        vm.stopPrank();

        strike.mint(alice, 1_000_000e18);
        strike.mint(bob, 1_000_000e18);
        strike.mint(admin, 1_000_000e18);

        vm.prank(alice);
        strike.approve(address(manager), type(uint256).max);
        vm.prank(bob);
        strike.approve(address(manager), type(uint256).max);

        vm.startPrank(admin);
        strike.approve(address(creditReserve), type(uint256).max);
        creditReserve.fundEvent(EVENT_ID, 10_000e18);
        vm.stopPrank();
    }

    function _flatConfig(uint16 feeBps) internal view returns (ParimutuelMarketConfig memory config) {
        config = ParimutuelMarketConfig({
            tradingCloseTime: uint64(block.timestamp + 1 hours),
            resolutionTime: uint64(block.timestamp + 1 hours),
            outcomeCount: 3,
            resolverType: ParimutuelResolverType.Admin,
            fallbackResolverType: ParimutuelResolverType.Admin,
            curveType: ParimutuelCurveType.Flat,
            curveParam: 0,
            feeBps: feeBps,
            metadataHash: keccak256("strike-flat-market"),
            metadataURI: "ipfs://strike/strike-pool/flat",
            resolverConfig: bytes("")
        });
    }

    function _createMarket() internal returns (uint256 marketId) {
        vm.prank(creator);
        marketId = factory.createMarket(_flatConfig(0));
    }

    function _buy(uint256 marketId, address user, uint8 outcomeId, uint256 amount) internal {
        ParimutuelBuyParam[] memory buys = new ParimutuelBuyParam[](1);
        buys[0] = ParimutuelBuyParam({outcomeId: outcomeId, amountIn: amount});
        vm.prank(user);
        manager.buyMany(marketId, buys, amount);
    }

    function _buyWithCredit(uint256 marketId, address user, uint8 outcomeId, uint256 amount) internal {
        ParimutuelBuyParam[] memory buys = new ParimutuelBuyParam[](1);
        buys[0] = ParimutuelBuyParam({outcomeId: outcomeId, amountIn: amount});
        vm.prank(user);
        manager.buyWithCredit(EVENT_ID, marketId, buys, amount);
    }

    function _assignAndClaim(address user, bytes32 grantId, uint256 amount) internal {
        vm.prank(admin);
        creditReserve.assignCredit(EVENT_ID, user, amount, amount);

        uint256 claimStart = block.timestamp;
        uint256 claimEnd = block.timestamp + 1 days;
        bytes32 digest = creditReserve.getGrantDigest(EVENT_ID, user, grantId, amount, amount, claimStart, claimEnd);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);

        vm.prank(user);
        creditReserve.claimCredit(EVENT_ID, grantId, amount, amount, claimStart, claimEnd, abi.encodePacked(r, s, v));
    }

    function _resolveWinner(uint256 marketId, uint8 winningOutcomeId) internal {
        vm.warp(block.timestamp + 1 hours);
        factory.closeMarket(marketId);
        vm.prank(admin);
        factory.resolveToWinner(marketId, winningOutcomeId);
    }

    function _finalizeEvent() internal {
        vm.prank(admin);
        creditReserve.endEvent(EVENT_ID);
        vm.prank(admin);
        creditReserve.finalizeEvent(EVENT_ID);
    }

    function test_AdminAssignsAndUserClaimsBeforeClaimEnd() public {
        _assignAndClaim(alice, keccak256("grant-1"), 1_000e18);

        StrikeCreditReserve.UserEventCredit memory credit = creditReserve.getUserCredit(EVENT_ID, alice);
        assertEq(credit.assignedBaseline, 1_000e18);
        assertEq(credit.claimableCredit, 0);
        assertEq(credit.freeCredit, 1_000e18);
        assertEq(creditReserve.totalFreeCredit(), 1_000e18);
    }

    function test_ClaimBlockedAfterClaimEndAndEventEnd() public {
        vm.prank(admin);
        creditReserve.assignCredit(EVENT_ID, alice, 100e18, 100e18);

        uint256 claimStart = block.timestamp;
        uint256 claimEnd = block.timestamp + 1 days;
        bytes32 grantId = keccak256("late-grant");
        bytes32 digest = creditReserve.getGrantDigest(EVENT_ID, alice, grantId, 100e18, 100e18, claimStart, claimEnd);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.warp(claimEnd + 1);
        vm.expectRevert();
        vm.prank(alice);
        creditReserve.claimCredit(EVENT_ID, grantId, 100e18, 100e18, claimStart, claimEnd, sig);

        uint256 secondEventId = EVENT_ID + 1;
        vm.startPrank(admin);
        creditReserve.createEvent(secondEventId, uint64(block.timestamp), uint64(block.timestamp + 1 days));
        creditReserve.assignCredit(secondEventId, alice, 100e18, 100e18);
        creditReserve.endEvent(secondEventId);
        vm.stopPrank();

        bytes32 endedGrant = keccak256("ended-grant");
        digest = creditReserve.getGrantDigest(secondEventId, alice, endedGrant, 100e18, 100e18, block.timestamp, block.timestamp + 1 days);
        (v, r, s) = vm.sign(signerKey, digest);
        vm.expectRevert("StrikeCreditReserve: event ended");
        vm.prank(alice);
        creditReserve.claimCredit(
            secondEventId, endedGrant, 100e18, 100e18, block.timestamp, block.timestamp + 1 days, abi.encodePacked(r, s, v)
        );
    }

    function test_AdminCanAdjustBeforeRedemptionIncludingAfterEnd() public {
        _assignAndClaim(alice, keccak256("grant-2"), 1_000e18);

        vm.prank(admin);
        creditReserve.adjustUserCredit(EVENT_ID, alice, 700e18, 1_200e18, 0);
        StrikeCreditReserve.UserEventCredit memory credit = creditReserve.getUserCredit(EVENT_ID, alice);
        assertEq(credit.assignedBaseline, 700e18);
        assertEq(credit.freeCredit, 1_200e18);

        vm.prank(admin);
        creditReserve.endEvent(EVENT_ID);
        vm.prank(admin);
        creditReserve.adjustUserCredit(EVENT_ID, alice, 800e18, 1_300e18, 0);

        credit = creditReserve.getUserCredit(EVENT_ID, alice);
        assertEq(credit.assignedBaseline, 800e18);
        assertEq(credit.freeCredit, 1_300e18);
    }

    function test_CreditFundedWinIncreasesEventCreditNotStrikeBalance() public {
        uint256 marketId = _createMarket();
        _assignAndClaim(alice, keccak256("grant-3"), 1_000e18);
        _buyWithCredit(marketId, alice, 1, 500e18);
        _buy(marketId, bob, 0, 500e18);
        _resolveWinner(marketId, 1);

        uint256 aliceStrikeBefore = strike.balanceOf(alice);
        vm.prank(alice);
        uint256 userPayout = redemption.claim(marketId);

        assertEq(userPayout, 0);
        assertEq(strike.balanceOf(alice), aliceStrikeBefore);
        StrikeCreditReserve.UserEventCredit memory credit = creditReserve.getUserCredit(EVENT_ID, alice);
        assertEq(credit.freeCredit, 1_500e18);
        assertEq(credit.lockedCredit, 0);
    }

    function test_OnlyCreditAboveBaselineRedeemableAfterFinalization() public {
        uint256 marketId = _createMarket();
        _assignAndClaim(alice, keccak256("grant-4"), 1_000e18);
        _buyWithCredit(marketId, alice, 1, 500e18);
        _buy(marketId, bob, 0, 500e18);
        _resolveWinner(marketId, 1);

        vm.prank(alice);
        redemption.claim(marketId);
        manager.clearCreditMarket(marketId);
        _finalizeEvent();

        assertEq(creditReserve.redeemableCredit(EVENT_ID, alice), 500e18);
        uint256 aliceBefore = strike.balanceOf(alice);
        vm.prank(alice);
        uint256 redeemed = creditReserve.redeemExcessCredit(EVENT_ID);

        assertEq(redeemed, 500e18);
        assertEq(strike.balanceOf(alice), aliceBefore + 500e18);
        assertEq(creditReserve.redeemableCredit(EVENT_ID, alice), 0);
    }

    function test_RedemptionBlockedBeforeEventFinalization() public {
        _assignAndClaim(alice, keccak256("grant-5"), 1_000e18);
        vm.prank(admin);
        creditReserve.adjustUserCredit(EVENT_ID, alice, 500e18, 1_000e18, 0);

        vm.expectRevert("StrikeCreditReserve: event not finalized");
        vm.prank(alice);
        creditReserve.redeemExcessCredit(EVENT_ID);
    }

    function test_FinalizationBlockedWhileCreditMarketUnresolved() public {
        uint256 marketId = _createMarket();
        _assignAndClaim(alice, keccak256("grant-6"), 1_000e18);
        _buyWithCredit(marketId, alice, 1, 100e18);

        vm.prank(admin);
        creditReserve.endEvent(EVENT_ID);
        vm.expectRevert("StrikeCreditReserve: active credit markets");
        vm.prank(admin);
        creditReserve.finalizeEvent(EVENT_ID);

        vm.expectRevert("StrikePoolManager: market unresolved");
        manager.clearCreditMarket(marketId);

        _resolveWinner(marketId, 1);
        manager.clearCreditMarket(marketId);
        vm.prank(admin);
        creditReserve.finalizeEvent(EVENT_ID);
    }

    function test_LosingCreditPositionCanSettleLockedCreditAfterResolution() public {
        uint256 marketId = _createMarket();
        _assignAndClaim(alice, keccak256("grant-losing-credit"), 1_000e18);
        _buyWithCredit(marketId, alice, 1, 500e18);
        _buy(marketId, bob, 0, 500e18);
        _resolveWinner(marketId, 0);

        StrikeCreditReserve.UserEventCredit memory credit = creditReserve.getUserCredit(EVENT_ID, alice);
        assertEq(credit.freeCredit, 500e18);
        assertEq(credit.lockedCredit, 500e18);

        vm.prank(alice);
        uint256 payout = redemption.claim(marketId);

        assertEq(payout, 0);
        credit = creditReserve.getUserCredit(EVENT_ID, alice);
        assertEq(credit.freeCredit, 500e18);
        assertEq(credit.lockedCredit, 0);
    }

    function test_WinningCreditClaimConsumesLosingCreditExposureToo() public {
        uint256 marketId = _createMarket();
        _assignAndClaim(alice, keccak256("grant-multi-credit"), 1_000e18);
        _buyWithCredit(marketId, alice, 1, 300e18);
        _buyWithCredit(marketId, alice, 2, 200e18);
        _buy(marketId, bob, 0, 500e18);
        _resolveWinner(marketId, 1);

        vm.prank(alice);
        redemption.claim(marketId);

        StrikeCreditReserve.UserEventCredit memory credit = creditReserve.getUserCredit(EVENT_ID, alice);
        assertEq(credit.lockedCredit, 0);
        assertEq(credit.freeCredit, 1_500e18);
    }

    function test_MixedRealAndCreditSameUserMarketIsBlockedForMvp() public {
        uint256 realFirstMarketId = _createMarket();
        _assignAndClaim(alice, keccak256("grant-7"), 1_000e18);
        _buy(realFirstMarketId, alice, 1, 100e18);

        ParimutuelBuyParam[] memory buys = new ParimutuelBuyParam[](1);
        buys[0] = ParimutuelBuyParam({outcomeId: 2, amountIn: 100e18});

        vm.expectRevert("StrikePoolManager: mixed funding blocked");
        vm.prank(alice);
        manager.buyWithCredit(EVENT_ID, realFirstMarketId, buys, 100e18);

        uint256 creditFirstMarketId = _createMarket();
        _buyWithCredit(creditFirstMarketId, alice, 0, 100e18);

        buys[0] = ParimutuelBuyParam({outcomeId: 1, amountIn: 100e18});
        vm.expectRevert("StrikePoolManager: mixed funding blocked");
        vm.prank(alice);
        manager.buyMany(creditFirstMarketId, buys, 100e18);
    }

    function test_RealStrikeBuyClaimAndInvalidRefundStillWork() public {
        uint256 claimMarketId = _createMarket();
        _buy(claimMarketId, alice, 1, 100e18);
        _buy(claimMarketId, bob, 0, 100e18);
        _resolveWinner(claimMarketId, 1);

        uint256 aliceBefore = strike.balanceOf(alice);
        vm.prank(alice);
        uint256 payout = redemption.claim(claimMarketId);

        assertEq(payout, 200e18);
        assertEq(strike.balanceOf(alice), aliceBefore + 200e18);
        assertEq(manager.marketTotalPrincipal(claimMarketId), 0);

        uint256 refundMarketId = _createMarket();
        _buy(refundMarketId, alice, 2, 25e18);

        vm.prank(admin);
        factory.cancelMarket(refundMarketId);

        uint8[] memory outcomes = new uint8[](1);
        outcomes[0] = 2;

        uint256 refundBefore = strike.balanceOf(alice);
        vm.prank(alice);
        uint256 refund = redemption.refund(refundMarketId, outcomes);

        assertEq(refund, 25e18);
        assertEq(strike.balanceOf(alice), refundBefore + 25e18);
        assertEq(manager.marketTotalPrincipal(refundMarketId), 0);
    }
}
