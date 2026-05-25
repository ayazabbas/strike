// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/USDTCreditReserve.sol";
import "./mocks/MockUSDT.sol";

contract USDTCreditReserveTest is Test {
    USDTCreditReserve public reserve;
    MockUSDT public usdt;

    uint256 internal constant EVENT_ID = 202606;
    uint256 internal constant SECOND_EVENT_ID = 202607;
    uint256 internal signerKey = 0xA11CE;
    uint256 internal badSignerKey = 0xB0B;

    address public signer;
    address public admin = address(0x1);
    address public alice = address(0x2);
    address public bob = address(0x3);
    address public market = address(0x4);
    address public unauthorizedMarket = address(0x5);
    address public vault = address(0x6);

    function setUp() public {
        signer = vm.addr(signerKey);

        usdt = new MockUSDT();
        reserve = new USDTCreditReserve(admin, address(usdt));

        vm.startPrank(admin);
        reserve.grantRole(reserve.CREDIT_SIGNER_ROLE(), signer);
        reserve.createEvent(
            EVENT_ID, uint64(block.timestamp), uint64(block.timestamp + 2 days), uint64(block.timestamp + 7 days)
        );
        reserve.setAuthorizedMarket(EVENT_ID, market, true);
        vm.stopPrank();

        usdt.mint(admin, 1_000_000e18);
        vm.startPrank(admin);
        usdt.approve(address(reserve), type(uint256).max);
        reserve.fundEvent(EVENT_ID, 10_000e18);
        vm.stopPrank();
    }

    function _signature(address user, uint256 amount, uint64 claimStart, uint64 claimEnd, uint256 nonce, uint256 key)
        internal
        view
        returns (bytes memory)
    {
        return _signatureForEvent(EVENT_ID, user, amount, claimStart, claimEnd, nonce, key);
    }

    function _signatureForEvent(
        uint256 eventId,
        address user,
        uint256 amount,
        uint64 claimStart,
        uint64 claimEnd,
        uint256 nonce,
        uint256 key
    ) internal view returns (bytes memory) {
        bytes32 digest = reserve.getGrantDigest(eventId, user, amount, claimStart, claimEnd, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function _claim(address user, uint256 amount) internal {
        uint64 claimStart = uint64(block.timestamp);
        uint64 claimEnd = uint64(block.timestamp + 1 days);
        bytes memory sig =
            _signature(user, amount, claimStart, claimEnd, reserve.getAccount(EVENT_ID, user).nonce, signerKey);

        vm.prank(user);
        reserve.claimCredit(EVENT_ID, amount, claimStart, claimEnd, sig);
    }

    function _claimForEvent(uint256 eventId, address user, uint256 amount) internal {
        uint64 claimStart = uint64(block.timestamp);
        uint64 claimEnd = uint64(block.timestamp + 1 days);
        bytes memory sig = _signatureForEvent(
            eventId, user, amount, claimStart, claimEnd, reserve.getAccount(eventId, user).nonce, signerKey
        );

        vm.prank(user);
        reserve.claimCredit(eventId, amount, claimStart, claimEnd, sig);
    }

    function test_CreateFundAndClaimWithValidSignature() public {
        _claim(alice, 1_000e18);

        USDTCreditReserve.CreditAccount memory account = reserve.getAccount(EVENT_ID, alice);
        assertEq(account.assignedBaseline, 1_000e18);
        assertEq(account.freeCredit, 1_000e18);
        assertEq(account.lockedCredit, 0);
        assertEq(account.nonce, 1);

        (,,,,, uint256 fundedUsdt, uint256 assignedTotal, uint256 freeTotal,,,,,, uint256 marketWithdrawnTotal) =
            reserve.creditEvents(EVENT_ID);
        assertEq(fundedUsdt, 10_000e18);
        assertEq(assignedTotal, 1_000e18);
        assertEq(freeTotal, 1_000e18);
        assertEq(marketWithdrawnTotal, 0);
    }

    function test_ClaimRejectsReplayBadSignerAndOutsideWindow() public {
        uint64 claimStart = uint64(block.timestamp);
        uint64 claimEnd = uint64(block.timestamp + 1 days);
        bytes memory sig = _signature(alice, 100e18, claimStart, claimEnd, 0, signerKey);

        vm.prank(alice);
        reserve.claimCredit(EVENT_ID, 100e18, claimStart, claimEnd, sig);

        vm.expectRevert(USDTCreditReserve.InvalidSignature.selector);
        vm.prank(alice);
        reserve.claimCredit(EVENT_ID, 100e18, claimStart, claimEnd, sig);

        bytes memory badSig = _signature(bob, 100e18, claimStart, claimEnd, 0, badSignerKey);
        vm.expectRevert(USDTCreditReserve.InvalidSignature.selector);
        vm.prank(bob);
        reserve.claimCredit(EVENT_ID, 100e18, claimStart, claimEnd, badSig);

        uint64 lateStart = uint64(block.timestamp + 1 hours);
        uint64 lateEnd = uint64(block.timestamp + 2 hours);
        bytes memory lateSig = _signature(bob, 100e18, lateStart, lateEnd, 0, signerKey);
        vm.expectRevert(USDTCreditReserve.GrantInactive.selector);
        vm.prank(bob);
        reserve.claimCredit(EVENT_ID, 100e18, lateStart, lateEnd, lateSig);

        vm.warp(block.timestamp + 3 days);
        uint64 staleStart = uint64(block.timestamp - 1 days);
        uint64 staleEnd = uint64(block.timestamp + 1 days);
        bytes memory staleSig = _signature(bob, 100e18, staleStart, staleEnd, 0, signerKey);
        vm.expectRevert(USDTCreditReserve.ClaimClosed.selector);
        vm.prank(bob);
        reserve.claimCredit(EVENT_ID, 100e18, staleStart, staleEnd, staleSig);
    }

    function test_AuthorizedMarketCanLockAndReturnCredit() public {
        _claim(alice, 1_000e18);

        vm.prank(market);
        reserve.lockCredit(EVENT_ID, alice, 400e18);

        USDTCreditReserve.CreditAccount memory account = reserve.getAccount(EVENT_ID, alice);
        assertEq(account.freeCredit, 600e18);
        assertEq(account.lockedCredit, 400e18);

        vm.prank(market);
        reserve.returnLockedCredit(EVENT_ID, alice, 150e18);

        account = reserve.getAccount(EVENT_ID, alice);
        assertEq(account.freeCredit, 750e18);
        assertEq(account.lockedCredit, 250e18);
    }

    function test_AuthorizedMarketCanSettleWinningCreditPayout() public {
        _claim(alice, 1_000e18);

        vm.prank(market);
        reserve.lockCredit(EVENT_ID, alice, 500e18);

        vm.prank(market);
        reserve.settleCreditPayout(EVENT_ID, alice, 500e18, 1_500e18);

        USDTCreditReserve.CreditAccount memory account = reserve.getAccount(EVENT_ID, alice);
        assertEq(account.assignedBaseline, 1_000e18);
        assertEq(account.freeCredit, 2_000e18);
        assertEq(account.lockedCredit, 0);
        assertEq(reserve.redeemableCredit(EVENT_ID, alice), 1_000e18);

        (
            ,,,,,,,,,,
            uint256 authorizedMarketCount,
            uint256 settledConsumedTotal,
            uint256 settledPayoutTotal,
            uint256 marketWithdrawnTotal
        ) = reserve.creditEvents(EVENT_ID);
        assertEq(authorizedMarketCount, 1);
        assertEq(settledConsumedTotal, 500e18);
        assertEq(settledPayoutTotal, 1_500e18);
        assertEq(marketWithdrawnTotal, 0);
    }

    function test_AuthorizedMarketCanSettleCreditPayoutAndWithdrawConsumedBacking() public {
        _claim(alice, 1_000e18);

        vm.prank(market);
        reserve.lockCredit(EVENT_ID, alice, 600e18);

        uint256 reserveBefore = usdt.balanceOf(address(reserve));

        vm.prank(market);
        reserve.settleCreditPayoutAndWithdraw(EVENT_ID, alice, 600e18, 200e18, vault, 400e18);

        USDTCreditReserve.CreditAccount memory account = reserve.getAccount(EVENT_ID, alice);
        assertEq(account.freeCredit, 600e18);
        assertEq(account.lockedCredit, 0);
        assertEq(usdt.balanceOf(vault), 400e18);
        assertEq(usdt.balanceOf(address(reserve)), reserveBefore - 400e18);

        (
            ,,,,,,,
            uint256 freeTotal,
            uint256 lockedTotal,,,
            uint256 settledConsumedTotal,
            uint256 settledPayoutTotal,
            uint256 marketWithdrawnTotal
        ) = reserve.creditEvents(EVENT_ID);
        assertEq(freeTotal, 600e18);
        assertEq(lockedTotal, 0);
        assertEq(settledConsumedTotal, 600e18);
        assertEq(settledPayoutTotal, 200e18);
        assertEq(marketWithdrawnTotal, 400e18);
        assertGe(usdt.balanceOf(address(reserve)), freeTotal + lockedTotal);
    }

    function test_AuthorizedMarketCannotFundSettlementWithoutIncrementalTransfer() public {
        assertEq(usdt.balanceOf(address(reserve)), 10_000e18);
        assertEq(reserve.lastObservedUsdtBalance(), 10_000e18);

        vm.expectRevert(USDTCreditReserve.InsufficientBacking.selector);
        vm.prank(market);
        reserve.fundFromMarketSettlement(EVENT_ID, 1_000e18);

        (,,,,, uint256 fundedUsdt,,,,,,,,) = reserve.creditEvents(EVENT_ID);
        assertEq(fundedUsdt, 10_000e18);
        assertEq(usdt.balanceOf(address(reserve)), 10_000e18);
        assertEq(reserve.lastObservedUsdtBalance(), 10_000e18);
    }

    function test_AuthorizedMarketCanFundSettlementAfterTransfer() public {
        usdt.mint(market, 1_000e18);

        vm.startPrank(market);
        usdt.transfer(address(reserve), 1_000e18);
        reserve.fundFromMarketSettlement(EVENT_ID, 1_000e18);
        vm.stopPrank();

        (,,,,, uint256 fundedUsdt,,,,,,,,) = reserve.creditEvents(EVENT_ID);
        assertEq(fundedUsdt, 11_000e18);
        assertEq(usdt.balanceOf(address(reserve)), 11_000e18);
        assertEq(reserve.lastObservedUsdtBalance(), 11_000e18);
    }

    function test_CannotWithdrawMoreThanConsumedLockedCredit() public {
        _claim(alice, 100e18);

        vm.prank(market);
        reserve.lockCredit(EVENT_ID, alice, 100e18);

        vm.expectRevert(USDTCreditReserve.WithdrawExceedsConsumedCredit.selector);
        vm.prank(market);
        reserve.settleCreditPayoutAndWithdraw(EVENT_ID, alice, 50e18, 0, vault, 51e18);
    }

    function test_UnauthorizedMarketCannotWithdrawConsumedBacking() public {
        _claim(alice, 100e18);

        vm.prank(market);
        reserve.lockCredit(EVENT_ID, alice, 100e18);

        vm.expectRevert(USDTCreditReserve.UnauthorizedMarket.selector);
        vm.prank(unauthorizedMarket);
        reserve.settleCreditPayoutAndWithdraw(EVENT_ID, alice, 100e18, 0, vault, 100e18);
    }

    function test_FinalizationAndRedeemOnlyExcessAboveBaseline() public {
        _claim(alice, 1_000e18);

        vm.startPrank(market);
        reserve.lockCredit(EVENT_ID, alice, 500e18);
        reserve.settleCreditPayout(EVENT_ID, alice, 500e18, 1_500e18);
        vm.stopPrank();

        vm.warp(block.timestamp + 7 days);
        vm.prank(admin);
        reserve.setAuthorizedMarket(EVENT_ID, market, false);
        vm.prank(admin);
        reserve.finalizeEvent(EVENT_ID);

        assertEq(reserve.redeemableCredit(EVENT_ID, alice), 1_000e18);
        uint256 aliceBefore = usdt.balanceOf(alice);
        vm.prank(alice);
        uint256 redeemed = reserve.redeemExcessCredit(EVENT_ID);

        assertEq(redeemed, 1_000e18);
        assertEq(usdt.balanceOf(alice), aliceBefore + 1_000e18);

        USDTCreditReserve.CreditAccount memory account = reserve.getAccount(EVENT_ID, alice);
        assertEq(account.freeCredit, 1_000e18);
        assertEq(account.assignedBaseline, 1_000e18);
        assertEq(account.redeemedExcess, 1_000e18);
        assertEq(reserve.redeemableCredit(EVENT_ID, alice), 0);

        vm.expectRevert(USDTCreditReserve.NothingRedeemable.selector);
        vm.prank(alice);
        reserve.redeemExcessCredit(EVENT_ID);
    }

    function test_RejectsUnauthorizedMarketCallsAndOverLockOrOverRedeem() public {
        _claim(alice, 100e18);

        vm.expectRevert(USDTCreditReserve.UnauthorizedMarket.selector);
        vm.prank(unauthorizedMarket);
        reserve.lockCredit(EVENT_ID, alice, 1e18);

        vm.expectRevert(USDTCreditReserve.InsufficientCredit.selector);
        vm.prank(market);
        reserve.lockCredit(EVENT_ID, alice, 101e18);

        vm.prank(market);
        reserve.lockCredit(EVENT_ID, alice, 100e18);

        vm.expectRevert(USDTCreditReserve.InsufficientLockedCredit.selector);
        vm.prank(market);
        reserve.returnLockedCredit(EVENT_ID, alice, 101e18);

        vm.expectRevert(USDTCreditReserve.InvalidWindow.selector);
        vm.warp(block.timestamp + 7 days);
        vm.prank(admin);
        reserve.finalizeEvent(EVENT_ID);
    }

    function test_FinalizationRequiresNoAuthorizedMarkets() public {
        vm.warp(block.timestamp + 7 days);

        vm.expectRevert(USDTCreditReserve.ActiveAuthorizedMarkets.selector);
        vm.prank(admin);
        reserve.finalizeEvent(EVENT_ID);

        vm.prank(admin);
        reserve.setAuthorizedMarket(EVENT_ID, market, false);

        vm.prank(admin);
        reserve.finalizeEvent(EVENT_ID);
    }

    function test_MarketAuthorizationIsEventScopedWithoutGlobalRoleSideEffects() public {
        vm.startPrank(admin);
        reserve.createEvent(
            SECOND_EVENT_ID, uint64(block.timestamp), uint64(block.timestamp + 2 days), uint64(block.timestamp + 7 days)
        );
        reserve.fundEvent(SECOND_EVENT_ID, 1_000e18);
        reserve.setAuthorizedMarket(SECOND_EVENT_ID, market, true);
        reserve.setAuthorizedMarket(EVENT_ID, market, false);
        vm.stopPrank();

        assertFalse(reserve.authorizedMarkets(EVENT_ID, market));
        assertTrue(reserve.authorizedMarkets(SECOND_EVENT_ID, market));
        assertFalse(reserve.hasRole(keccak256("MARKET_ROLE"), market));

        _claimForEvent(SECOND_EVENT_ID, bob, 100e18);

        vm.expectRevert(USDTCreditReserve.UnauthorizedMarket.selector);
        vm.prank(market);
        reserve.lockCredit(EVENT_ID, bob, 1e18);

        vm.prank(market);
        reserve.lockCredit(SECOND_EVENT_ID, bob, 25e18);

        USDTCreditReserve.CreditAccount memory account = reserve.getAccount(SECOND_EVENT_ID, bob);
        assertEq(account.freeCredit, 75e18);
        assertEq(account.lockedCredit, 25e18);
    }

    function test_RejectsUnbackedClaimOrSettlementAndPreservesSolvencyTotals() public {
        _claim(alice, 10_000e18);

        uint64 claimStart = uint64(block.timestamp);
        uint64 claimEnd = uint64(block.timestamp + 1 days);
        bytes memory sig =
            _signature(bob, 1e18, claimStart, claimEnd, reserve.getAccount(EVENT_ID, bob).nonce, signerKey);

        vm.expectRevert(USDTCreditReserve.InsufficientBacking.selector);
        vm.prank(bob);
        reserve.claimCredit(EVENT_ID, 1e18, claimStart, claimEnd, sig);

        vm.prank(market);
        reserve.lockCredit(EVENT_ID, alice, 10_000e18);

        vm.expectRevert(USDTCreditReserve.InsufficientBacking.selector);
        vm.prank(market);
        reserve.settleCreditPayout(EVENT_ID, alice, 10_000e18, 10_001e18);

        vm.prank(market);
        reserve.settleCreditPayout(EVENT_ID, alice, 10_000e18, 10_000e18);

        vm.warp(block.timestamp + 7 days);
        vm.prank(admin);
        reserve.setAuthorizedMarket(EVENT_ID, market, false);
        vm.prank(admin);
        reserve.finalizeEvent(EVENT_ID);

        (
            ,,,,,
            uint256 fundedUsdt,,
            uint256 freeTotal,
            uint256 lockedTotal,
            uint256 redeemedTotal,,,,
            uint256 marketWithdrawnTotal
        ) = reserve.creditEvents(EVENT_ID);
        assertEq(freeTotal + lockedTotal + redeemedTotal + marketWithdrawnTotal, fundedUsdt);
        assertEq(usdt.balanceOf(address(reserve)), freeTotal + lockedTotal);
    }

    function test_FinalSolvencyTotalsIncludeMarketWithdrawalsAndOutstandingCreditBacked() public {
        _claim(alice, 10_000e18);

        vm.prank(market);
        reserve.lockCredit(EVENT_ID, alice, 10_000e18);

        uint256 reserveBefore = usdt.balanceOf(address(reserve));
        vm.prank(market);
        reserve.settleCreditPayoutAndWithdraw(EVENT_ID, alice, 10_000e18, 6_000e18, vault, 4_000e18);

        vm.warp(block.timestamp + 7 days);
        vm.prank(admin);
        reserve.setAuthorizedMarket(EVENT_ID, market, false);
        vm.prank(admin);
        reserve.finalizeEvent(EVENT_ID);

        (
            ,,,,,
            uint256 fundedUsdt,,
            uint256 freeTotal,
            uint256 lockedTotal,
            uint256 redeemedTotal,,,,
            uint256 marketWithdrawnTotal
        ) = reserve.creditEvents(EVENT_ID);
        assertEq(freeTotal, 6_000e18);
        assertEq(lockedTotal, 0);
        assertEq(marketWithdrawnTotal, 4_000e18);
        assertEq(freeTotal + lockedTotal + redeemedTotal + marketWithdrawnTotal, fundedUsdt);
        assertEq(usdt.balanceOf(vault), 4_000e18);
        assertEq(usdt.balanceOf(address(reserve)), reserveBefore - 4_000e18);
        assertEq(usdt.balanceOf(address(reserve)), freeTotal + lockedTotal);
    }

    function test_GrantCannotReplayAcrossReserveAddress() public {
        USDTCreditReserve secondReserve = new USDTCreditReserve(admin, address(usdt));

        vm.startPrank(admin);
        usdt.approve(address(secondReserve), type(uint256).max);
        secondReserve.grantRole(secondReserve.CREDIT_SIGNER_ROLE(), signer);
        secondReserve.createEvent(
            EVENT_ID, uint64(block.timestamp), uint64(block.timestamp + 2 days), uint64(block.timestamp + 7 days)
        );
        secondReserve.fundEvent(EVENT_ID, 100e18);
        vm.stopPrank();

        uint64 claimStart = uint64(block.timestamp);
        uint64 claimEnd = uint64(block.timestamp + 1 days);
        bytes memory sig = _signature(alice, 100e18, claimStart, claimEnd, 0, signerKey);

        vm.expectRevert(USDTCreditReserve.InvalidSignature.selector);
        vm.prank(alice);
        secondReserve.claimCredit(EVENT_ID, 100e18, claimStart, claimEnd, sig);
    }
}
