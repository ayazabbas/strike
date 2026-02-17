import { createPublicClient, createWalletClient, http, formatEther, parseEther, encodeFunctionData, type Address } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { bsc, bscTestnet } from "viem/chains";
import { config } from "../config.js";

// ABI excerpts — only the functions we call
export const MARKET_ABI = [
  {
    name: "bet",
    type: "function",
    stateMutability: "payable",
    inputs: [{ name: "side", type: "uint8" }],
    outputs: [],
  },
  {
    name: "claim",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [],
    outputs: [],
  },
  {
    name: "refund",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [],
    outputs: [],
  },
  {
    name: "getMarketInfo",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [
      { name: "currentState", type: "uint8" },
      { name: "_priceId", type: "bytes32" },
      { name: "_strikePrice", type: "int64" },
      { name: "_strikePriceExpo", type: "int32" },
      { name: "_startTime", type: "uint256" },
      { name: "_tradingEnd", type: "uint256" },
      { name: "_expiryTime", type: "uint256" },
      { name: "upPool", type: "uint256" },
      { name: "downPool", type: "uint256" },
      { name: "_totalPool", type: "uint256" },
    ],
  },
  {
    name: "getUserBets",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "user", type: "address" }],
    outputs: [
      { name: "upBet", type: "uint256" },
      { name: "downBet", type: "uint256" },
      { name: "upShares", type: "uint256" },
      { name: "downShares", type: "uint256" },
    ],
  },
  {
    name: "estimatePayout",
    type: "function",
    stateMutability: "view",
    inputs: [
      { name: "side", type: "uint8" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "estimatedPayout", type: "uint256" }],
  },
  {
    name: "getCurrentState",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
  },
  {
    name: "strikePrice",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "int64" }],
  },
  {
    name: "strikePriceExpo",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "int32" }],
  },
  {
    name: "winningSide",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
  },
  {
    name: "resolutionPrice",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "int64" }],
  },
] as const;

export const FACTORY_ABI = [
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
  {
    name: "allMarkets",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "", type: "uint256" }],
    outputs: [{ name: "", type: "address" }],
  },
  {
    name: "isMarket",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
  },
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
  {
    name: "resolveMarket",
    type: "function",
    stateMutability: "payable",
    inputs: [
      { name: "market", type: "address" },
      { name: "pythUpdateData", type: "bytes[]" },
    ],
    outputs: [],
  },
  {
    name: "cancelMarket",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [{ name: "market", type: "address" }],
    outputs: [],
  },
] as const;

const chain = config.chainId === 56 ? bsc : bscTestnet;

export const publicClient = createPublicClient({
  chain,
  transport: http(config.bscRpcUrl),
});

// Market state enum matching the contract
export enum MarketState {
  Open = 0,
  Closed = 1,
  Resolved = 2,
  Cancelled = 3,
}

export const STATE_LABELS: Record<MarketState, string> = {
  [MarketState.Open]: "OPEN",
  [MarketState.Closed]: "CLOSED",
  [MarketState.Resolved]: "RESOLVED",
  [MarketState.Cancelled]: "CANCELLED",
};

export enum Side {
  Up = 0,
  Down = 1,
}

export interface MarketInfo {
  address: Address;
  state: MarketState;
  priceId: string;
  strikePrice: number;
  startTime: number;
  tradingEnd: number;
  expiryTime: number;
  upPool: bigint;
  downPool: bigint;
  totalPool: bigint;
  winningSide?: Side;
  resolutionPrice?: number;
}

export async function getBalance(address: Address): Promise<string> {
  const balance = await publicClient.getBalance({ address });
  return formatEther(balance);
}

export async function isMarketFromFactory(marketAddress: Address): Promise<boolean> {
  try {
    return await publicClient.readContract({
      address: config.marketFactoryAddress,
      abi: FACTORY_ABI,
      functionName: "isMarket",
      args: [marketAddress],
    }) as boolean;
  } catch {
    return false;
  }
}

export async function getMarketCount(): Promise<number> {
  const count = await publicClient.readContract({
    address: config.marketFactoryAddress,
    abi: FACTORY_ABI,
    functionName: "getMarketCount",
  });
  return Number(count);
}

export async function getMarketAddresses(offset = 0, limit = 10): Promise<Address[]> {
  return publicClient.readContract({
    address: config.marketFactoryAddress,
    abi: FACTORY_ABI,
    functionName: "getMarkets",
    args: [BigInt(offset), BigInt(limit)],
  }) as Promise<Address[]>;
}

export async function getMarketInfo(marketAddress: Address): Promise<MarketInfo> {
  const info = await publicClient.readContract({
    address: marketAddress,
    abi: MARKET_ABI,
    functionName: "getMarketInfo",
  });

  const [state, priceId, strikePrice, strikePriceExpo, startTime, tradingEnd, expiryTime, upPool, downPool, totalPool] = info;

  const result: MarketInfo = {
    address: marketAddress,
    state: Number(state) as MarketState,
    priceId: priceId as string,
    strikePrice: Number(strikePrice) * 10 ** Number(strikePriceExpo),
    startTime: Number(startTime),
    tradingEnd: Number(tradingEnd),
    expiryTime: Number(expiryTime),
    upPool,
    downPool,
    totalPool,
  };

  if (result.state === MarketState.Resolved) {
    try {
      const [winningSide, resPrice] = await Promise.all([
        publicClient.readContract({ address: marketAddress, abi: MARKET_ABI, functionName: "winningSide" }),
        publicClient.readContract({ address: marketAddress, abi: MARKET_ABI, functionName: "resolutionPrice" }),
      ]);
      result.winningSide = Number(winningSide) as Side;
      result.resolutionPrice = Number(resPrice) * 10 ** Number(strikePriceExpo);
    } catch {}
  }

  return result;
}

export async function getUserBets(marketAddress: Address, userAddress: Address) {
  const [upBet, downBet, upShares, downShares] = await publicClient.readContract({
    address: marketAddress,
    abi: MARKET_ABI,
    functionName: "getUserBets",
    args: [userAddress],
  });
  return { upBet, downBet, upShares, downShares };
}

export async function estimatePayout(marketAddress: Address, side: Side, amount: bigint): Promise<bigint> {
  return publicClient.readContract({
    address: marketAddress,
    abi: MARKET_ABI,
    functionName: "estimatePayout",
    args: [side, amount],
  });
}

export async function getWinningSide(marketAddress: Address): Promise<Side> {
  const side = await publicClient.readContract({
    address: marketAddress,
    abi: MARKET_ABI,
    functionName: "winningSide",
  });
  return Number(side) as Side;
}

export async function getResolutionPrice(marketAddress: Address): Promise<number> {
  const [price, expo] = await Promise.all([
    publicClient.readContract({
      address: marketAddress,
      abi: MARKET_ABI,
      functionName: "resolutionPrice",
    }),
    publicClient.readContract({
      address: marketAddress,
      abi: MARKET_ABI,
      functionName: "strikePriceExpo",
    }),
  ]);
  return Number(price) * 10 ** Number(expo);
}

export function encodeBetCall(side: Side): string {
  return encodeFunctionData({
    abi: MARKET_ABI,
    functionName: "bet",
    args: [side],
  });
}

export function encodeClaimCall(): string {
  return encodeFunctionData({
    abi: MARKET_ABI,
    functionName: "claim",
  });
}

export function encodeRefundCall(): string {
  return encodeFunctionData({
    abi: MARKET_ABI,
    functionName: "refund",
  });
}

export function encodeCreateMarketCall(priceId: `0x${string}`, duration: bigint, pythUpdateData: `0x${string}`[]): string {
  return encodeFunctionData({
    abi: FACTORY_ABI,
    functionName: "createMarket",
    args: [priceId, duration, pythUpdateData],
  });
}

/**
 * Send a createMarket tx using the deployer/keeper private key directly.
 * Returns the tx hash.
 */
export async function createMarketOnChain(priceId: `0x${string}`, duration: bigint, pythUpdateData: `0x${string}`[]): Promise<string> {
  if (!config.deployerPrivateKey) throw new Error("DEPLOYER_PRIVATE_KEY not set");
  const account = privateKeyToAccount(config.deployerPrivateKey);
  const walletClient = createWalletClient({ account, chain, transport: http(config.bscRpcUrl) });

  const hash = await walletClient.writeContract({
    address: config.marketFactoryAddress,
    abi: FACTORY_ABI,
    functionName: "createMarket",
    args: [priceId, duration, pythUpdateData],
    value: 1n, // Pyth update fee
  });
  return hash;
}

/**
 * Resolve a market via the factory's resolveMarket (onlyKeeper).
 * Returns the tx hash.
 */
export async function resolveMarketOnChain(marketAddress: Address, pythUpdateData: `0x${string}`[]): Promise<string> {
  if (!config.deployerPrivateKey) throw new Error("DEPLOYER_PRIVATE_KEY not set");
  const account = privateKeyToAccount(config.deployerPrivateKey);
  const walletClient = createWalletClient({ account, chain, transport: http(config.bscRpcUrl) });

  const hash = await walletClient.writeContract({
    address: config.marketFactoryAddress,
    abi: FACTORY_ABI,
    functionName: "resolveMarket",
    args: [marketAddress, pythUpdateData],
    value: parseEther("0.001"),
  });
  return hash;
}

/**
 * Cancel an empty market via the factory's cancelMarket (onlyOwner).
 * Returns the tx hash.
 */
export async function cancelMarketOnChain(marketAddress: Address): Promise<string> {
  if (!config.deployerPrivateKey) throw new Error("DEPLOYER_PRIVATE_KEY not set");
  const account = privateKeyToAccount(config.deployerPrivateKey);
  const walletClient = createWalletClient({ account, chain, transport: http(config.bscRpcUrl) });

  const hash = await walletClient.writeContract({
    address: config.marketFactoryAddress,
    abi: FACTORY_ABI,
    functionName: "cancelMarket",
    args: [marketAddress],
  });
  return hash;
}

/**
 * Place a bet on a market using the deployer/keeper private key directly.
 * Returns the tx hash.
 */
export async function betOnMarketOnChain(marketAddress: Address, side: Side, value: bigint): Promise<string> {
  if (!config.deployerPrivateKey) throw new Error("DEPLOYER_PRIVATE_KEY not set");
  const account = privateKeyToAccount(config.deployerPrivateKey);
  const walletClient = createWalletClient({ account, chain, transport: http(config.bscRpcUrl) });

  const hash = await walletClient.writeContract({
    address: marketAddress,
    abi: MARKET_ABI,
    functionName: "bet",
    args: [side],
    value,
  });
  return hash;
}

/**
 * Claim winnings from a resolved market (calls Market.claim() directly).
 * Returns the tx hash.
 */
export async function claimOnMarket(marketAddress: Address): Promise<string> {
  if (!config.deployerPrivateKey) throw new Error("DEPLOYER_PRIVATE_KEY not set");
  const account = privateKeyToAccount(config.deployerPrivateKey);
  const walletClient = createWalletClient({ account, chain, transport: http(config.bscRpcUrl) });

  const hash = await walletClient.writeContract({
    address: marketAddress,
    abi: MARKET_ABI,
    functionName: "claim",
  });
  return hash;
}

/**
 * Refund bets from a cancelled market (calls Market.refund() directly).
 * Returns the tx hash.
 */
export async function refundOnMarket(marketAddress: Address): Promise<string> {
  if (!config.deployerPrivateKey) throw new Error("DEPLOYER_PRIVATE_KEY not set");
  const account = privateKeyToAccount(config.deployerPrivateKey);
  const walletClient = createWalletClient({ account, chain, transport: http(config.bscRpcUrl) });

  const hash = await walletClient.writeContract({
    address: marketAddress,
    abi: MARKET_ABI,
    functionName: "refund",
  });
  return hash;
}

/**
 * Get the keeper wallet address derived from the deployer private key.
 */
export function getKeeperAddress(): Address {
  if (!config.deployerPrivateKey) throw new Error("DEPLOYER_PRIVATE_KEY not set");
  return privateKeyToAccount(config.deployerPrivateKey).address;
}

export { formatEther, parseEther };
