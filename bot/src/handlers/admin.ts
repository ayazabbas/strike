import { type Context } from "grammy";
import { config, PYTH, type FeedName } from "../config.js";
import { getMarketCount, getMarketAddresses, getMarketInfo, createMarketOnChain, formatEther, STATE_LABELS } from "../services/blockchain.js";
import { getPriceUpdateData, formatPrice } from "../services/pyth.js";
import { getUserCount, getBetCount } from "../db/database.js";
import type { Address } from "viem";

function isAdmin(telegramId: number): boolean {
  return config.adminTelegramId !== 0 && telegramId === config.adminTelegramId;
}

export async function handleAdmin(ctx: Context) {
  const telegramId = ctx.from!.id;

  if (!isAdmin(telegramId)) {
    await ctx.reply("Unauthorized.");
    return;
  }

  const args = ctx.message?.text?.split(/\s+/).slice(1) ?? [];
  const subcommand = args[0]?.toLowerCase();

  if (!subcommand || subcommand === "help") {
    await ctx.reply([
      "Admin Commands:\n",
      "/admin stats - Bot statistics",
      "/admin markets - List all markets with state",
      "/admin create - Create a 5-minute BTC/USD market",
    ].join("\n"));
    return;
  }

  if (subcommand === "stats") {
    await handleStats(ctx);
  } else if (subcommand === "markets") {
    await handleAdminMarkets(ctx);
  } else if (subcommand === "create") {
    await handleCreateMarket(ctx, args.slice(1));
  } else {
    await ctx.reply("Unknown subcommand. Use /admin help");
  }
}

async function handleStats(ctx: Context) {
  const userCount = getUserCount();
  const betStats = getBetCount();
  let marketCount = 0;
  try {
    marketCount = await getMarketCount();
  } catch {}

  const network = config.chainId === 56 ? "BSC Mainnet" : "BSC Testnet";

  await ctx.reply([
    "Bot Statistics\n",
    `Network: ${network}`,
    `Factory: ${config.marketFactoryAddress}`,
    `Markets on-chain: ${marketCount}`,
    `Registered users: ${userCount}`,
    `Total bets: ${betStats.total} (${betStats.confirmed} confirmed, ${betStats.failed} failed)`,
  ].join("\n"));
}

async function handleAdminMarkets(ctx: Context) {
  let count: number;
  try {
    count = await getMarketCount();
  } catch (err) {
    await ctx.reply("Failed to read market count from chain.");
    return;
  }

  if (count === 0) {
    await ctx.reply("No markets deployed yet.");
    return;
  }

  const addresses = await getMarketAddresses(0, Math.min(count, 20));
  const lines: string[] = [`Markets (${count} total):\n`];

  for (const addr of addresses) {
    try {
      const m = await getMarketInfo(addr);
      const upPool = Number(formatEther(m.upPool)).toFixed(3);
      const downPool = Number(formatEther(m.downPool)).toFixed(3);
      const short = `${addr.slice(0, 6)}...${addr.slice(-4)}`;
      lines.push(`${short} | ${STATE_LABELS[m.state]} | $${formatPrice(m.strikePrice)} | UP:${upPool} DOWN:${downPool}`);
    } catch {
      lines.push(`${addr.slice(0, 6)}...${addr.slice(-4)} | ERROR`);
    }
  }

  await ctx.reply(lines.join("\n"));
}

async function handleCreateMarket(ctx: Context, _args: string[]) {
  const feedName: FeedName = "BTC/USD";
  const duration = BigInt(PYTH.defaultDurationSeconds);

  await ctx.reply(`Creating ${feedName} market (5m) using keeper wallet...`);

  try {
    const priceId = PYTH.feeds[feedName] as `0x${string}`;
    const pythUpdateData = await getPriceUpdateData([priceId]) as `0x${string}`[];

    const txHash = await createMarketOnChain(priceId, duration, pythUpdateData);

    const explorer = config.chainId === 56
      ? `https://bscscan.com/tx/${txHash}`
      : `https://testnet.bscscan.com/tx/${txHash}`;

    await ctx.reply(`Market created!\n\n[View TX on BSCScan](${explorer})`, { parse_mode: "Markdown", link_preview_options: { is_disabled: true } });
  } catch (err: any) {
    console.error("Admin create market error:", err);
    await ctx.reply(`Failed to create market: ${err.message ?? "Unknown error"}`);
  }
}
