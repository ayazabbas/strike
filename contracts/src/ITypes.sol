// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// ITypes — Shared types for the Strike CLOB protocol.

// Size of one lot in collateral token units (1 USDT = 1e18).
uint256 constant LOT_SIZE = 1e18;

/// @notice Side of an order in a binary outcome market.
enum Side {
    Bid, // buying YES outcome (willing to pay tick/100)
    Ask  // selling YES outcome (willing to accept tick/100)
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
    address owner;       // 20 bytes — order placer
    Side side;           // 1 byte  — Bid or Ask
    OrderType orderType; // 1 byte  — GTC or GTB
    uint8 tick;          // 1 byte  — price tick 1-99 (price = tick/100)
    uint64 lots;         // 8 bytes — remaining lots (each lot = 1 USDT = 1e18)
    // --- Slot 2 (21 bytes) ---
    uint64 id;           // 8 bytes — unique order ID
    uint32 marketId;     // 4 bytes — market this order belongs to
    uint32 batchId;      // 4 bytes — batch ID when order was placed
    uint40 timestamp;    // 5 bytes — block.timestamp when placed
}

/// @notice Result of a batch auction clearing.
///         Packed into 2 storage slots (was 7).
struct BatchResult {
    // --- Slot 1 (17 bytes) ---
    uint32 marketId;     // 4 bytes — market that was cleared
    uint32 batchId;      // 4 bytes — sequential batch number
    uint8 clearingTick;  // 1 byte  — clearing price tick (0 = no cross)
    uint64 matchedLots;  // 8 bytes — total lots matched at clearing tick
    // --- Slot 2 (21 bytes) ---
    uint64 totalBidLots; // 8 bytes — cumulative bid lots at clearing tick
    uint64 totalAskLots; // 8 bytes — cumulative ask lots at clearing tick
    uint40 timestamp;    // 5 bytes — block.timestamp of clearing
}

/// @notice Market lifecycle states.
enum MarketState {
    Open,      // orders accepted, batches clear
    Closed,    // no new orders, final batch clears
    Resolving, // resolution submitted, finality pending
    Resolved,  // outcome set, redemption open
    Cancelled  // no resolution within 24h → refunds
}

/// @notice Market descriptor stored in OrderBook.
///         Packed into 1 storage slot (was 6).
struct Market {
    uint32 id;             // 4 bytes — market ID
    bool active;           // 1 byte  — true if trading is open
    bool halted;           // 1 byte  — true if temporarily halted
    uint32 currentBatchId; // 4 bytes — current batch counter
    uint32 minLots;        // 4 bytes — minimum order size in lots
    uint32 batchInterval;  // 4 bytes — seconds between batch auctions
    uint40 expiryTime;     // 5 bytes — timestamp when market expires
}
