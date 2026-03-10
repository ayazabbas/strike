#!/bin/bash
# Strike Gas Report — measures gas for all user/keeper functions on local devnet
set -euo pipefail

export PATH="$HOME/.foundry/bin:$PATH"
RPC=http://localhost:8545

# Anvil accounts
DEPLOYER_PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
DEPLOYER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
TRADER_A_PK=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
TRADER_A=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
TRADER_B_PK=0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6
TRADER_B=0x90F79bf6EB2c4f870365E785982E1f101E93b906

# Contract addresses (verified against running devnet)
VAULT=0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
ORDERBOOK=0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9
BATCH=0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9
FACTORY=0x0165878A594ca255338adfa4d48449f69242Eb8F
RESOLVER=0xa513E6E4b8f2a923D98304ec87F64353C4D5C853
REDEMPTION=0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6
OUTCOME=0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512

# Helper: send a tx and extract gasUsed from cast output
send_gas() {
    local output
    output=$(cast send "$@" --rpc-url $RPC 2>&1)
    local status
    status=$(echo "$output" | grep "^status" | awk '{print $2}')
    if [ "$status" = "0" ]; then
        echo "REVERTED"
        echo "$output" >&2
        return 1
    fi
    echo "$output" | grep "^gasUsed" | awk '{print $2}'
}

# BNB price assumption for USD cost
BNB_USD=600

results=()
record() {
    local name=$1
    local gas=$2
    local cost_usd=$(echo "scale=6; $gas * 1 * $BNB_USD / 1000000000" | bc)
    results+=("$name|$gas|$cost_usd")
    printf "  %-50s %10s gas  \$%s\n" "$name" "$gas" "$cost_usd"
}

echo "=== Strike Protocol Gas Report ==="
echo "Network: Anvil (local devnet)"
echo "Gas price assumption: 1 gwei (BNB Chain typical)"
echo "BNB price assumption: \$$BNB_USD"
echo ""

# ─── 1. Vault Operations ───
echo "── Vault ──"

GAS=$(send_gas $VAULT "deposit()" --value 5ether --private-key $TRADER_A_PK)
record "Vault.deposit (5 BNB)" $GAS

GAS=$(send_gas $VAULT "deposit()" --value 5ether --private-key $TRADER_B_PK)
record "Vault.deposit (Trader B, 5 BNB)" $GAS

GAS=$(send_gas $VAULT "withdraw(uint256)" 100000000000000000 --private-key $TRADER_A_PK)
record "Vault.withdraw (0.1 BNB)" $GAS

echo ""

# ─── 2. Market Creation ───
echo "── Market Creation ──"

BOND=$(cast call $FACTORY "creationBond()(uint256)" --rpc-url $RPC | awk '{print $1}')

GAS=$(send_gas $FACTORY "createMarket(bytes32,int64,uint256,uint256,uint128)" \
    0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace \
    5000000000000 \
    7200 \
    60 \
    1 \
    --value $BOND --private-key $DEPLOYER_PK)
record "MarketFactory.createMarket" $GAS

# Get the new orderbook market ID
NEXT_OB=$(cast call $ORDERBOOK "nextMarketId()(uint256)" --rpc-url $RPC | awk "{print \$1}")
NEW_MKT=$((NEXT_OB - 1))
echo "  (Using OrderBook market ID: $NEW_MKT)"

echo ""

# ─── 3. Order Placement ───
echo "── Order Placement ──"

# BID GTC at tick 60, 10 lots
GAS=$(send_gas $ORDERBOOK "placeOrder(uint256,uint8,uint8,uint256,uint256)" \
    $NEW_MKT 0 1 60 10 --private-key $TRADER_A_PK)
record "placeOrder (BID GTC, tick 60, 10 lots)" $GAS

# Get order ID
NEXT_ORD=$(cast call $ORDERBOOK "nextOrderId()(uint256)" --rpc-url $RPC | awk "{print \$1}")
ORDER_BID60=$((NEXT_ORD - 1))

# BID GTC at tick 55, 20 lots
GAS=$(send_gas $ORDERBOOK "placeOrder(uint256,uint8,uint8,uint256,uint256)" \
    $NEW_MKT 0 1 55 20 --private-key $TRADER_A_PK)
record "placeOrder (BID GTC, tick 55, 20 lots)" $GAS
NEXT_ORD=$(cast call $ORDERBOOK "nextOrderId()(uint256)" --rpc-url $RPC | awk "{print \$1}")
ORDER_BID55=$((NEXT_ORD - 1))

# BID GTB at tick 50, 5 lots
GAS=$(send_gas $ORDERBOOK "placeOrder(uint256,uint8,uint8,uint256,uint256)" \
    $NEW_MKT 0 0 50 5 --private-key $TRADER_A_PK)
record "placeOrder (BID GTB, tick 50, 5 lots)" $GAS
NEXT_ORD=$(cast call $ORDERBOOK "nextOrderId()(uint256)" --rpc-url $RPC | awk "{print \$1}")
ORDER_GTB=$((NEXT_ORD - 1))

# ASK GTC at tick 60, 10 lots — crosses with bid at 60
GAS=$(send_gas $ORDERBOOK "placeOrder(uint256,uint8,uint8,uint256,uint256)" \
    $NEW_MKT 1 1 60 10 --private-key $TRADER_B_PK)
record "placeOrder (ASK GTC, tick 60, 10 lots)" $GAS
NEXT_ORD=$(cast call $ORDERBOOK "nextOrderId()(uint256)" --rpc-url $RPC | awk "{print \$1}")
ORDER_ASK60=$((NEXT_ORD - 1))

# ASK GTC at tick 65, 15 lots — won't cross
GAS=$(send_gas $ORDERBOOK "placeOrder(uint256,uint8,uint8,uint256,uint256)" \
    $NEW_MKT 1 1 65 15 --private-key $TRADER_B_PK)
record "placeOrder (ASK GTC, tick 65, 15 lots)" $GAS
NEXT_ORD=$(cast call $ORDERBOOK "nextOrderId()(uint256)" --rpc-url $RPC | awk "{print \$1}")
ORDER_ASK65=$((NEXT_ORD - 1))

echo ""

# ─── 4. Cancel Order ───
echo "── Cancel ──"

GAS=$(send_gas $ORDERBOOK "cancelOrder(uint256)" $ORDER_ASK65 --private-key $TRADER_B_PK)
record "cancelOrder (GTC, 15 lots)" $GAS

echo ""

# ─── 5. Batch Clearing ───
echo "── Batch Clearing ──"

# Advance time past batch interval
cast rpc evm_increaseTime 61 --rpc-url $RPC > /dev/null 2>&1
cast rpc evm_mine --rpc-url $RPC > /dev/null 2>&1

GAS=$(send_gas $BATCH "clearBatch(uint256)" $NEW_MKT --private-key $DEPLOYER_PK)
record "clearBatch (4 orders, 2 crossing at tick 60)" $GAS

echo ""

# ─── 6. Claim Fills ───
echo "── Claim Fills ──"

GAS=$(send_gas $BATCH "claimFills(uint256)" $ORDER_BID60 --private-key $TRADER_A_PK)
record "claimFills (BID full fill, mints YES tokens)" $GAS

GAS=$(send_gas $BATCH "claimFills(uint256)" $ORDER_ASK60 --private-key $TRADER_B_PK)
record "claimFills (ASK full fill, mints NO tokens)" $GAS

GAS=$(send_gas $BATCH "claimFills(uint256)" $ORDER_BID55 --private-key $TRADER_A_PK)
record "claimFills (no fill — tick below clearing)" $GAS

echo ""

# ─── 7. Prune Expired GTB ───
echo "── Prune ──"

# Need another batch clear for GTB to be expired
cast rpc evm_increaseTime 61 --rpc-url $RPC > /dev/null 2>&1
cast rpc evm_mine --rpc-url $RPC > /dev/null 2>&1
send_gas $BATCH "clearBatch(uint256)" $NEW_MKT --private-key $DEPLOYER_PK > /dev/null

GAS=$(send_gas $BATCH "pruneExpiredOrder(uint256)" $ORDER_GTB --private-key $DEPLOYER_PK)
record "pruneExpiredOrder (GTB, 5 lots)" $GAS

echo ""

# ─── 8. Market Resolution (if we can) ───
echo "── Resolution ──"

# Close the market first (advance to expiry)
cast rpc evm_increaseTime 7200 --rpc-url $RPC > /dev/null 2>&1
cast rpc evm_mine --rpc-url $RPC > /dev/null 2>&1

# Get the factory market ID for this OB market
FACTORY_MKT_COUNT=$(cast call $FACTORY "nextFactoryMarketId()(uint256)" --rpc-url $RPC | awk "{print \$1}")
FACTORY_MKT=$((FACTORY_MKT_COUNT - 1))

GAS=$(send_gas $FACTORY "closeMarket(uint256)" $FACTORY_MKT --private-key $DEPLOYER_PK)
record "closeMarket" $GAS

echo ""

# ─── Summary Table ───
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
printf "  %-50s %10s %12s\n" "Function" "Gas" "USD @1gwei"
echo "───────────────────────────────────────────────────────────────────────────"
for r in "${results[@]}"; do
    IFS='|' read -r name gas cost <<< "$r"
    printf "  %-50s %10s  \$%s\n" "$name" "$gas" "$cost"
done
echo "═══════════════════════════════════════════════════════════════════════════"

echo ""
echo "Notes:"
echo "  - Gas price: 1 gwei (BNB Chain average, can spike to 3-5 gwei)"
echo "  - BNB: \$$BNB_USD"
echo "  - Inline settlement would combine clearBatch + N×claimFills into one tx"
echo "  - Keeper cost per batch = clearBatch + (N × claimFills) under current design"
echo "  - With inline settlement: keeper cost = just the combined clearBatch tx"
