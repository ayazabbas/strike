/**
 * Strike Integration Test
 *
 * Tests the full on-chain flow against a local Anvil devnet:
 * 1. Deploy MockPyth oracle
 * 2. Deploy MarketFactory
 * 3. Create a BTC/USD market
 * 4. Place UP bet from account1, DOWN bet from account2
 * 5. Fast-forward time past expiry
 * 6. Resolve market with higher price (UP wins)
 * 7. Claim winnings for account1
 * 8. Verify refund not available for loser
 *
 * Run: npx tsx bot/test/integration.ts
 * Requires: anvil running on http://127.0.0.1:8545
 */

import {
  createPublicClient,
  createWalletClient,
  http,
  parseEther,
  formatEther,
  getAddress,
  type Address,
  type Hex,
  type Chain,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { foundry } from "viem/chains";
import { readFileSync } from "fs";
import { resolve } from "path";

// ─── Anvil default accounts ─────────────────────────────────────────────────
const DEPLOYER_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as Hex;
const BETTOR1_KEY = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d" as Hex;
const BETTOR2_KEY = "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a" as Hex;

const deployer = privateKeyToAccount(DEPLOYER_KEY);
const bettor1 = privateKeyToAccount(BETTOR1_KEY);
const bettor2 = privateKeyToAccount(BETTOR2_KEY);

const RPC_URL = "http://127.0.0.1:8545";

// ─── Load compiled artifacts ─────────────────────────────────────────────────
function loadArtifact(name: string) {
  const contractsDir = resolve(import.meta.dirname || __dirname, "../../contracts");
  const raw = readFileSync(`${contractsDir}/out/${name}.sol/${name}.json`, "utf8");
  const artifact = JSON.parse(raw);
  return {
    abi: artifact.abi,
    bytecode: artifact.bytecode.object as Hex,
  };
}

const MockPythArtifact = loadArtifact("MockPyth");
const MarketFactoryArtifact = loadArtifact("MarketFactory");
const MarketArtifact = loadArtifact("Market");

// ─── Clients ─────────────────────────────────────────────────────────────────
const publicClient = createPublicClient({ chain: foundry, transport: http(RPC_URL) });
const deployerClient = createWalletClient({ account: deployer, chain: foundry, transport: http(RPC_URL) });
const bettor1Client = createWalletClient({ account: bettor1, chain: foundry, transport: http(RPC_URL) });
const bettor2Client = createWalletClient({ account: bettor2, chain: foundry, transport: http(RPC_URL) });

// ─── Constants ───────────────────────────────────────────────────────────────
const BTC_USD_FEED = "0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43" as Hex;
const MARKET_DURATION = 300; // 5 minutes
const STRIKE_PRICE = 50000_00000000n; // $50,000 with 8 decimals
const RESOLUTION_PRICE = 51000_00000000n; // $51,000 — UP wins
const PRICE_EXPO = -8;

// ─── Helpers ─────────────────────────────────────────────────────────────────
let passCount = 0;
let failCount = 0;

function assert(condition: boolean, message: string) {
  if (condition) {
    console.log(`  ✅ ${message}`);
    passCount++;
  } else {
    console.log(`  ❌ FAIL: ${message}`);
    failCount++;
  }
}

async function getBlockTimestamp(): Promise<bigint> {
  const block = await publicClient.getBlock();
  return block.timestamp;
}

async function increaseTime(seconds: number) {
  await publicClient.request({ method: "evm_increaseTime" as any, params: [seconds] });
  await publicClient.request({ method: "evm_mine" as any, params: [] });
}

async function createPriceFeedData(
  mockPyth: Address,
  price: bigint,
  timestamp: bigint,
): Promise<Hex> {
  const data = await publicClient.readContract({
    address: mockPyth,
    abi: MockPythArtifact.abi,
    functionName: "createPriceFeedUpdateData",
    args: [
      BTC_USD_FEED,
      price,        // price
      10n,          // conf
      PRICE_EXPO,   // expo
      price,        // emaPrice
      10n,          // emaConf
      timestamp,    // publishTime
      timestamp - 1n, // prevPublishTime
    ],
  });
  return data as Hex;
}

// ─── Main Test ───────────────────────────────────────────────────────────────
async function main() {
  console.log("\n⚡ Strike Integration Tests\n");
  console.log("═══════════════════════════════════════════════════════\n");

  // ── Step 1: Deploy MockPyth ──────────────────────────────────────────────
  console.log("📋 Step 1: Deploy MockPyth oracle");

  const mockPythHash = await deployerClient.deployContract({
    abi: MockPythArtifact.abi,
    bytecode: MockPythArtifact.bytecode,
    args: [60n, 1n], // validTimePeriod=60s, singleUpdateFee=1wei
  });
  const mockPythReceipt = await publicClient.waitForTransactionReceipt({ hash: mockPythHash });
  const mockPyth = mockPythReceipt.contractAddress!;
  assert(!!mockPyth, `MockPyth deployed at ${mockPyth}`);

  // ── Step 2: Deploy MarketFactory ─────────────────────────────────────────
  console.log("\n📋 Step 2: Deploy MarketFactory");

  const factoryHash = await deployerClient.deployContract({
    abi: MarketFactoryArtifact.abi,
    bytecode: MarketFactoryArtifact.bytecode,
    args: [mockPyth, deployer.address], // pyth, feeCollector
  });
  const factoryReceipt = await publicClient.waitForTransactionReceipt({ hash: factoryHash });
  const factory = factoryReceipt.contractAddress!;
  assert(!!factory, `MarketFactory deployed at ${factory}`);

  // Verify factory state
  const pythAddr = await publicClient.readContract({
    address: factory,
    abi: MarketFactoryArtifact.abi,
    functionName: "pyth",
  });
  assert(getAddress(pythAddr as string) === getAddress(mockPyth), "Factory pyth address matches");

  // ── Step 3: Create market ────────────────────────────────────────────────
  console.log("\n📋 Step 3: Create BTC/USD market (5 min duration)");

  const now = await getBlockTimestamp();
  const strikeUpdateData = await createPriceFeedData(mockPyth, STRIKE_PRICE, now);

  // Get Pyth update fee
  const updateFee = await publicClient.readContract({
    address: mockPyth,
    abi: MockPythArtifact.abi,
    functionName: "getUpdateFee",
    args: [[strikeUpdateData]],
  });

  const createHash = await deployerClient.writeContract({
    address: factory,
    abi: MarketFactoryArtifact.abi,
    functionName: "createMarket",
    args: [BTC_USD_FEED, BigInt(MARKET_DURATION), [strikeUpdateData]],
    value: updateFee as bigint,
  });
  const createReceipt = await publicClient.waitForTransactionReceipt({ hash: createHash });
  assert(createReceipt.status === "success", "Market creation tx succeeded");

  // Get market address from factory
  const marketCount = await publicClient.readContract({
    address: factory,
    abi: MarketFactoryArtifact.abi,
    functionName: "getMarketCount",
  });
  assert((marketCount as bigint) === 1n, "Factory has 1 market");

  const markets = await publicClient.readContract({
    address: factory,
    abi: MarketFactoryArtifact.abi,
    functionName: "getMarkets",
    args: [0n, 1n],
  });
  const market = (markets as Address[])[0];
  console.log(`  📍 Market address: ${market}`);

  // Verify market state
  const marketState = await publicClient.readContract({
    address: market,
    abi: MarketArtifact.abi,
    functionName: "state",
  });
  assert(Number(marketState) === 0, "Market state is Open (0)");

  const strikeOnChain = await publicClient.readContract({
    address: market,
    abi: MarketArtifact.abi,
    functionName: "strikePrice",
  });
  assert((strikeOnChain as bigint) === STRIKE_PRICE, `Strike price is $50,000`);

  // ── Step 4: Place bets ───────────────────────────────────────────────────
  console.log("\n📋 Step 4: Place bets (1 BNB UP, 0.5 BNB DOWN)");

  // Bettor 1 bets UP (side=0)
  const bet1Hash = await bettor1Client.writeContract({
    address: market,
    abi: MarketArtifact.abi,
    functionName: "bet",
    args: [0], // Side.Up
    value: parseEther("1"),
  });
  const bet1Receipt = await publicClient.waitForTransactionReceipt({ hash: bet1Hash });
  assert(bet1Receipt.status === "success", "Bettor1 placed 1 BNB on UP");

  // Bettor 2 bets DOWN (side=1)
  const bet2Hash = await bettor2Client.writeContract({
    address: market,
    abi: MarketArtifact.abi,
    functionName: "bet",
    args: [1], // Side.Down
    value: parseEther("0.5"),
  });
  const bet2Receipt = await publicClient.waitForTransactionReceipt({ hash: bet2Hash });
  assert(bet2Receipt.status === "success", "Bettor2 placed 0.5 BNB on DOWN");

  // Verify pool
  const totalPool = await publicClient.readContract({
    address: market,
    abi: MarketArtifact.abi,
    functionName: "totalPool",
  });
  assert((totalPool as bigint) === parseEther("1.5"), `Total pool is 1.5 BNB`);

  const upTotal = await publicClient.readContract({
    address: market,
    abi: MarketArtifact.abi,
    functionName: "totalBets",
    args: [0], // Side.Up
  });
  assert((upTotal as bigint) === parseEther("1"), "UP pool is 1 BNB");

  const downTotal = await publicClient.readContract({
    address: market,
    abi: MarketArtifact.abi,
    functionName: "totalBets",
    args: [1], // Side.Down
  });
  assert((downTotal as bigint) === parseEther("0.5"), "DOWN pool is 0.5 BNB");

  // ── Step 5: Fast-forward past expiry ─────────────────────────────────────
  console.log("\n📋 Step 5: Fast-forward time past market expiry");

  await increaseTime(MARKET_DURATION + 10); // +10s buffer past expiry
  console.log(`  ⏩ Advanced ${MARKET_DURATION + 10} seconds`);

  // ── Step 6: Resolve market ───────────────────────────────────────────────
  console.log("\n📋 Step 6: Resolve market (price went UP to $51,000)");

  const resolveTimestamp = await getBlockTimestamp();
  const resolveUpdateData = await createPriceFeedData(mockPyth, RESOLUTION_PRICE, resolveTimestamp);

  const resolveFee = await publicClient.readContract({
    address: mockPyth,
    abi: MockPythArtifact.abi,
    functionName: "getUpdateFee",
    args: [[resolveUpdateData]],
  });

  // Only keeper (deployer) can resolve through factory
  const resolveHash = await deployerClient.writeContract({
    address: factory,
    abi: MarketFactoryArtifact.abi,
    functionName: "resolveMarket",
    args: [market, [resolveUpdateData]],
    value: resolveFee as bigint,
  });
  const resolveReceipt = await publicClient.waitForTransactionReceipt({ hash: resolveHash });
  assert(resolveReceipt.status === "success", "Market resolved successfully");

  // Verify resolution
  const finalState = await publicClient.readContract({
    address: market,
    abi: MarketArtifact.abi,
    functionName: "state",
  });
  assert(Number(finalState) === 2, "Market state is Resolved (2)");

  const winningSide = await publicClient.readContract({
    address: market,
    abi: MarketArtifact.abi,
    functionName: "winningSide",
  });
  assert(Number(winningSide) === 0, "Winning side is UP (0)");

  const resPrice = await publicClient.readContract({
    address: market,
    abi: MarketArtifact.abi,
    functionName: "resolutionPrice",
  });
  assert((resPrice as bigint) === RESOLUTION_PRICE, "Resolution price is $51,000");

  // ── Step 7: Claim winnings ───────────────────────────────────────────────
  console.log("\n📋 Step 7: Claim winnings for UP bettor");

  const balanceBefore = await publicClient.getBalance({ address: bettor1.address });

  const claimHash = await bettor1Client.writeContract({
    address: market,
    abi: MarketArtifact.abi,
    functionName: "claim",
  });
  const claimReceipt = await publicClient.waitForTransactionReceipt({ hash: claimHash });
  assert(claimReceipt.status === "success", "Claim tx succeeded");

  const balanceAfter = await publicClient.getBalance({ address: bettor1.address });
  const gained = balanceAfter - balanceBefore;

  // Winner gets bet back + loser pool minus 3% fee on losers, minus gas
  // Loser pool = 0.5 BNB, fee = 0.015 BNB, net winnings = 0.485 BNB
  // Payout = 1 + 0.485 = 1.485 BNB (minus gas)
  console.log(`  💰 Bettor1 gained: ${formatEther(gained)} BNB (expected ~1.485 BNB minus gas)`);
  assert(gained > parseEther("1.45"), "Winner received significant payout (> 1.45 BNB after gas)");

  // ── Step 8: Verify loser can't claim ─────────────────────────────────────
  console.log("\n📋 Step 8: Verify loser cannot claim");

  try {
    await bettor2Client.writeContract({
      address: market,
      abi: MarketArtifact.abi,
      functionName: "claim",
    });
    assert(false, "Loser claim should have reverted");
  } catch (err: any) {
    assert(true, "Loser claim correctly reverted");
  }

  // ── Step 9: Collect protocol fees ────────────────────────────────────────
  console.log("\n📋 Step 9: Collect protocol fees");

  const feeCollectorBefore = await publicClient.getBalance({ address: deployer.address });

  const feeHash = await deployerClient.writeContract({
    address: market,
    abi: MarketArtifact.abi,
    functionName: "collectFees",
  });
  const feeReceipt = await publicClient.waitForTransactionReceipt({ hash: feeHash });
  assert(feeReceipt.status === "success", "Fee collection tx succeeded");

  const feeCollectorAfter = await publicClient.getBalance({ address: deployer.address });
  const feesCollected = feeCollectorAfter - feeCollectorBefore;
  console.log(`  💸 Fees collected: ${formatEther(feesCollected)} BNB (expected ~0.015 BNB minus gas)`);
  assert(feesCollected > parseEther("0.01"), "Protocol fees collected (> 0.01 BNB after gas)");

  // ── Summary ──────────────────────────────────────────────────────────────
  console.log("\n═══════════════════════════════════════════════════════");
  console.log(`\n📊 Results: ${passCount} passed, ${failCount} failed\n`);

  if (failCount > 0) {
    process.exit(1);
  }
}

main().catch((err) => {
  console.error("\n💥 Fatal error:", err);
  process.exit(1);
});
