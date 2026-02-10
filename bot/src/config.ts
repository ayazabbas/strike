import "dotenv/config";

function env(key: string, fallback?: string): string {
  const v = process.env[key] ?? fallback;
  if (!v) throw new Error(`Missing env var: ${key}`);
  return v;
}

export const config = {
  botToken: env("BOT_TOKEN"),
  privyAppId: env("PRIVY_APP_ID"),
  privyAppSecret: env("PRIVY_APP_SECRET"),
  bscRpcUrl: env("BSC_RPC_URL", "https://bsc-testnet-rpc.publicnode.com"),
  marketFactoryAddress: env("MARKET_FACTORY_ADDRESS", "0x0000000000000000000000000000000000000000") as `0x${string}`,
  chainId: Number(env("CHAIN_ID", "97")),
  adminTelegramId: Number(env("ADMIN_TELEGRAM_ID", "0")),
} as const;

export const PYTH = {
  hermesUrl: "https://hermes.pyth.network",
  feeds: {
    "BTC/USD": "0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43",
    "BNB/USD": "0x2f95862b045670cd22bee3114c39763a4a08beeb663b145d283c31d7d1101c4f",
  },
} as const;

export type FeedName = keyof typeof PYTH.feeds;
