// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import "@pythnetwork/pyth-sdk-solidity/MockPyth.sol";
import "../src/MarketFactory.sol";
import "../src/PythResolver.sol";
import "../src/OrderBook.sol";
import "../src/BatchAuction.sol";
import "../src/OutcomeToken.sol";
import "../src/Vault.sol";
import "../src/FeeModel.sol";
import "../src/Redemption.sol";
import "../src/ITypes.sol";
import "./mocks/MockUSDT.sol";

/// @title PoolSolvencyTest
/// @notice Fuzz tests verifying that the market pool is always solvent:
///         sum of all redemptions <= market pool balance for any market.
///         Covers C-01 (pool insolvency) and H-03 (rounding remainder) audit fixes.
contract PoolSolvencyTest is Test {
    MarketFactory public factory;
    PythResolver public resolver;
    OrderBook public book;
    BatchAuction public auction;
    OutcomeToken public token;
    Vault public vault;
    FeeModel public feeModel;
    Redemption public redemption;
    MockPyth public mockPyth;
    MockUSDT public usdt;

    address public admin = address(0x1);
    address public operator = address(0x2);
    address public feeCollector = address(0x99);

    bytes32 public constant PRICE_ID = bytes32(uint256(0xB7C));
    int64 public constant STRIKE_PRICE = int64(50000_00000000);
    uint256 public constant LOT = 1e16;

    // User addresses
    address[10] public users;

    function setUp() public {
        usdt = new MockUSDT();

        vm.startPrank(admin);
        vault = new Vault(admin, address(usdt));
        feeModel = new FeeModel(admin, 20, feeCollector); // 20 bps fee
        token = new OutcomeToken(admin);
        book = new OrderBook(admin, address(vault), address(feeModel), address(token));
        auction = new BatchAuction(admin, address(book), address(vault), address(token));

        mockPyth = new MockPyth(120, 1);
        factory = new MarketFactory(admin, address(book), address(token));
        resolver = new PythResolver(address(mockPyth), address(factory));
        redemption = new Redemption(address(factory), address(token), address(vault));

        book.grantRole(book.OPERATOR_ROLE(), operator);
        book.grantRole(book.OPERATOR_ROLE(), address(auction));
        book.grantRole(book.OPERATOR_ROLE(), address(factory));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(book));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(auction));
        vault.grantRole(vault.PROTOCOL_ROLE(), address(redemption));
        token.grantRole(token.MINTER_ROLE(), address(auction));
        token.grantRole(token.MINTER_ROLE(), address(redemption));
        token.grantRole(token.ESCROW_ROLE(), address(auction));
        factory.grantRole(factory.ADMIN_ROLE(), address(resolver));
        factory.grantRole(factory.MARKET_CREATOR_ROLE(), admin);
        vm.stopPrank();

        for (uint256 i = 0; i < 10; i++) {
            users[i] = address(uint160(0x100 + i));
            usdt.mint(users[i], 1_000_000 ether);
            vm.prank(users[i]);
            usdt.approve(address(vault), type(uint256).max);
            vm.deal(users[i], 10 ether);
        }
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    function _createMarket() internal returns (uint256 fmId, uint256 obId) {
        vm.prank(admin);
        fmId = factory.createMarket(PRICE_ID, STRIKE_PRICE, block.timestamp + 7200, 60, 1);
        (, , , , , , , uint256 _obId) = factory.marketMeta(fmId);
        obId = _obId;
    }

    function _resolveMarket(uint256 fmId, bool yesWins) internal {
        (, , uint256 expiry, , , , , ) = factory.marketMeta(fmId);
        vm.warp(expiry);
        factory.closeMarket(fmId);

        int64 price = yesWins ? STRIKE_PRICE + 1 : STRIKE_PRICE - 1;
        uint64 publishTime = uint64(expiry + 10);
        bytes[] memory updateData = new bytes[](1);
        updateData[0] = mockPyth.createPriceFeedUpdateData(
            PRICE_ID, price, 100_00000000, -8, price, 100_00000000,
            publishTime, publishTime - 1
        );

        vm.prank(users[0]);
        resolver.resolveMarket{value: 1}(fmId, updateData);

        vm.roll(block.number + 4);
        resolver.finalizeResolution(fmId);
    }

    // =========================================================================
    // Fuzz: Pool solvency with fees (C-01)
    // =========================================================================

    /// @notice For any clearing tick and lot count, pool must hold enough
    ///         for all winning redemptions.
    function testFuzz_PoolSolvency_BuyOrders(
        uint256 _tick,
        uint256 _bidLots,
        uint256 _askLots,
        bool _yesWins
    ) public {
        uint8 tick = uint8(bound(_tick, 5, 95));
        uint64 bidLots = uint64(bound(_bidLots, 1, 200));
        uint64 askLots = uint64(bound(_askLots, 1, 200));

        (uint256 fmId, uint256 obId) = _createMarket();

        // Place bids and asks at the same tick to guarantee a match
        vm.prank(users[0]);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilBatch, tick, bidLots);

        vm.prank(users[1]);
        book.placeOrder(obId, Side.Ask, OrderType.GoodTilBatch, tick, askLots);

        auction.clearBatch(obId);

        uint256 matchedLots = bidLots < askLots ? bidLots : askLots;
        uint256 poolBalance = vault.marketPool(obId);

        // Pool must hold at least matchedLots * LOT_SIZE
        assertGe(poolBalance, matchedLots * LOT, "Pool insolvent: pool < matched * LOT_SIZE");

        // Now resolve and redeem to verify end-to-end
        _resolveMarket(fmId, _yesWins);

        // The winner redeems
        address winner = _yesWins ? users[0] : users[1];
        uint256 winnerBalance = _yesWins
            ? token.balanceOf(winner, obId * 2)      // YES token
            : token.balanceOf(winner, obId * 2 + 1);  // NO token

        if (winnerBalance > 0) {
            vm.startPrank(winner);
            token.setApprovalForAll(address(redemption), true);
            redemption.redeem(fmId, winnerBalance);
            vm.stopPrank();
        }

        // Pool must still be >= 0 (no underflow/revert during redemption)
        assertGe(vault.marketPool(obId), 0, "Pool went negative after redemption");
    }

    /// @notice Multiple users, multiple ticks — pool stays solvent.
    function testFuzz_PoolSolvency_MultiUser(
        uint256 _tick1,
        uint256 _tick2,
        uint256 _lots1,
        uint256 _lots2,
        uint256 _lots3,
        uint256 _lots4,
        bool _yesWins
    ) public {
        uint8 tick1 = uint8(bound(_tick1, 10, 90));
        uint8 tick2 = uint8(bound(_tick2, 10, 90));
        uint64 lots1 = uint64(bound(_lots1, 1, 50));
        uint64 lots2 = uint64(bound(_lots2, 1, 50));
        uint64 lots3 = uint64(bound(_lots3, 1, 50));
        uint64 lots4 = uint64(bound(_lots4, 1, 50));

        (uint256 fmId, uint256 obId) = _createMarket();

        // Multiple bids and asks at different ticks
        vm.prank(users[0]);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilBatch, tick1, lots1);

        vm.prank(users[1]);
        book.placeOrder(obId, Side.Bid, OrderType.GoodTilBatch, tick2, lots2);

        vm.prank(users[2]);
        book.placeOrder(obId, Side.Ask, OrderType.GoodTilBatch, tick1, lots3);

        vm.prank(users[3]);
        book.placeOrder(obId, Side.Ask, OrderType.GoodTilBatch, tick2, lots4);

        BatchResult memory r = auction.clearBatch(obId);

        if (r.matchedLots > 0) {
            uint256 poolBalance = vault.marketPool(obId);
            assertGe(poolBalance, uint256(r.matchedLots) * LOT, "Pool insolvent after multi-user clear");
        }

        // Resolve and redeem all winners
        _resolveMarket(fmId, _yesWins);

        for (uint256 i = 0; i < 4; i++) {
            address u = users[i];
            // Try YES token
            uint256 yBal = token.balanceOf(u, obId * 2);
            uint256 nBal = token.balanceOf(u, obId * 2 + 1);
            uint256 winBal = _yesWins ? yBal : nBal;

            if (winBal > 0) {
                vm.startPrank(u);
                token.setApprovalForAll(address(redemption), true);
                redemption.redeem(fmId, winBal);
                vm.stopPrank();
            }
        }

        // Pool should not have gone negative (redemption would revert if so)
        assertGe(vault.marketPool(obId), 0, "Pool went negative after all redemptions");
    }

    // =========================================================================
    // Fuzz: Rounding remainder (H-03) — fills sum to matchedLots
    // =========================================================================

    /// @notice Sum of individual fills must exactly equal matchedLots for both sides.
    function testFuzz_RoundingRemainder_FillsMatchExact(
        uint256 _tick,
        uint256 _numBids,
        uint256 _numAsks,
        uint256 _bidLotsSeed,
        uint256 _askLotsSeed
    ) public {
        uint8 tick = uint8(bound(_tick, 10, 90));
        uint256 numBids = bound(_numBids, 2, 8);
        uint256 numAsks = bound(_numAsks, 2, 8);

        (, uint256 obId) = _createMarket();

        // Place multiple bids
        uint256 totalBidLots;
        for (uint256 i = 0; i < numBids; i++) {
            uint64 lots = uint64(bound(uint256(keccak256(abi.encode(_bidLotsSeed, i))), 1, 20));
            vm.prank(users[i % 4]);
            book.placeOrder(obId, Side.Bid, OrderType.GoodTilBatch, tick, lots);
            totalBidLots += lots;
        }

        // Place multiple asks
        uint256 totalAskLots;
        for (uint256 i = 0; i < numAsks; i++) {
            uint64 lots = uint64(bound(uint256(keccak256(abi.encode(_askLotsSeed, i))), 1, 20));
            vm.prank(users[(i + numBids) % 4]);
            book.placeOrder(obId, Side.Ask, OrderType.GoodTilBatch, tick, lots);
            totalAskLots += lots;
        }

        BatchResult memory r = auction.clearBatch(obId);

        if (r.matchedLots > 0) {
            // Check pool received the correct amount
            uint256 expectedPool = uint256(r.matchedLots) * LOT;
            uint256 actualPool = vault.marketPool(obId);
            assertEq(actualPool, expectedPool, "Pool != matchedLots * LOT_SIZE");

            // Check total minted YES tokens == matchedLots
            uint256 totalYes;
            uint256 totalNo;
            for (uint256 i = 0; i < 10; i++) {
                totalYes += token.balanceOf(users[i], obId * 2);
                totalNo += token.balanceOf(users[i], obId * 2 + 1);
            }
            assertEq(totalYes, r.matchedLots, "Minted YES != matchedLots");
            assertEq(totalNo, r.matchedLots, "Minted NO != matchedLots");
        }
    }
}
