# Strike Duels Wager Contract

## Contract

`StrikeDuelsWagerVault` is the v1 escrow for server-authoritative Strike Duels wagers on BNB Chain.

It supports two isolated wager modes:

- **PvP native BNB:** both players deposit the same enabled BNB bracket. The winner receives the pool minus protocol fee. Draw/no-contest refunds both players. If a native transfer recipient rejects BNB, the payout is held as a claimable pending withdrawal instead of blocking settlement.
- **AI `$STRIKE` pool:** player deposits the fixed AI stake in `$STRIKE`. If the player beats the server-authoritative AI, the player receives their stake back and the fixed reward becomes claimable from the treasury-funded reward pool. If AI wins/forfeit, the player stake remains in the pool. Draw/no-contest refunds the player stake.

The contract does **not** decide gameplay results. Only an address with `SETTLER_ROLE` can finalize a wager with a server-authored result and match-summary hash.

## Roles

- `DEFAULT_ADMIN_ROLE`: bootstrap/admin role; can grant/revoke roles.
- `SETTLER_ROLE`: can call `finalizeWager` and `refundWager`.
- `PAUSER_ROLE`: can pause/unpause create/join/finalize/refund flows.
- `TREASURY_ROLE`: can update treasury, caps, fee bps, PvP brackets, AI fixed amounts, and recover only unreserved surplus assets.

## Constructor

```solidity
constructor(
    address strikeToken,
    address admin,
    address treasury,
    address settler,
    uint256 aiStakeAmount,
    uint256 aiWinRewardAmount,
    uint16 pvpFeeBps,
    uint256 maxPvpStakeAmount,
    uint256 maxAiRewardExposure
)
```

Recommended v1 defaults:

- `strikeToken`: `0xDccC017B0F923Cf3F3ACDB535eb1019439717777` on BNB Chain.
- `aiStakeAmount`: `20_000e18`.
- `aiWinRewardAmount`: `20_000e18`.
- `pvpFeeBps`: `500` (5% of total PvP pool).
- Initial PvP brackets: disabled by default for V1. The deploy script only enables the `0.001 ether` and `0.01 ether` brackets when `DUELS_ENABLE_PVP_BRACKETS=true` is explicitly set.

## Public user functions

```solidity
function createPvpWager(bytes32 wagerId, address opponent) external payable;
function joinPvpWager(bytes32 wagerId) external payable;
function createAiWager(bytes32 wagerId, bytes32 aiConfigHash) external;
```

### PvP

- `wagerId` must be unused.
- `msg.value` must exactly match an enabled PvP bracket.
- `msg.value <= maxPvpStakeAmount`.
- `opponent` can be a specific wallet or `address(0)` for open challenge.
- The creator cannot join their own PvP wager.
- If opponent is non-zero, only that opponent can join.

### AI

- `wagerId` must be unused.
- The player transfers exactly `aiStakeAmount` `$STRIKE` via `safeTransferFrom`.
- The vault must have enough unreserved pool liquidity for `aiWinRewardAmount` before accepting the wager.
- Open AI reward exposure must remain `<= maxAiRewardExposure`.

## Settlement functions

```solidity
enum Result {
    PlayerAWins,
    PlayerBWins,
    DrawNoContest
}

function finalizeWager(bytes32 wagerId, Result result, bytes32 matchSummaryHash) external;
function refundWager(bytes32 wagerId, bytes32 reason) external;
function claimNativePayout() external;
function claimNativePayoutTo(address payable to) external;
function claimAiReward() external;
```

- Only `SETTLER_ROLE` can settle/refund.
- Settlement is idempotent by state: finalized/refunded wagers cannot be finalized/refunded again.
- `matchSummaryHash` should be the backend's canonical hash of the final server-authored `MatchSummary`.
- PvP:
  - `PlayerAWins`: creator receives pool minus fee.
  - `PlayerBWins`: joiner receives pool minus fee.
  - `DrawNoContest`: both players are refunded their stakes.
  - If a native payout transfer fails, the amount is recorded in `pendingNativeWithdrawals(recipient)` and can later be pulled with `claimNativePayout()`.
  - Recipients that permanently reject BNB can call `claimNativePayoutTo(to)` to withdraw their pending payout to an alternate payable address.
- AI:
  - `PlayerAWins`: player receives `aiStakeAmount`; `aiWinRewardAmount` is credited to `pendingAiRewards(player)` and can be pulled with `claimAiReward()`.
  - `PlayerBWins`: player's stake remains in reward pool.
  - `DrawNoContest`: player receives `aiStakeAmount` refund.

## Admin functions

```solidity
function setPvpBracket(uint256 amount, bool enabled) external;
function setPvpFeeBps(uint16 feeBps) external;
function setTreasury(address treasury) external;
function setCaps(uint256 maxPvpStakeAmount, uint256 maxAiRewardExposure) external;
function setAiPrize(uint256 stakeAmount, uint256 winRewardAmount) external;
function pause() external;
function unpause() external;
function recoverNativeSurplus(address to, uint256 amount) external;
function recoverERC20(address token, address to, uint256 amount) external;
```

Recovery is treasury-only and cannot withdraw active escrow or claimable rewards:

- Native recovery excludes open PvP stake escrow plus pending native withdrawals.
- `$STRIKE` recovery excludes open AI reward exposure, refundable open AI player stakes, and finalized claimable AI rewards.
- Unrelated ERC20 recovery can rescue accidental token transfers to the vault.

## Events

```solidity
event PvpWagerCreated(bytes32 indexed wagerId, address indexed creator, address indexed opponent, uint256 stakeAmount);
event PvpWagerJoined(bytes32 indexed wagerId, address indexed joiner);
event AiWagerCreated(bytes32 indexed wagerId, address indexed player, bytes32 aiConfigHash, uint256 stakeAmount, uint256 winRewardAmount);
event WagerFinalized(bytes32 indexed wagerId, Result result, bytes32 matchSummaryHash, address indexed payoutRecipient, uint256 payoutAmount, uint256 feeAmount);
event WagerRefunded(bytes32 indexed wagerId, bytes32 reason);
event TreasuryUpdated(address indexed treasury);
event CapsUpdated(uint256 maxPvpStakeAmount, uint256 maxAiRewardExposure);
event PvpBracketUpdated(uint256 amount, bool enabled);
event AiPrizeUpdated(uint256 stakeAmount, uint256 winRewardAmount);
event PvpFeeUpdated(uint16 feeBps);
event NativeSurplusRecovered(address indexed to, uint256 amount);
event ERC20Recovered(address indexed token, address indexed to, uint256 amount);
event NativePayoutPending(address indexed recipient, uint256 amount);
event NativePayoutClaimed(address indexed recipient, uint256 amount);
event AiRewardClaimable(bytes32 indexed wagerId, address indexed recipient, uint256 amount);
event AiRewardClaimed(address indexed recipient, uint256 amount);
```

## Deployment / ABI prep

Dry-run command:

```bash
cd /home/ubuntu/dev/strike/contracts
DEPLOYER_PRIVATE_KEY=<dry-run-key> \
forge script script/DeployStrikeDuelsWagerVault.s.sol --rpc-url $RPC_URL
```

Broadcast command (approval-required):

```bash
cd /home/ubuntu/dev/strike/contracts
DEPLOYER_PRIVATE_KEY=<approved-deployer-key> \
DUELS_WAGER_ADMIN=<final-admin> \
DUELS_WAGER_TREASURY=<treasury> \
DUELS_WAGER_SETTLER=<settler> \
DUELS_ENABLE_PVP_BRACKETS=false \
forge script script/DeployStrikeDuelsWagerVault.s.sol --rpc-url $RPC_URL --broadcast --verify
```

ABI export after build:

```bash
jq '.abi' out/StrikeDuelsWagerVault.sol/StrikeDuelsWagerVault.json \
  > /home/ubuntu/dev/strike-frontend/src/lib/abi/StrikeDuelsWagerVault.json
```

## Safety notes

- Wager mode remains disabled in product/backend config until legal/product approval.
- PvP brackets remain disabled in the V1 deploy script unless `DUELS_ENABLE_PVP_BRACKETS=true` is explicitly set.
- Deployment/broadcast requires explicit approval. Scripts are dry-run-first.
- The contract has no geoblock; any jurisdiction gate must live in product/backend configuration for v1.
- Treasury recovery functions are for accidental/surplus balances only and preserve open PvP escrow, pending native payouts, open AI reward exposure, open AI player stakes, and claimable AI rewards.
