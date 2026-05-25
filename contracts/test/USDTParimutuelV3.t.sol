// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/USDTCreditReserve.sol";
import "../src/USDTParimutuelV3Factory.sol";
import "../src/USDTParimutuelV3Manager.sol";
import "../src/USDTParimutuelV3Redemption.sol";
import "../src/USDTParimutuelV3Vault.sol";
import "./mocks/MockUSDT.sol";

contract USDTParimutuelV3Test is Test {
    uint256 internal constant EVENT_ID = 202606;
    uint256 internal signerKey = 0xA11CE;

    address internal admin = address(0x1);
    address internal feeRecipient = address(0x9);
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal charlie = address(0xCAFE);

    MockUSDT internal usdt;
    USDTCreditReserve internal reserve;
    USDTParimutuelV3Factory internal factory;
    USDTParimutuelV3Vault internal vault;
    USDTParimutuelV3Manager internal manager;
    USDTParimutuelV3Redemption internal redemption;

    function setUp() public {
        usdt = new MockUSDT();
        reserve = new USDTCreditReserve(admin, address(usdt));
        factory = new USDTParimutuelV3Factory(admin);
        vault = new USDTParimutuelV3Vault(admin, address(usdt));
        manager = new USDTParimutuelV3Manager(admin, address(factory), address(vault), address(reserve), feeRecipient);
        redemption = new USDTParimutuelV3Redemption(admin, address(manager), address(vault));

        vm.startPrank(admin);
        factory.setManager(address(manager));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(manager));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(redemption));
        manager.grantRole(manager.REDEMPTION_ROLE(), address(redemption));
        reserve.grantRole(reserve.CREDIT_SIGNER_ROLE(), vm.addr(signerKey));
        reserve.createEvent(
            EVENT_ID, uint64(block.timestamp), uint64(block.timestamp + 2 days), uint64(block.timestamp + 10 days)
        );
        reserve.setAuthorizedMarket(EVENT_ID, address(manager), true);
        vm.stopPrank();

        usdt.mint(admin, 1_000_000e18);
        vm.startPrank(admin);
        usdt.approve(address(reserve), type(uint256).max);
        reserve.fundEvent(EVENT_ID, 10_000e18);
        vm.stopPrank();

        usdt.mint(alice, 1_000e18);
        usdt.mint(bob, 1_000e18);
        usdt.mint(charlie, 1_000e18);
        vm.prank(alice);
        usdt.approve(address(manager), type(uint256).max);
        vm.prank(bob);
        usdt.approve(address(manager), type(uint256).max);
        vm.prank(charlie);
        usdt.approve(address(manager), type(uint256).max);
    }

    function test_CreateMarketBuyRealUsdtAndBuyCredit() public {
        _claimCredit(bob, 250e18);
        uint256 marketId = _createMarket(true);

        vm.prank(alice);
        uint256 realShares = manager.buyWithUsdt(marketId, 0, 100e18, 100e18);
        vm.prank(bob);
        uint256 creditShares = manager.buyWithCredit(marketId, 1, 200e18, 200e18);

        assertEq(realShares, 100e18);
        assertEq(creditShares, 200e18);
        assertEq(usdt.balanceOf(address(vault)), 100e18);

        USDTParimutuelV3Position memory realPosition = manager.getUserRealPosition(marketId, alice, 0);
        USDTParimutuelV3Position memory creditPosition = manager.getUserCreditPosition(marketId, bob, 1);
        assertEq(realPosition.principal, 100e18);
        assertEq(creditPosition.principal, 200e18);
        assertEq(reserve.creditBalance(EVENT_ID, bob), 50e18);
        assertEq(reserve.lockedCreditBalance(EVENT_ID, bob), 200e18);
    }

    function test_MixedSettlementCreditLoserFundsRealWinner() public {
        _claimCredit(bob, 100e18);
        uint256 marketId = _createMarket(true);

        vm.prank(alice);
        manager.buyWithUsdt(marketId, 0, 100e18, 0);
        vm.prank(bob);
        manager.buyWithCredit(marketId, 1, 100e18, 0);

        _resolve(marketId, 0);

        address[] memory creditUsers = new address[](1);
        creditUsers[0] = bob;
        uint256 aliceBefore = usdt.balanceOf(alice);
        vm.prank(alice);
        redemption.claim(marketId, creditUsers);

        assertEq(usdt.balanceOf(alice), aliceBefore + 200e18);
        assertEq(usdt.balanceOf(address(vault)), 0);
        assertEq(reserve.creditBalance(EVENT_ID, bob), 0);
        assertEq(reserve.lockedCreditBalance(EVENT_ID, bob), 0);
    }

    function test_CreditWinnerReceivesReserveCreditNotUsdtTransfer() public {
        _claimCredit(alice, 100e18);
        uint256 marketId = _createMarket(true);

        vm.prank(alice);
        manager.buyWithCredit(marketId, 0, 100e18, 0);
        vm.prank(bob);
        manager.buyWithUsdt(marketId, 1, 100e18, 0);

        _resolve(marketId, 0);

        uint256 aliceUsdtBefore = usdt.balanceOf(alice);
        vm.prank(alice);
        redemption.claim(marketId, new address[](0));

        assertEq(usdt.balanceOf(alice), aliceUsdtBefore);
        assertEq(reserve.creditBalance(EVENT_ID, alice), 200e18);
        assertEq(reserve.lockedCreditBalance(EVENT_ID, alice), 0);
        assertEq(usdt.balanceOf(address(vault)), 0);
    }

    function test_InvalidRefundReturnsRealUsdtAndLockedCredit() public {
        _claimCredit(bob, 100e18);
        uint256 marketId = _createMarket(true);

        vm.prank(alice);
        manager.buyWithUsdt(marketId, 0, 100e18, 0);
        vm.prank(bob);
        manager.buyWithCredit(marketId, 1, 100e18, 0);

        vm.warp(block.timestamp + 2 days);
        vm.prank(admin);
        factory.resolveInvalid(marketId);

        uint8[] memory aliceOutcomes = new uint8[](1);
        aliceOutcomes[0] = 0;
        uint8[] memory bobOutcomes = new uint8[](1);
        bobOutcomes[0] = 1;

        uint256 aliceBefore = usdt.balanceOf(alice);
        vm.prank(alice);
        redemption.refund(marketId, aliceOutcomes);
        vm.prank(bob);
        redemption.refund(marketId, bobOutcomes);

        assertEq(usdt.balanceOf(alice), aliceBefore + 100e18);
        assertEq(reserve.creditBalance(EVENT_ID, bob), 100e18);
        assertEq(reserve.lockedCreditBalance(EVENT_ID, bob), 0);
    }

    function test_RejectsBuyAfterTradingCloseAndCreditDisabled() public {
        _claimCredit(bob, 100e18);
        uint256 creditDisabledMarket = _createMarket(false);

        vm.expectRevert(USDTParimutuelV3Manager.CreditDisabled.selector);
        vm.prank(bob);
        manager.buyWithCredit(creditDisabledMarket, 0, 100e18, 0);

        uint256 marketId = _createMarket(true);
        vm.warp(block.timestamp + 1 days + 1);

        vm.expectRevert(USDTParimutuelV3Manager.TradingClosed.selector);
        vm.prank(alice);
        manager.buyWithUsdt(marketId, 0, 100e18, 0);
    }

    function test_DoubleClaimIsRejectedAfterPositionConsumed() public {
        uint256 marketId = _createMarket(true);

        vm.prank(alice);
        manager.buyWithUsdt(marketId, 0, 100e18, 0);
        vm.prank(bob);
        manager.buyWithUsdt(marketId, 1, 100e18, 0);

        _resolve(marketId, 0);

        vm.prank(alice);
        redemption.claim(marketId, new address[](0));

        vm.expectRevert(USDTParimutuelV3Manager.NothingToClaim.selector);
        vm.prank(alice);
        redemption.claim(marketId, new address[](0));
    }

    function test_DoubleRefundIsRejectedAfterPositionConsumed() public {
        uint256 marketId = _createMarket(true);

        vm.prank(alice);
        manager.buyWithUsdt(marketId, 0, 100e18, 0);

        vm.warp(block.timestamp + 2 days);
        vm.prank(admin);
        factory.resolveInvalid(marketId);

        uint8[] memory outcomeIds = new uint8[](1);
        outcomeIds[0] = 0;

        vm.prank(alice);
        redemption.refund(marketId, outcomeIds);

        vm.expectRevert(USDTParimutuelV3Manager.NothingToRefund.selector);
        vm.prank(alice);
        redemption.refund(marketId, outcomeIds);
    }

    function test_MultipleRealWinnersShareLosingPoolAcrossSequentialClaims() public {
        uint256 marketId = _createMarket(true);

        vm.prank(alice);
        manager.buyWithUsdt(marketId, 0, 100e18, 0);
        vm.prank(bob);
        manager.buyWithUsdt(marketId, 0, 100e18, 0);
        vm.prank(charlie);
        manager.buyWithUsdt(marketId, 1, 100e18, 0);

        _resolve(marketId, 0);

        uint256 aliceBefore = usdt.balanceOf(alice);
        uint256 bobBefore = usdt.balanceOf(bob);

        vm.prank(alice);
        redemption.claim(marketId, new address[](0));
        vm.prank(bob);
        redemption.claim(marketId, new address[](0));

        assertEq(usdt.balanceOf(alice), aliceBefore + 150e18);
        assertEq(usdt.balanceOf(bob), bobBefore + 150e18);
        assertEq(usdt.balanceOf(address(vault)), 0);
    }

    function test_MixedRealWinAndCreditLossSameUserSettlesOnce() public {
        _claimCredit(alice, 100e18);
        uint256 marketId = _createMarket(true);

        vm.prank(alice);
        manager.buyWithUsdt(marketId, 0, 100e18, 0);
        vm.prank(alice);
        manager.buyWithCredit(marketId, 1, 100e18, 0);

        _resolve(marketId, 0);

        address[] memory creditUsers = new address[](1);
        creditUsers[0] = alice;
        uint256 aliceBefore = usdt.balanceOf(alice);

        vm.prank(alice);
        redemption.claim(marketId, creditUsers);

        assertEq(usdt.balanceOf(alice), aliceBefore + 200e18);
        assertEq(reserve.creditBalance(EVENT_ID, alice), 0);
        assertEq(reserve.lockedCreditBalance(EVENT_ID, alice), 0);

        vm.expectRevert(USDTParimutuelV3Manager.AlreadySettled.selector);
        vm.prank(alice);
        redemption.claim(marketId, creditUsers);
    }

    function test_MixedWinningRealAndLosingRealClaimCleansAllUserPools() public {
        uint256 marketId = _createMarket(true);

        vm.prank(alice);
        manager.buyWithUsdt(marketId, 0, 100e18, 0);
        vm.prank(alice);
        manager.buyWithUsdt(marketId, 1, 100e18, 0);

        _resolve(marketId, 0);

        uint256 aliceBefore = usdt.balanceOf(alice);
        vm.prank(alice);
        redemption.claim(marketId, new address[](0));

        assertEq(usdt.balanceOf(alice), aliceBefore + 200e18);
        assertEq(manager.marketTotalPrincipal(marketId), 0);

        USDTParimutuelV3Position memory winningPosition = manager.getUserRealPosition(marketId, alice, 0);
        USDTParimutuelV3Position memory losingPosition = manager.getUserRealPosition(marketId, alice, 1);
        assertEq(winningPosition.principal, 0);
        assertEq(winningPosition.rewardShares, 0);
        assertEq(losingPosition.principal, 0);
        assertEq(losingPosition.rewardShares, 0);

        USDTParimutuelV3OutcomePool memory winningPool = manager.getOutcomePool(marketId, 0);
        USDTParimutuelV3OutcomePool memory losingPool = manager.getOutcomePool(marketId, 1);
        assertEq(winningPool.principal, 0);
        assertEq(winningPool.rewardShares, 0);
        assertEq(losingPool.principal, 0);
        assertEq(losingPool.rewardShares, 0);
    }

    function test_MixedWinningRealAndLosingCreditClaimCleansCreditPoolWithoutDoubleSubtractingPot() public {
        _claimCredit(alice, 100e18);
        uint256 marketId = _createMarket(true);

        vm.prank(alice);
        manager.buyWithUsdt(marketId, 0, 100e18, 0);
        vm.prank(bob);
        manager.buyWithUsdt(marketId, 0, 100e18, 0);
        vm.prank(alice);
        manager.buyWithCredit(marketId, 1, 100e18, 0);

        _resolve(marketId, 0);

        address[] memory creditUsers = new address[](1);
        creditUsers[0] = alice;
        uint256 aliceBefore = usdt.balanceOf(alice);
        uint256 bobBefore = usdt.balanceOf(bob);

        vm.prank(alice);
        redemption.claim(marketId, creditUsers);

        assertEq(usdt.balanceOf(alice), aliceBefore + 150e18);
        assertEq(manager.marketTotalPrincipal(marketId), 150e18);

        USDTParimutuelV3Position memory losingCreditPosition = manager.getUserCreditPosition(marketId, alice, 1);
        assertEq(losingCreditPosition.principal, 0);
        assertEq(losingCreditPosition.rewardShares, 0);

        USDTParimutuelV3OutcomePool memory losingPool = manager.getOutcomePool(marketId, 1);
        assertEq(losingPool.principal, 0);
        assertEq(losingPool.rewardShares, 0);
        assertEq(losingPool.creditPrincipal, 0);
        assertEq(losingPool.creditRewardShares, 0);

        vm.prank(bob);
        redemption.claim(marketId, new address[](0));

        assertEq(usdt.balanceOf(bob), bobBefore + 150e18);
        assertEq(manager.marketTotalPrincipal(marketId), 0);
        assertEq(usdt.balanceOf(address(vault)), 0);
    }

    function test_MixedClaimDoesNotBlockOtherLosingCreditSettlementOrWinnerClaim() public {
        _claimCredit(alice, 100e18);
        _claimCredit(bob, 100e18);
        uint256 marketId = _createMarket(true);

        vm.prank(alice);
        manager.buyWithUsdt(marketId, 0, 100e18, 0);
        vm.prank(charlie);
        manager.buyWithUsdt(marketId, 0, 100e18, 0);
        vm.prank(alice);
        manager.buyWithCredit(marketId, 1, 100e18, 0);
        vm.prank(bob);
        manager.buyWithCredit(marketId, 1, 100e18, 0);

        _resolve(marketId, 0);

        address[] memory aliceCreditUsers = new address[](1);
        aliceCreditUsers[0] = alice;
        uint256 aliceBefore = usdt.balanceOf(alice);
        uint256 charlieBefore = usdt.balanceOf(charlie);

        vm.prank(alice);
        redemption.claim(marketId, aliceCreditUsers);

        assertEq(usdt.balanceOf(alice), aliceBefore + 200e18);
        assertEq(manager.marketTotalPrincipal(marketId), 200e18);

        USDTParimutuelV3OutcomePool memory losingPoolAfterAlice = manager.getOutcomePool(marketId, 1);
        assertEq(losingPoolAfterAlice.principal, 100e18);
        assertEq(losingPoolAfterAlice.creditPrincipal, 100e18);
        assertEq(reserve.lockedCreditBalance(EVENT_ID, bob), 100e18);

        address[] memory bobCreditUsers = new address[](1);
        bobCreditUsers[0] = bob;
        vm.prank(charlie);
        redemption.claim(marketId, bobCreditUsers);

        assertEq(usdt.balanceOf(charlie), charlieBefore + 200e18);
        assertEq(reserve.creditBalance(EVENT_ID, bob), 0);
        assertEq(reserve.lockedCreditBalance(EVENT_ID, bob), 0);
        assertEq(manager.marketTotalPrincipal(marketId), 0);
        assertEq(usdt.balanceOf(address(vault)), 0);
    }

    function test_CreditWinnerBackingUsesResolvedShareSnapshotAfterRealWinnerClaimsFirst() public {
        _claimCredit(bob, 100e18);
        uint256 marketId = _createMarket(true);

        vm.prank(alice);
        manager.buyWithUsdt(marketId, 0, 100e18, 0);
        vm.prank(bob);
        manager.buyWithCredit(marketId, 0, 100e18, 0);
        vm.prank(charlie);
        manager.buyWithUsdt(marketId, 1, 100e18, 0);

        _resolve(marketId, 0);

        uint256 aliceBefore = usdt.balanceOf(alice);
        uint256 bobBefore = usdt.balanceOf(bob);

        vm.prank(alice);
        redemption.claim(marketId, new address[](0));
        vm.prank(bob);
        redemption.claim(marketId, new address[](0));

        assertEq(usdt.balanceOf(alice), aliceBefore + 150e18);
        assertEq(usdt.balanceOf(bob), bobBefore);
        assertEq(reserve.creditBalance(EVENT_ID, bob), 150e18);
        assertEq(reserve.lockedCreditBalance(EVENT_ID, bob), 0);
        assertEq(usdt.balanceOf(address(vault)), 0);
    }

    function _createMarket(bool creditEnabled) internal returns (uint256) {
        USDTParimutuelV3MarketConfig memory config = USDTParimutuelV3MarketConfig({
            tradingCloseTime: uint64(block.timestamp + 1 days),
            resolutionTime: uint64(block.timestamp + 2 days),
            outcomeCount: 2,
            feeBps: 0,
            creditEventId: creditEnabled ? EVENT_ID : 0,
            creditEnabled: creditEnabled,
            metadataHash: keccak256("world-cup-match"),
            metadataURI: "ipfs://world-cup-match"
        });

        vm.prank(admin);
        return factory.createMarket(config);
    }

    function _resolve(uint256 marketId, uint8 winner) internal {
        vm.warp(block.timestamp + 2 days);
        vm.prank(admin);
        factory.resolveToWinner(marketId, winner);
    }

    function _claimCredit(address user, uint256 amount) internal {
        uint64 claimStart = uint64(block.timestamp);
        uint64 claimEnd = uint64(block.timestamp + 1 days);
        uint256 nonce = reserve.getAccount(EVENT_ID, user).nonce;
        bytes32 digest = reserve.getGrantDigest(EVENT_ID, user, amount, claimStart, claimEnd, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(user);
        reserve.claimCredit(EVENT_ID, amount, claimStart, claimEnd, signature);
    }
}
