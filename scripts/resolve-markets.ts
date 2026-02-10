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

const FACTORY_ABI = [
  {
    name: "getMarketCount",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "getMarkets",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "offset", type: "uint256" },
      { name: "limit", type: "uint256" },
    ],
    outputs: [{ name: "markets", type: "address[]" }],
  },
] as const;

const MARKET_ABI = [
  {
    name: "state",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
  },
  {
    name: "expiryTime",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "priceId",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "bytes32" }],
  },
  {
    name: "totalPool",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "resolve",
    type: "function",
    stateMutability: "payable",
    inputs: [{ name: "pythUpdateData", type: "bytes[]" }],
    outputs: [],
  },
  {
    name: "getCurrentState",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
  },
] as const;

enum MarketState {
  Open = 0,
  Closed = 1,
  Resolved = 2,
  Cancelled = 3,
}

// ─── Helpers ─────────────────────────────────────────────────────────────

async function fetchPythUpdateData(feedId: string): Promise<Hex[]> {
  const cleanId = feedId.startsWith("0x") ? feedId.slice(2) : feedId;
  const url = `https://hermes.pyth.network/v2/updates/price/latest?ids[]=${cleanId}&encoding=hex`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Pyth Hermes error: ${res.status}`);
  const data = (await res.json()) as { binary: { data: string[] } };
  return data.binary.data.map((d: string) => `0x${d}` as Hex);
}

// ─── Main ────────────────────────────────────────────────────────────────

async function main() {
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

  console.log(`🔍 Checking markets on ${chain.name}...`);
  console.log(`   Factory: ${factoryAddress}`);

  // Get all markets
  const marketCount = await publicClient.readContract({
    address: factoryAddress,
    abi: FACTORY_ABI,
    functionName: "getMarketCount",
  });

  console.log(`   Total markets: ${marketCount}`);

  if (marketCount === 0n) {
    console.log("   No markets found.");
    return;
  }

  const markets = await publicClient.readContract({
    address: factoryAddress,
    abi: FACTORY_ABI,
    functionName: "getMarkets",
    args: [0n, marketCount],
  });

  const now = BigInt(Math.floor(Date.now() / 1000));
  let resolved = 0;
  let skipped = 0;

  for (const marketAddr of markets) {
    try {
      const [stateRaw, expiryTime, priceId, totalPool] = await Promise.all([
        publicClient.readContract({
          address: marketAddr,
          abi: MARKET_ABI,
          functionName: "state",
        }),
        publicClient.readContract({
          address: marketAddr,
          abi: MARKET_ABI,
          functionName: "expiryTime",
        }),
        publicClient.readContract({
          address: marketAddr,
          abi: MARKET_ABI,
          functionName: "priceId",
        }),
        publicClient.readContract({
          address: marketAddr,
          abi: MARKET_ABI,
          functionName: "totalPool",
        }),
      ]);

      const state = Number(stateRaw) as MarketState;

      // Skip already resolved or cancelled markets
      if (state === MarketState.Resolved || state === MarketState.Cancelled) {
        skipped++;
        continue;
      }

      // Check if market is expired and ready for resolution
      // State.Open (0) transitions to Closed when expiry - 60s is reached
      // State.Closed (1) can be resolved after expiryTime
      if (now < expiryTime) {
        console.log(`   ⏳ ${marketAddr.slice(0, 10)}... — not yet expired (${Number(expiryTime - now)}s left)`);
        skipped++;
        continue;
      }

      if (totalPool === 0n) {
        console.log(`   ⏭️  ${marketAddr.slice(0, 10)}... — empty pool, skipping`);
        skipped++;
        continue;
      }

      console.log(`   🎯 ${marketAddr.slice(0, 10)}... — expired, resolving...`);

      // Fetch Pyth update data for this market's price feed
      const pythUpdateData = await fetchPythUpdateData(priceId);
      const pythFee = parseEther("0.001");

      const hash = await walletClient.writeContract({
        address: marketAddr,
        abi: MARKET_ABI,
        functionName: "resolve",
        args: [pythUpdateData],
        value: pythFee,
      });

      const receipt = await publicClient.waitForTransactionReceipt({ hash });

      if (receipt.status === "success") {
        console.log(`   ✅ Resolved! Tx: ${hash.slice(0, 18)}... Gas: ${receipt.gasUsed}`);
        resolved++;
      } else {
        console.log(`   ❌ Resolution reverted for ${marketAddr.slice(0, 10)}...`);
      }
    } catch (err) {
      console.error(`   ⚠️  Error processing ${marketAddr.slice(0, 10)}...:`, (err as Error).message);
    }
  }

  console.log(`\n📊 Summary: ${resolved} resolved, ${skipped} skipped, ${markets.length} total`);
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
