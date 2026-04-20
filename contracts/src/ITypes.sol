// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// ITypes — Shared types for the Strike CLOB protocol.

// Size of one lot in collateral token units (0.01 USDT = 1e16).
uint256 constant LOT_SIZE = 1e16;

/// @notice Side of an order in a binary outcome market.
enum Side {
    Bid, // buy YES: lock tick/100 * LOT_SIZE USDT → receive YES tokens at fill
    Ask, // buy NO:  lock (100-tick)/100 * LOT_SIZE USDT → receive NO tokens at fill
    SellYes, // sell YES tokens: lock YES tokens → receive tick/100 * LOT_SIZE USDT at fill
    SellNo // sell NO tokens:  lock NO tokens → receive (100-tick)/100 * LOT_SIZE USDT at fill
}

/// @notice Order type classification.
enum OrderType {
    GoodTilBatch, // lives for one batch auction, then expires
    GoodTilCancel // persists until filled or cancelled
}

/// @notice An order in the order book.
///         Packed into 2 storage slots (was 7).
struct Order {
    // --- Slot 1 (31 bytes) ---
    address owner; // 20 bytes — order placer
    Side side; // 1 byte  — Bid or Ask
    OrderType orderType; // 1 byte  — GTC or GTB
    uint8 tick; // 1 byte  — price tick 1-99 (price = tick/100)
    uint64 lots; // 8 bytes — remaining lots (each lot = 0.01 USDT = 1e16)
    // --- Slot 2 (23 bytes) ---
    uint64 id; // 8 bytes — unique order ID
    uint32 marketId; // 4 bytes — market this order belongs to
    uint32 batchId; // 4 bytes — batch ID when order was placed
    uint40 timestamp; // 5 bytes — block.timestamp when placed
    uint16 feeBps; // 2 bytes — feeBps at order placement (for locked calc)
}

/// @notice Result of a batch auction clearing.
///         Packed into 2 storage slots (was 7).
struct BatchResult {
    // --- Slot 1 (17 bytes) ---
    uint32 marketId; // 4 bytes — market that was cleared
    uint32 batchId; // 4 bytes — sequential batch number
    uint8 clearingTick; // 1 byte  — clearing price tick (0 = no cross)
    uint64 matchedLots; // 8 bytes — total lots matched at clearing tick
    // --- Slot 2 (21 bytes) ---
    uint64 totalBidLots; // 8 bytes — cumulative bid lots at clearing tick
    uint64 totalAskLots; // 8 bytes — cumulative ask lots at clearing tick
    uint40 timestamp; // 5 bytes — block.timestamp of clearing
}

/// @notice Parameters for batch order placement.
struct OrderParam {
    Side side;
    OrderType orderType;
    uint8 tick;
    uint64 lots;
}

/// @notice Parameters for in-place order amendment.
struct AmendOrderParam {
    uint256 orderId;
    uint8 newTick;
    uint64 newLots;
}

/// @notice Market lifecycle states.
enum MarketState {
    Open, // orders accepted, batches clear
    Closed, // no new orders, final batch clears
    Resolving, // resolution submitted, finality pending
    Resolved, // outcome set, redemption open
    Cancelled // no resolution within 24h → refunds
}

/// @notice Market descriptor stored in OrderBook.
///         Packed into 1 storage slot (24 bytes).
struct Market {
    uint32 id; // 4 bytes — market ID
    bool active; // 1 byte  — true if trading is open
    bool halted; // 1 byte  — true if temporarily halted
    uint32 currentBatchId; // 4 bytes — current batch counter
    uint32 minLots; // 4 bytes — minimum order size in lots
    uint32 batchInterval; // 4 bytes — seconds between batch auctions
    uint40 expiryTime; // 5 bytes — timestamp when market expires
    bool useInternalPositions; // 1 byte — true = internal positions, false = ERC1155
}
