// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "../src/AIResolver.sol";
import "../src/MarketFactory.sol";
import "../src/OrderBook.sol";
import "../src/OutcomeToken.sol";
import "../src/Vault.sol";
import "../src/FeeModel.sol";
import "../src/MockFlapAIProvider.sol";
import "../src/ITypes.sol";
import "./mocks/MockUSDT.sol";

contract AIResolverTest is Test {
    AIResolver public resolver;
    MarketFactory public factory;
    MockFlapAIProvider public mockProvider;
    OrderBook public book;
    OutcomeToken public token;
    Vault public vault;
    MockUSDT public usdt;

    address public admin = address(this);
    address public keeper = address(0x10);
    address public user1 = address(0x3);
    address public challenger1 = address(0x4);
    address public treasuryAddr = address(0x5);
    address public anyone = address(0x6);

    uint256 public constant ORACLE_FEE = 0.01 ether;
    string public constant PROMPT = "Will BTC be above 100k by end of March?";

    function setUp() public {
        usdt = new MockUSDT();
        vault = new Vault(admin, address(usdt));
        token = new OutcomeToken(admin);
        FeeModel fm = new FeeModel(admin, 20, admin);
        book = new OrderBook(admin, address(vault), address(fm), address(token));

        factory = new MarketFactory(admin, address(book), address(token));
        book.grantRole(book.OPERATOR_ROLE(), address(factory));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(book));

        // Deploy mock provider and resolver
        mockProvider = new MockFlapAIProvider();

        resolver = new AIResolver(address(factory), treasuryAddr);

        // Grant roles
        factory.grantRole(factory.ADMIN_ROLE(), address(resolver));
        factory.grantRole(factory.MARKET_CREATOR_ROLE(), user1);
        factory.setAIResolver(address(resolver));

        resolver.grantRole(resolver.KEEPER_ROLE(), keeper);

        // Override provider to mock
        resolver.setProviderOverride(address(mockProvider));

        // Fund accounts
        vm.deal(user1, 10 ether);
        vm.deal(keeper, 10 ether);
        vm.deal(challenger1, 10 ether);
        vm.deal(anyone, 10 ether);
        vm.deal(address(resolver), 1 ether);
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    function _createAIMarket() internal returns (uint256 marketId) {
        vm.prank(user1);
        marketId = factory.createAIMarket{value: ORACLE_FEE}(PROMPT, 0, block.timestamp + 3600, 1);
    }

    function _createAndResolve() internal returns (uint256 marketId, uint256 requestId) {
        marketId = _createAIMarket();
        vm.warp(block.timestamp + 3601);

        vm.prank(keeper);
        resolver.resolveMarket(marketId);
        requestId = resolver.lastRequestId();
    }

    function _createResolveAndFulfill(uint8 choice) internal returns (uint256 marketId) {
        uint256 requestId;
        (marketId, requestId) = _createAndResolve();
        mockProvider.fulfill(address(resolver), requestId, choice);
    }

    // =========================================================================
    // Happy path
    // =========================================================================

    function test_createAIMarket_success() public {
        uint256 balBefore = address(resolver).balance;
        uint256 marketId = _createAIMarket();

        (, , , , , , , , , bool isAI) = factory.marketMeta(marketId);
        assertTrue(isAI, "isAIMarket flag");

        assertEq(address(resolver).balance, balBefore + ORACLE_FEE);
    }

    function test_resolveMarket_requestsSent() public {
        uint256 marketId = _createAIMarket();
        vm.warp(block.timestamp + 3601);

        uint256 providerBalBefore = address(mockProvider).balance;

        vm.prank(keeper);
        resolver.resolveMarket(marketId);

        assertEq(address(mockProvider).balance, providerBalBefore + ORACLE_FEE);
        assertTrue(resolver.lastRequestId() > 0);
    }

    function test_fulfillAndFinalise() public {
        uint256 marketId = _createResolveAndFulfill(0);

        vm.warp(block.timestamp + resolver.LIVENESS_PERIOD() + 1);

        vm.prank(anyone);
        resolver.finalise(marketId);

        (, , , , MarketState state, bool outcomeYes, , , , ) = factory.marketMeta(marketId);
        assertEq(uint256(state), uint256(MarketState.Resolved));
        assertTrue(outcomeYes);
    }

    function test_fulfillAndFinalise_choiceNo() public {
        uint256 marketId = _createResolveAndFulfill(1);

        vm.warp(block.timestamp + resolver.LIVENESS_PERIOD() + 1);

        vm.prank(anyone);
        resolver.finalise(marketId);

        (, , , , MarketState state, bool outcomeYes, , , , ) = factory.marketMeta(marketId);
        assertEq(uint256(state), uint256(MarketState.Resolved));
        assertFalse(outcomeYes);
    }

    // =========================================================================
    // Fee validation
    // =========================================================================

    function test_createAIMarket_underpayment_reverts() public {
        vm.prank(user1);
        vm.expectRevert("AIResolver: insufficient fee");
        factory.createAIMarket{value: 0}(PROMPT, 0, block.timestamp + 3600, 1);
    }

    function test_resolveMarket_exactFee() public {
        uint256 marketId = _createAIMarket();
        vm.warp(block.timestamp + 3601);

        uint256 resolverBal = address(resolver).balance;
        uint256 providerBal = address(mockProvider).balance;

        vm.prank(keeper);
        resolver.resolveMarket(marketId);

        assertEq(address(mockProvider).balance - providerBal, ORACLE_FEE);
        assertEq(resolverBal - address(resolver).balance, ORACLE_FEE);
    }

    // =========================================================================
    // Challenge flow
    // =========================================================================

    function test_challenge_success() public {
        uint256 marketId = _createResolveAndFulfill(0);

        vm.prank(challenger1);
        resolver.challenge{value: 0.1 ether}(marketId);

        (, , address ch, uint256 challengeEnd, ) = resolver.proposals(marketId);
        assertEq(ch, challenger1);
        assertGt(challengeEnd, 0);
    }

    function test_challenge_wrongBond_reverts() public {
        uint256 marketId = _createResolveAndFulfill(0);

        vm.prank(challenger1);
        vm.expectRevert(AIResolver.WrongBondAmount.selector);
        resolver.challenge{value: 0.05 ether}(marketId);
    }

    function test_challenge_afterLiveness_reverts() public {
        uint256 marketId = _createResolveAndFulfill(0);

        vm.warp(block.timestamp + resolver.LIVENESS_PERIOD() + 1);

        vm.prank(challenger1);
        vm.expectRevert(AIResolver.LivenessExpired.selector);
        resolver.challenge{value: 0.1 ether}(marketId);
    }

    function test_challenge_twice_reverts() public {
        uint256 marketId = _createResolveAndFulfill(0);

        vm.prank(challenger1);
        resolver.challenge{value: 0.1 ether}(marketId);

        vm.prank(anyone);
        vm.expectRevert(AIResolver.AlreadyChallenged.selector);
        resolver.challenge{value: 0.1 ether}(marketId);
    }

    // =========================================================================
    // Admin confirm/override
    // =========================================================================

    function test_confirmResolution() public {
        uint256 marketId = _createResolveAndFulfill(0);

        vm.prank(challenger1);
        resolver.challenge{value: 0.1 ether}(marketId);

        uint256 treasuryBal = treasuryAddr.balance;

        resolver.confirmResolution(marketId);

        assertEq(treasuryAddr.balance - treasuryBal, 0.1 ether);

        (, , , , MarketState state, bool outcomeYes, , , , ) = factory.marketMeta(marketId);
        assertEq(uint256(state), uint256(MarketState.Resolved));
        assertTrue(outcomeYes);
    }

    function test_overrideResolution_toYes() public {
        uint256 marketId = _createResolveAndFulfill(1); // proposed NO

        vm.prank(challenger1);
        resolver.challenge{value: 0.1 ether}(marketId);

        uint256 challengerBal = challenger1.balance;

        resolver.overrideResolution(marketId, true);

        assertEq(challenger1.balance - challengerBal, 0.1 ether + 0.01 ether);

        (, , , , , bool outcomeYes, , , , ) = factory.marketMeta(marketId);
        assertTrue(outcomeYes);
    }

    function test_overrideResolution_toNo() public {
        uint256 marketId = _createResolveAndFulfill(0); // proposed YES

        vm.prank(challenger1);
        resolver.challenge{value: 0.1 ether}(marketId);

        resolver.overrideResolution(marketId, false);

        (, , , , , bool outcomeYes, , , , ) = factory.marketMeta(marketId);
        assertFalse(outcomeYes);
    }

    function test_nonAdmin_confirm_reverts() public {
        uint256 marketId = _createResolveAndFulfill(0);

        vm.prank(challenger1);
        resolver.challenge{value: 0.1 ether}(marketId);

        vm.prank(user1);
        vm.expectRevert(AIResolver.NotAdmin.selector);
        resolver.confirmResolution(marketId);
    }

    function test_nonAdmin_override_reverts() public {
        uint256 marketId = _createResolveAndFulfill(0);

        vm.prank(challenger1);
        resolver.challenge{value: 0.1 ether}(marketId);

        vm.prank(user1);
        vm.expectRevert(AIResolver.NotAdmin.selector);
        resolver.overrideResolution(marketId, false);
    }

    // =========================================================================
    // Refund path
    // =========================================================================

    function test_refund_clearsPending() public {
        (uint256 marketId, uint256 requestId) = _createAndResolve();

        mockProvider.refund(address(resolver), requestId);

        (, , , bool pending, ) = resolver.aiMarkets(marketId);
        assertFalse(pending);

        // Should be able to resolve again (market is in Resolving state)
        vm.prank(keeper);
        resolver.resolveMarket(marketId);
    }

    function test_refund_emitsEvent() public {
        (uint256 marketId, uint256 requestId) = _createAndResolve();

        vm.expectEmit(true, false, false, true);
        emit AIResolver.AIResolutionRefunded(marketId, requestId);

        mockProvider.refund(address(resolver), requestId);
    }

    // =========================================================================
    // Access control
    // =========================================================================

    function test_resolveMarket_nonKeeper_reverts() public {
        uint256 marketId = _createAIMarket();
        vm.warp(block.timestamp + 3601);

        vm.prank(user1);
        vm.expectRevert(AIResolver.NotAuthorized.selector);
        resolver.resolveMarket(marketId);
    }

    function test_finalise_beforeLiveness_reverts() public {
        uint256 marketId = _createResolveAndFulfill(0);

        vm.prank(anyone);
        vm.expectRevert(AIResolver.LivenessNotExpired.selector);
        resolver.finalise(marketId);
    }

    function test_finalise_afterChallenge_reverts() public {
        uint256 marketId = _createResolveAndFulfill(0);

        vm.prank(challenger1);
        resolver.challenge{value: 0.1 ether}(marketId);

        vm.warp(block.timestamp + resolver.LIVENESS_PERIOD() + 1);

        vm.prank(anyone);
        vm.expectRevert(AIResolver.ChallengeActive.selector);
        resolver.finalise(marketId);
    }

    function test_doubleResolve_reverts() public {
        uint256 marketId = _createResolveAndFulfill(0);

        vm.warp(block.timestamp + resolver.LIVENESS_PERIOD() + 1);
        vm.prank(anyone);
        resolver.finalise(marketId);

        vm.prank(keeper);
        vm.expectRevert(AIResolver.MarketAlreadyResolved.selector);
        resolver.resolveMarket(marketId);
    }

    // =========================================================================
    // Edge cases
    // =========================================================================

    function test_finalise_byAnyone() public {
        uint256 marketId = _createResolveAndFulfill(0);

        vm.warp(block.timestamp + resolver.LIVENESS_PERIOD() + 1);

        vm.prank(address(0xDEAD));
        resolver.finalise(marketId);

        (, , , , MarketState state, , , , , ) = factory.marketMeta(marketId);
        assertEq(uint256(state), uint256(MarketState.Resolved));
    }

    function test_treasury_receivesBond() public {
        uint256 marketId = _createResolveAndFulfill(0);

        vm.prank(challenger1);
        resolver.challenge{value: 0.1 ether}(marketId);

        uint256 treasuryBal = treasuryAddr.balance;

        resolver.confirmResolution(marketId);

        assertEq(treasuryAddr.balance, treasuryBal + 0.1 ether);
    }

    function test_challenger_rewarded() public {
        uint256 marketId = _createResolveAndFulfill(0);

        vm.prank(challenger1);
        resolver.challenge{value: 0.1 ether}(marketId);

        uint256 challengerBal = challenger1.balance;

        resolver.overrideResolution(marketId, false);

        assertEq(challenger1.balance, challengerBal + 0.11 ether);
    }

    // -------------------------------------------------------------------------
    // Challenge timeout tests
    // -------------------------------------------------------------------------

    function test_finaliseAfterChallengeTimeout_success() public {
        uint256 marketId = _createResolveAndFulfill(0); // AI says YES

        vm.prank(challenger1);
        resolver.challenge{value: 0.1 ether}(marketId);

        uint256 treasuryBal = treasuryAddr.balance;

        // Fast forward past 24h challenge period
        vm.warp(block.timestamp + 24 hours + 1);

        // Anyone can call it
        vm.prank(address(0xBEEF));
        resolver.finaliseAfterChallengeTimeout(marketId);

        // Market resolved with AI's original answer (YES)
        (, , , , MarketState state, bool outcomeYes, , , , ) = factory.marketMeta(marketId);
        assertEq(uint8(state), uint8(MarketState.Resolved));
        assertTrue(outcomeYes);

        // Challenger lost bond to treasury
        assertEq(treasuryAddr.balance, treasuryBal + 0.1 ether);
    }

    function test_finaliseAfterChallengeTimeout_beforeExpiry_reverts() public {
        uint256 marketId = _createResolveAndFulfill(0);

        vm.prank(challenger1);
        resolver.challenge{value: 0.1 ether}(marketId);

        // Only 12 hours passed
        vm.warp(block.timestamp + 12 hours);

        vm.expectRevert(AIResolver.ChallengeNotExpired.selector);
        resolver.finaliseAfterChallengeTimeout(marketId);
    }

    function test_finaliseAfterChallengeTimeout_noChallengeReverts() public {
        uint256 marketId = _createResolveAndFulfill(0);

        // No challenge was made
        vm.warp(block.timestamp + 24 hours + 1);

        vm.expectRevert(AIResolver.NotChallenged.selector);
        resolver.finaliseAfterChallengeTimeout(marketId);
    }

    function test_finaliseAfterChallengeTimeout_alreadyFinalized_reverts() public {
        uint256 marketId = _createResolveAndFulfill(0);

        vm.prank(challenger1);
        resolver.challenge{value: 0.1 ether}(marketId);

        // Admin confirms first
        resolver.confirmResolution(marketId);

        vm.warp(block.timestamp + 24 hours + 1);

        vm.expectRevert(AIResolver.AlreadyFinalized.selector);
        resolver.finaliseAfterChallengeTimeout(marketId);
    }
}
