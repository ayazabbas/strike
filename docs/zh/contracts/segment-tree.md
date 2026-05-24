# SegmentTree.sol

Pure Solidity library，用固定大小的线段树表示 99 个价格 tick（1--99）。`OrderBook` 在内部使用它跟踪每个 tick 的 bid/ask volume，并为 Frequent Batch Auctions 计算最优清算价格。

## Layout

该树由一个 `uint256[256]` array（`Tree.nodes`）表示，采用 1-indexed 布局：

```
               nodes[1] = root (total volume)
              /                              \
        nodes[2]                          nodes[3]
       /        \                        /        \
    nodes[4]  nodes[5]  ...          ...       nodes[7]
     ...                                          ...
  nodes[128] nodes[129] ... nodes[226]  nodes[227] ... nodes[255]
    tick 1     tick 2        tick 99     (unused padding)
```

- **Leaves:** indices 128--226（tick `i` 映射至 leaf index `127 + i`）。
- **Internal nodes:** indices 1--127。
- **Root:** `nodes[1]` 存储所有 tick 的总 volume。
- **Unused:** leaf indices 227--255 为 padding（大于等于 99 的下一个 2 的幂是 128）。

每个节点都存储其 subtree 的总 volume。

## Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `LEAVES` | 128 | Next power-of-2 >= 99 |
| `SIZE` | 256 | Array length (2 * LEAVES, 1-indexed) |
| `MAX_TICK` | 99 | 最大有效 tick |

## 存储 Struct

```solidity
struct Tree {
    uint256[256] nodes;
}
```

## 函数

所有操作都是 **O(log 128) = O(7)** 次 storage reads/writes。

### update

```solidity
function update(Tree storage tree, uint256 tick, int256 delta) internal
```

为指定 tick 添加或移除 volume。`delta` 为 signed: 正数表示增加 volume，负数表示移除 volume。函数会从 leaf 向上走向 root，并更新每个 ancestor node。

- 如果 `tick` 不在 [1, 99] 内，则 revert。
- 如果发生 underflow（移除的 volume 超过某个节点现有 volume），则 revert。

### prefixSum

```solidity
function prefixSum(Tree storage tree, uint256 tick) internal view returns (uint256 sum)
```

返回 ticks [1, tick]（含两端）的累计 volume。该函数在线段树上执行标准 recursive range query。

- 如果 `tick` 不在 [1, 99] 内，则 revert。

### findClearingTick

```solidity
function findClearingTick(
    Tree storage bidTree,
    Tree storage askTree
) internal view returns (uint256 clearingTick)
```

对于 Frequent Batch Auction，通过 binary search 查找最优清算 tick。算法如下：

1. **tick p 处的累计 bid:** ticks >= p 的总 bid volume（bid 愿意支付至少 p）。计算方式为 `totalBidVolume - prefixSum(bidTree, p-1)`。
2. **tick p 处的累计 ask:** ticks <= p 的总 ask volume（ask 愿意以至多 p 卖出）。计算方式为 `prefixSum(askTree, p)`。
3. **Clearing tick:** [1, 99] 中满足 `cumBid(p) >= cumAsk(p)` 的最高 `p`。
4. **Tie-break 校正:** 找出 candidate 后，检查 `p+1`，并选择能够最大化 matched volume（`min(cumBid, cumAsk)`）的 tick。

如果没有 crossing（没有有效清算 tick），则返回 0。

### totalVolume

```solidity
function totalVolume(Tree storage tree) internal view returns (uint256)
```

返回 root node 的值，即所有 tick 中存储的总 volume。这是一次 O(1) read。

### volumeAt

```solidity
function volumeAt(Tree storage tree, uint256 tick) internal view returns (uint256)
```

返回指定 tick 的 volume（leaf value）。这是一次 O(1) read。

- 如果 `tick` 不在 [1, 99] 内，则 revert。

## 在订单簿中的用法

`OrderBook` 为每个市场维护两棵线段树：

- `bidTrees[marketId]` -- 跟踪每个 tick 的 bid volume。
- `askTrees[marketId]` -- 跟踪每个 tick 的 ask volume。

当订单以 tick `t` 和 `n` lots 提交时，系统调用 `update(tree, t, int256(n))`。取消订单时，调用 `update(tree, t, -int256(n))`。清算时调用 `findClearingTick(bidTrees[id], askTrees[id])`。
