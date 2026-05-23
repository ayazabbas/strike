// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/MockFlapAIProvider.sol";
import "../src/NativeTokenPoolAIResolver.sol";
import "../src/NativeTokenParimutuelFactory.sol";
import "../src/NativeTokenPoolManager.sol";
import "../src/NativeTokenPoolRedemption.sol";
import "../src/NativeTokenPoolTypes.sol";
import "../src/NativeTokenPoolVault.sol";
import "../src/ParimutuelTypes.sol";
import "./mocks/MockUSDT.sol";

contract FeeOnTransferToken is MockUSDT {
    uint256 public constant FEE_BPS = 100;

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            uint256 fee = value * FEE_BPS / 10_000;
            super._update(from, address(0), fee);
            super._update(from, to, value - fee);
            return;
        }

        super._update(from, to, value);
    }
}

contract OutboundFeeToken is MockUSDT {
    uint256 public constant FEE_BPS = 100;
    address public taxedSender;

    function setTaxedSender(address taxedSender_) external {
        taxedSender = taxedSender_;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from == taxedSender && from != address(0) && to != address(0)) {
            uint256 fee = value * FEE_BPS / 10_000;
            super._update(from, address(0), fee);
            super._update(from, to, value - fee);
            return;
        }

        super._update(from, to, value);
    }
}

contract RejectNativePayout {
    function create(NativeTokenParimutuelFactory factory, NativeTokenPoolMarketConfig calldata config)
        external
        payable
        returns (uint256)
    {
        return factory.createNativePoolMarket{value: msg.value}(config);
    }

    function withdraw(NativeTokenParimutuelFactory factory) external {
        factory.withdrawNativePayout();
    }

    receive() external payable {
        revert("reject native");
    }
}

contract NativeTokenPoolTest is Test {
    event NativeTokenPoolMarketCreated(
        uint256 indexed marketId,
        address indexed creator,
        address indexed collateralToken,
        uint8 outcomeCount,
        uint64 tradingCloseTime,
        uint64 resolutionTime,
        uint16 feeBps,
        uint256 minStake,
        uint256 maxStake,
        bytes32 metadataHash,
        string metadataURI
    );
    event NativeTokenPoolPromptConfigured(uint256 indexed marketId, string prompt);

    NativeTokenParimutuelFactory public factory;
    NativeTokenPoolManager public manager;
    NativeTokenPoolRedemption public redemption;
    NativeTokenPoolVault public vault;
    NativeTokenPoolAIResolver public aiResolver;
    MockFlapAIProvider public mockProvider;
    MockUSDT public token;

    address public admin = address(0x1);
    address public keeper = address(0x10);
    address public creator = address(0x2);
    address public alice = address(0x3);
    address public bob = address(0x4);
    address public challenger = address(0x5);
    address public feeRecipient = address(0x6);
    address payable public treasury = payable(address(0x31436E47AcFb85537547E9f5Ec41423dcD15D6AB));

    function setUp() public {
        token = new MockUSDT();
        factory = new NativeTokenParimutuelFactory(admin, treasury);
        vault = new NativeTokenPoolVault(admin);
        manager = new NativeTokenPoolManager(admin, address(factory), address(vault), feeRecipient);
        redemption = new NativeTokenPoolRedemption(admin, address(manager), address(vault));
        aiResolver = new NativeTokenPoolAIResolver(address(factory), 1);
        mockProvider = new MockFlapAIProvider();

        vm.startPrank(admin);
        factory.setPoolManager(address(manager));
        factory.grantRole(factory.RESOLVER_ROLE(), address(aiResolver));
        manager.grantRole(manager.REDEMPTION_ROLE(), address(redemption));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(manager));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(redemption));
        vm.stopPrank();
        aiResolver.grantRole(aiResolver.KEEPER_ROLE(), keeper);
        aiResolver.setProviderOverride(address(mockProvider));

        token.mint(creator, 1_000_000e18);
        token.mint(alice, 1_000_000e18);
        token.mint(bob, 1_000_000e18);

        vm.prank(creator);
        token.approve(address(manager), type(uint256).max);
        vm.prank(alice);
        token.approve(address(manager), type(uint256).max);
        vm.prank(bob);
        token.approve(address(manager), type(uint256).max);

        vm.deal(creator, 10 ether);
        vm.deal(challenger, 10 ether);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(address(aiResolver), 10 ether);
    }

    function _config(address collateralToken, uint8 outcomeCount)
        internal
        view
        returns (NativeTokenPoolMarketConfig memory config)
    {
        config = NativeTokenPoolMarketConfig({
            collateralToken: collateralToken,
            tradingCloseTime: uint64(block.timestamp + 1 hours),
            resolutionTime: uint64(block.timestamp + 1 hours),
            outcomeCount: outcomeCount,
            curveType: ParimutuelCurveType.Flat,
            curveParam: 0,
            feeBps: 200,
            minStake: 1e18,
            maxStake: 1_000_000e18,
            metadataHash: keccak256("native-token-pool-metadata"),
            metadataURI: "https://metadata.strike.pm/native-token-pool/1.json",
            prompt: "Resolve this Flap Token Pool using the supplied official template and public evidence."
        });
    }

    function _createMarket(uint8 outcomeCount) internal returns (uint256 marketId) {
        uint256 bond = factory.creatorBondAmount();
        vm.prank(creator);
        marketId = factory.createNativePoolMarket{value: bond}(_config(address(token), outcomeCount));
    }

    function _closeResolveFinalize(uint256 marketId, uint8 winningOutcomeId) internal {
        vm.warp(block.timestamp + 1 hours);
        factory.closeMarket(marketId);
        vm.prank(admin);
        factory.resolveToWinner(marketId, winningOutcomeId);
        vm.warp(block.timestamp + factory.CHALLENGE_WINDOW() + 1);
        factory.finalizeMarket(marketId);
    }

    function test_PermissionlessCreateWithArbitraryERC20StoresPromptAndMetadata() public {
        NativeTokenPoolMarketConfig memory config = _config(address(token), 3);
        uint256 bond = factory.creatorBondAmount();
        vm.expectEmit(true, true, true, true, address(factory));
        emit NativeTokenPoolMarketCreated(
            1,
            alice,
            address(token),
            3,
            config.tradingCloseTime,
            config.resolutionTime,
            config.feeBps,
            config.minStake,
            config.maxStake,
            config.metadataHash,
            config.metadataURI
        );
        vm.expectEmit(true, false, false, true, address(factory));
        emit NativeTokenPoolPromptConfigured(1, config.prompt);
        vm.prank(alice);
        uint256 marketId = factory.createNativePoolMarket{value: bond}(config);

        NativeTokenPoolMarket memory market = factory.getMarket(marketId);
        assertEq(market.creator, alice);
        assertEq(market.collateralToken, address(token));
        assertEq(market.outcomeCount, 3);
        assertEq(market.metadataHash, keccak256("native-token-pool-metadata"));
        assertEq(market.metadataURI, "https://metadata.strike.pm/native-token-pool/1.json");
        assertEq(
            market.prompt, "Resolve this Flap Token Pool using the supplied official template and public evidence."
        );
        assertEq(market.feeBps, 200);
    }

    function test_OutcomeCountValidationSupportsTwoThroughEight() public {
        _createMarket(2);
        _createMarket(8);

        uint256 bond = factory.creatorBondAmount();
        vm.expectRevert("NativeTokenFactory: invalid outcomeCount");
        vm.prank(creator);
        factory.createNativePoolMarket{value: bond}(_config(address(token), 1));

        vm.expectRevert("NativeTokenFactory: invalid outcomeCount");
        vm.prank(creator);
        factory.createNativePoolMarket{value: bond}(_config(address(token), 9));
    }

    function test_PlatformFeeMustMatchAdminConfiguredFee() public {
        NativeTokenPoolMarketConfig memory config = _config(address(token), 2);
        config.feeBps = 0;
        uint256 bond = factory.creatorBondAmount();

        vm.expectRevert("NativeTokenFactory: invalid fee");
        vm.prank(creator);
        factory.createNativePoolMarket{value: bond}(config);

        vm.prank(admin);
        factory.setPlatformFeeBps(0);
        vm.prank(creator);
        uint256 marketId = factory.createNativePoolMarket{value: bond}(config);
        assertEq(factory.getMarket(marketId).feeBps, 0);
    }

    function test_CreationBondRequiredAndAdminConfigurable() public {
        uint256 bond = factory.creatorBondAmount();
        vm.expectRevert("NativeTokenFactory: creator bond required");
        vm.prank(creator);
        factory.createNativePoolMarket{value: bond - 1}(_config(address(token), 2));

        uint256 challengerBond = factory.challengerBondAmount();
        vm.startPrank(admin);
        vm.expectRevert("NativeTokenFactory: zero creator bond");
        factory.setBondParams(0, challengerBond);
        vm.expectRevert("NativeTokenFactory: zero challenger bond");
        factory.setBondParams(0.2 ether, 0);
        factory.setBondParams(0.2 ether, challengerBond);
        vm.stopPrank();

        vm.prank(creator);
        uint256 marketId = factory.createNativePoolMarket{value: 0.2 ether}(_config(address(token), 2));

        NativeTokenPoolMarket memory market = factory.getMarket(marketId);
        assertEq(market.creatorBondAmount, 0.2 ether);
    }

    function test_ChallengerBondRequiredAndAdminConfigurable() public {
        uint256 marketId = _createMarket(2);
        _closeResolveFinalizeWindowOnly(marketId);

        uint256 creatorBond = factory.creatorBondAmount();
        vm.prank(admin);
        factory.setBondParams(creatorBond, 0.2 ether);

        vm.expectRevert("NativeTokenFactory: challenger bond required");
        vm.prank(challenger);
        factory.openChallenge{value: 0.1 ether}(marketId, NativeTokenPoolReason.BadResolution, keccak256("evidence"));

        vm.prank(challenger);
        factory.openChallenge{value: 0.2 ether}(marketId, NativeTokenPoolReason.BadResolution, keccak256("evidence"));
    }

    function test_ClaimRejectsOutboundTokenTransferShortfall() public {
        OutboundFeeToken outboundFeeToken = new OutboundFeeToken();
        outboundFeeToken.mint(alice, 100e18);

        vm.prank(alice);
        outboundFeeToken.approve(address(manager), type(uint256).max);

        uint256 bond = factory.creatorBondAmount();
        vm.prank(creator);
        uint256 marketId = factory.createNativePoolMarket{value: bond}(_config(address(outboundFeeToken), 2));

        vm.prank(alice);
        manager.buy(marketId, 0, 100e18, 98e18);
        outboundFeeToken.setTaxedSender(address(vault));
        _closeResolveFinalize(marketId, 0);

        vm.expectRevert("NativeTokenPoolVault: recipient transfer shortfall");
        vm.prank(alice);
        redemption.claim(marketId);
    }

    function test_BuyRejectsFeeOnTransferTokenShortfall() public {
        FeeOnTransferToken taxedToken = new FeeOnTransferToken();
        taxedToken.mint(alice, 100e18);

        vm.prank(alice);
        taxedToken.approve(address(manager), type(uint256).max);

        uint256 bond = factory.creatorBondAmount();
        vm.prank(creator);
        uint256 marketId = factory.createNativePoolMarket{value: bond}(_config(address(taxedToken), 2));

        vm.expectRevert("NativeTokenPoolManager: collateral transfer shortfall");
        vm.prank(alice);
        manager.buy(marketId, 0, 10e18, 9.8e18);

        assertEq(taxedToken.balanceOf(address(vault)), 0);
        assertEq(manager.marketTotalPrincipal(marketId), 0);
    }

    function test_MaxStakeIsCumulativePerWallet() public {
        NativeTokenPoolMarketConfig memory config = _config(address(token), 2);
        config.maxStake = 100e18;
        uint256 bond = factory.creatorBondAmount();
        vm.prank(creator);
        uint256 marketId = factory.createNativePoolMarket{value: bond}(config);

        vm.prank(alice);
        manager.buy(marketId, 0, 60e18, 58.8e18);
        assertEq(manager.userMarketStake(marketId, alice), 60e18);

        vm.expectRevert("NativeTokenPoolManager: above max stake");
        vm.prank(alice);
        manager.buy(marketId, 1, 50e18, 49e18);

        vm.prank(alice);
        manager.buy(marketId, 1, 40e18, 39.2e18);
        assertEq(manager.userMarketStake(marketId, alice), 100e18);
    }

    function test_FinalizeRefundsCreatorBondAfterChallengeWindow() public {
        uint256 marketId = _createMarket(2);
        _closeResolveFinalizeWindowOnly(marketId);

        uint256 creatorBefore = creator.balance;
        vm.warp(block.timestamp + factory.CHALLENGE_WINDOW() + 1);
        factory.finalizeMarket(marketId);

        assertEq(creator.balance, creatorBefore);
        assertEq(factory.pendingNativePayouts(creator), factory.creatorBondAmount());
        assertTrue(factory.getMarket(marketId).creatorBondSettled);

        vm.prank(creator);
        factory.withdrawNativePayout();
        assertEq(creator.balance, creatorBefore + factory.creatorBondAmount());
    }

    function test_FinalizeNotBlockedByRejectingCreatorNativePayout() public {
        RejectNativePayout rejectingCreator = new RejectNativePayout();
        NativeTokenPoolMarketConfig memory config = _config(address(token), 2);
        uint256 bond = factory.creatorBondAmount();

        vm.deal(address(rejectingCreator), 1 ether);
        uint256 marketId = rejectingCreator.create{value: bond}(factory, config);

        vm.prank(admin);
        factory.cancelMarket(marketId, NativeTokenPoolReason.Other, keccak256("rejecting-creator"));
        vm.warp(block.timestamp + factory.CHALLENGE_WINDOW() + 1);
        factory.finalizeMarket(marketId);

        assertTrue(factory.isFinalized(marketId));
        assertEq(factory.pendingNativePayouts(address(rejectingCreator)), bond);

        vm.expectRevert("NativeTokenFactory: native payout failed");
        rejectingCreator.withdraw(factory);
        assertEq(factory.pendingNativePayouts(address(rejectingCreator)), bond);
    }

    function test_BuyAccountingClaimWinnerWithTwoPercentFee() public {
        uint256 marketId = _createMarket(2);

        vm.prank(alice);
        manager.buy(marketId, 0, 100e18, 98e18);
        vm.prank(bob);
        manager.buy(marketId, 1, 50e18, 49e18);

        assertEq(manager.marketTotalPrincipal(marketId), 147e18);
        assertEq(manager.accruedFees(address(token)), 3e18);

        _closeResolveFinalize(marketId, 0);

        uint256 aliceBefore = token.balanceOf(alice);
        vm.prank(alice);
        uint256 payout = redemption.claim(marketId);

        assertEq(payout, 147e18);
        assertEq(token.balanceOf(alice), aliceBefore + 147e18);
    }

    function test_InvalidAndCancelRefundPrincipal() public {
        uint256 invalidMarketId = _createMarket(2);
        vm.prank(alice);
        manager.buy(invalidMarketId, 0, 100e18, 98e18);

        vm.warp(block.timestamp + 1 hours);
        factory.closeMarket(invalidMarketId);
        vm.prank(admin);
        factory.resolveInvalid(invalidMarketId, NativeTokenPoolReason.OracleFailure, keccak256("oracle-down"));
        vm.warp(block.timestamp + factory.CHALLENGE_WINDOW() + 1);
        factory.finalizeMarket(invalidMarketId);

        uint8[] memory outcomes = new uint8[](1);
        outcomes[0] = 0;
        uint256 aliceBefore = token.balanceOf(alice);
        vm.prank(alice);
        uint256 refundAmount = redemption.refund(invalidMarketId, outcomes);
        assertEq(refundAmount, 98e18);
        assertEq(token.balanceOf(alice), aliceBefore + 98e18);

        uint256 cancelledMarketId = _createMarket(2);
        vm.prank(bob);
        manager.buy(cancelledMarketId, 1, 20e18, 19.6e18);
        vm.prank(admin);
        factory.cancelMarket(cancelledMarketId, NativeTokenPoolReason.Other, keccak256("cancel"));
        vm.warp(block.timestamp + factory.CHALLENGE_WINDOW() + 1);
        factory.finalizeMarket(cancelledMarketId);

        outcomes[0] = 1;
        uint256 bobBefore = token.balanceOf(bob);
        vm.prank(bob);
        refundAmount = redemption.refund(cancelledMarketId, outcomes);
        assertEq(refundAmount, 19.6e18);
        assertEq(token.balanceOf(bob), bobBefore + 19.6e18);
    }

    function test_ChallengeSuccessSlashesCreatorBondAndAllowsRefunds() public {
        uint256 marketId = _createMarket(2);
        vm.prank(alice);
        manager.buy(marketId, 0, 100e18, 98e18);
        uint8[] memory outcomes = new uint8[](1);
        outcomes[0] = 0;

        vm.warp(block.timestamp + 1 hours);
        factory.closeMarket(marketId);
        vm.prank(admin);
        factory.resolveToWinner(marketId, 0);

        uint256 challengerBond = factory.challengerBondAmount();
        uint256 creatorBond = factory.creatorBondAmount();
        uint256 challengerBefore = challenger.balance;
        uint256 treasuryBefore = treasury.balance;

        vm.prank(challenger);
        factory.openChallenge{value: challengerBond}(
            marketId, NativeTokenPoolReason.BadResolution, keccak256("evidence")
        );
        vm.prank(admin);
        factory.adjudicateChallenge(marketId, true, NativeTokenPoolReason.BadResolution, keccak256("evidence"));

        assertEq(challenger.balance, challengerBefore - challengerBond);
        assertEq(treasury.balance, treasuryBefore);
        assertEq(factory.pendingNativePayouts(challenger), challengerBond + creatorBond / 2);
        assertEq(factory.pendingNativePayouts(treasury), creatorBond / 2);
        assertTrue(factory.isFinalized(marketId));
        assertEq(uint8(factory.getMarketState(marketId)), uint8(ParimutuelMarketState.Invalid));

        vm.prank(challenger);
        factory.withdrawNativePayout();
        vm.prank(treasury);
        factory.withdrawNativePayout();
        assertEq(challenger.balance, challengerBefore + creatorBond / 2);
        assertEq(treasury.balance, treasuryBefore + creatorBond / 2);

        uint256 aliceBefore = token.balanceOf(alice);
        vm.prank(alice);
        uint256 refundAmount = redemption.refund(marketId, outcomes);
        assertEq(refundAmount, 98e18);
        assertEq(token.balanceOf(alice), aliceBefore + 98e18);
    }

    function test_ChallengeSuccessSlashesCreatorBondAndRefundsChallengerBond() public {
        uint256 marketId = _createMarket(2);
        _closeResolveFinalizeWindowOnly(marketId);

        uint256 challengerBond = factory.challengerBondAmount();
        uint256 creatorBond = factory.creatorBondAmount();
        uint256 challengerBefore = challenger.balance;
        uint256 treasuryBefore = treasury.balance;

        vm.prank(challenger);
        factory.openChallenge{value: challengerBond}(
            marketId, NativeTokenPoolReason.BadResolution, keccak256("evidence")
        );
        vm.prank(admin);
        factory.adjudicateChallenge(marketId, true, NativeTokenPoolReason.BadResolution, keccak256("evidence"));

        assertEq(challenger.balance, challengerBefore - challengerBond);
        assertEq(treasury.balance, treasuryBefore);
        assertEq(factory.pendingNativePayouts(challenger), challengerBond + creatorBond / 2);
        assertEq(factory.pendingNativePayouts(treasury), creatorBond / 2);
        assertTrue(factory.isFinalized(marketId));

        vm.prank(challenger);
        factory.withdrawNativePayout();
        vm.prank(treasury);
        factory.withdrawNativePayout();
        assertEq(challenger.balance, challengerBefore + creatorBond / 2);
        assertEq(treasury.balance, treasuryBefore + creatorBond / 2);
    }

    function test_FailedChallengeSplitsChallengerBondToCreatorAndTreasury() public {
        uint256 marketId = _createMarket(2);
        _closeResolveFinalizeWindowOnly(marketId);

        uint256 challengerBond = factory.challengerBondAmount();
        uint256 creatorBefore = creator.balance;
        uint256 treasuryBefore = treasury.balance;

        vm.prank(challenger);
        factory.openChallenge{value: challengerBond}(
            marketId, NativeTokenPoolReason.BadResolution, keccak256("weak-evidence")
        );
        vm.prank(admin);
        factory.adjudicateChallenge(marketId, false, NativeTokenPoolReason.BadResolution, keccak256("weak-evidence"));

        assertEq(creator.balance, creatorBefore);
        assertEq(treasury.balance, treasuryBefore);
        assertEq(factory.pendingNativePayouts(creator), challengerBond / 2);
        assertEq(factory.pendingNativePayouts(treasury), challengerBond / 2);

        vm.prank(creator);
        factory.withdrawNativePayout();
        vm.prank(treasury);
        factory.withdrawNativePayout();
        assertEq(creator.balance, creatorBefore + challengerBond / 2);
        assertEq(treasury.balance, treasuryBefore + challengerBond / 2);

        vm.warp(block.timestamp + factory.CHALLENGE_WINDOW() + 1);
        factory.finalizeMarket(marketId);
        assertTrue(factory.isFinalized(marketId));
    }

    function test_CreatorCanBuyOwnMarket() public {
        uint256 marketId = _createMarket(2);

        vm.prank(creator);
        manager.buy(marketId, 0, 10e18, 9.8e18);

        ParimutuelPosition memory position = manager.getUserPosition(marketId, creator, 0);
        assertEq(position.principal, 9.8e18);
        assertEq(position.rewardShares, 9.8e18);
    }

    function test_NativePoolAIRequestUsesMarketPromptAndOutcomeCount() public {
        NativeTokenPoolMarketConfig memory config = _config(address(token), 5);
        config.prompt = "Resolve the native token pool from official final standings.";
        uint256 bond = factory.creatorBondAmount();

        vm.prank(creator);
        uint256 marketId = factory.createNativePoolMarket{value: bond}(config);

        vm.warp(block.timestamp + 1 hours);
        vm.prank(keeper);
        aiResolver.resolveMarket(marketId);

        assertEq(mockProvider.lastModelId(), 1);
        assertEq(mockProvider.lastPrompt(), config.prompt);
        assertEq(mockProvider.lastNumChoices(), 5);
        assertEq(aiResolver.requestToMarket(aiResolver.lastRequestId()), marketId);
    }

    function test_NativePoolAIInvalidChoiceDoesNotFinalise() public {
        uint256 marketId = _requestNativePoolAIResolution(3);
        uint256 requestId = aiResolver.lastRequestId();

        mockProvider.fulfill(address(aiResolver), requestId, 3);

        vm.warp(block.timestamp + aiResolver.LIVENESS_PERIOD() + 1);
        vm.expectRevert(NativeTokenPoolAIResolver.NoProposal.selector);
        aiResolver.finalise(marketId);
        assertEq(uint8(factory.getMarketState(marketId)), uint8(ParimutuelMarketState.Closed));
    }

    function test_NativePoolAIUnknownFulfillReverts() public {
        vm.expectRevert(NativeTokenPoolAIResolver.UnknownRequest.selector);
        mockProvider.fulfill(address(aiResolver), 999, 0);
    }

    function test_NativePoolAIUnknownRefundReverts() public {
        vm.expectRevert(NativeTokenPoolAIResolver.UnknownRequest.selector);
        mockProvider.refund(address(aiResolver), 999);
    }

    function test_NativePoolAIDuplicateCallbackRevertsAfterInvalidChoice() public {
        _requestNativePoolAIResolution(2);
        uint256 requestId = aiResolver.lastRequestId();
        mockProvider.fulfill(address(aiResolver), requestId, 9);

        vm.expectRevert(NativeTokenPoolAIResolver.RequestNotPending.selector);
        mockProvider.fulfill(address(aiResolver), requestId, 1);
    }

    function test_NativePoolAIFinaliseAfterLivenessResolvesThroughFactory() public {
        uint256 marketId = _requestNativePoolAIResolution(4);
        mockProvider.fulfill(address(aiResolver), aiResolver.lastRequestId(), 2);

        vm.warp(block.timestamp + aiResolver.LIVENESS_PERIOD());
        vm.prank(keeper);
        aiResolver.finalise(marketId);

        NativeTokenPoolMarket memory market = factory.getMarket(marketId);
        assertEq(uint8(market.state), uint8(ParimutuelMarketState.Resolved));
        assertEq(market.winningOutcomeId, 2);
        assertTrue(market.hasWinner);
    }

    function test_NativePoolAICannotFinaliseBeforeLiveness() public {
        uint256 marketId = _requestNativePoolAIResolution(2);
        mockProvider.fulfill(address(aiResolver), aiResolver.lastRequestId(), 1);

        vm.expectRevert(NativeTokenPoolAIResolver.LivenessNotExpired.selector);
        aiResolver.finalise(marketId);
    }

    function _closeResolveFinalizeWindowOnly(uint256 marketId) internal {
        vm.warp(block.timestamp + 1 hours);
        factory.closeMarket(marketId);
        vm.prank(admin);
        factory.resolveToWinner(marketId, 0);
    }

    function _requestNativePoolAIResolution(uint8 outcomeCount) internal returns (uint256 marketId) {
        marketId = _createMarket(outcomeCount);
        vm.warp(block.timestamp + 1 hours);
        vm.prank(keeper);
        aiResolver.resolveMarket(marketId);
    }
}
