import { createPublicClient, http, formatEther, parseEther, encodeFunctionData, type Address } from "viem";
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
  expiryTime: number;
  upPool: bigint;
  downPool: bigint;
  totalPool: bigint;
}

export async function getBalance(address: Address): Promise<string> {
  const balance = await publicClient.getBalance({ address });
  return formatEther(balance);
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

  const [state, priceId, strikePrice, strikePriceExpo, startTime, expiryTime, upPool, downPool, totalPool] = info;

  return {
    address: marketAddress,
    state: Number(state) as MarketState,
    priceId: priceId as string,
    strikePrice: Number(strikePrice) * 10 ** Number(strikePriceExpo),
    startTime: Number(startTime),
    expiryTime: Number(expiryTime),
    upPool,
    downPool,
    totalPool,
  };
}

export async function getUserBets(marketAddress: Address, userAddress: Address) {
  const [upBet, downBet] = await publicClient.readContract({
    address: marketAddress,
    abi: MARKET_ABI,
    functionName: "getUserBets",
    args: [userAddress],
  });
  return { upBet, downBet };
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

export { formatEther, parseEther };
