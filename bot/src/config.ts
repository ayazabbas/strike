import dotenv from "dotenv";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.resolve(__dirname, "../../.env.local") });

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
  deployerPrivateKey: env("DEPLOYER_PRIVATE_KEY", "") as `0x${string}`,
} as const;

export const PYTH = {
  hermesUrl: "https://hermes.pyth.network",
  feeds: {
    "BTC/USD": "0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43",
  },
  defaultDurationSeconds: 300, // 5 minutes
} as const;

export type FeedName = keyof typeof PYTH.feeds;
