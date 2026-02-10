import "dotenv/config";
import {
  createPublicClient,
  createWalletClient,
  http,
  parseEther,
  type Address,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { bscTestnet, bsc } from "viem/chains";

// ─── Config ──────────────────────────────────────────────────────────────

const PYTH_FEEDS: Record<string, Hex> = {
  "BTC/USD": "0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43",
  "BNB/USD": "0x2f95862b045670cd22bee3114c39763a4a08beeb663b145d283c31d7d1101c4f",
};

const DURATIONS: Record<string, number> = {
  "1h": 3600,
  "4h": 14400,
  "24h": 86400,
};

const FACTORY_ABI = [
  {
    name: "createMarket",
    type: "function",
    stateMutability: "payable",
    inputs: [
      { name: "priceId", type: "bytes32" },
      { name: "duration", type: "uint256" },
      { name: "pythUpdateData", type: "bytes[]" },
    ],
    outputs: [{ name: "market", type: "address" }],
  },
] as const;

// ─── Helpers ─────────────────────────────────────────────────────────────

async function fetchPythUpdateData(feedId: string): Promise<Hex[]> {
  const url = `https://hermes.pyth.network/v2/updates/price/latest?ids[]=${feedId}&encoding=hex`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Pyth Hermes error: ${res.status}`);
  const data = (await res.json()) as { binary: { data: string[] } };
  return data.binary.data.map((d: string) => `0x${d}` as Hex);
}

// ─── Main ────────────────────────────────────────────────────────────────

async function main() {
  const args = process.argv.slice(2);
  const pairIdx = args.indexOf("--pair");
  const durationIdx = args.indexOf("--duration");

  if (pairIdx === -1 || durationIdx === -1) {
    console.log("Usage: npx tsx scripts/create-market.ts --pair BTC/USD --duration 1h");
    console.log("Pairs: BTC/USD, BNB/USD");
    console.log("Durations: 1h, 4h, 24h");
    process.exit(1);
  }

  const pair = args[pairIdx + 1];
  const duration = args[durationIdx + 1];

  const feedId = PYTH_FEEDS[pair];
  if (!feedId) {
    console.error(`Unknown pair: ${pair}. Supported: ${Object.keys(PYTH_FEEDS).join(", ")}`);
    process.exit(1);
  }

  const durationSecs = DURATIONS[duration];
  if (!durationSecs) {
    console.error(`Unknown duration: ${duration}. Supported: ${Object.keys(DURATIONS).join(", ")}`);
    process.exit(1);
  }

  const factoryAddress = process.env.MARKET_FACTORY_ADDRESS as Address;
  const privateKey = process.env.DEPLOYER_PRIVATE_KEY as Hex;
  const rpcUrl = process.env.BSC_RPC_URL || "https://bsc-testnet-rpc.publicnode.com";
  const chainId = Number(process.env.CHAIN_ID || "97");

  if (!factoryAddress || !privateKey) {
    console.error("Missing MARKET_FACTORY_ADDRESS or DEPLOYER_PRIVATE_KEY in .env");
    process.exit(1);
  }

  const chain = chainId === 56 ? bsc : bscTestnet;
  const account = privateKeyToAccount(privateKey);

  const publicClient = createPublicClient({ chain, transport: http(rpcUrl) });
  const walletClient = createWalletClient({ account, chain, transport: http(rpcUrl) });

  console.log(`⚡ Creating ${pair} market (${duration}) on ${chain.name}...`);
  console.log(`   Factory: ${factoryAddress}`);
  console.log(`   Feed ID: ${feedId}`);
  console.log(`   Duration: ${durationSecs}s`);

  // Fetch Pyth update data
  console.log("📡 Fetching Pyth price data...");
  const pythUpdateData = await fetchPythUpdateData(feedId.slice(2)); // remove 0x prefix for API

  // Estimate Pyth fee (typically 1 wei on BSC)
  const pythFee = parseEther("0.001"); // Send 0.001 BNB to cover Pyth fee + refund excess

  console.log("📝 Sending createMarket transaction...");
  const hash = await walletClient.writeContract({
    address: factoryAddress,
    abi: FACTORY_ABI,
    functionName: "createMarket",
    args: [feedId, BigInt(durationSecs), pythUpdateData],
    value: pythFee,
  });

  console.log(`⏳ Tx hash: ${hash}`);
  console.log("   Waiting for confirmation...");

  const receipt = await publicClient.waitForTransactionReceipt({ hash });

  if (receipt.status === "success") {
    // Parse MarketCreated event from logs
    console.log(`✅ Market created! Block: ${receipt.blockNumber}`);
    console.log(`   Gas used: ${receipt.gasUsed}`);
    console.log(`   BSCScan: https://${chainId === 97 ? "testnet." : ""}bscscan.com/tx/${hash}`);
  } else {
    console.error("❌ Transaction reverted!");
    process.exit(1);
  }
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
