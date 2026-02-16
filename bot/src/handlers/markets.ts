import { type Context, InlineKeyboard } from "grammy";
import {
  getMarketCount,
  getMarketAddresses,
  getMarketInfo,
  getUserBets as getOnChainBets,
  MarketState,
  STATE_LABELS,
  type MarketInfo,
  formatEther,
  estimatePayout,
  Side,
  publicClient,
} from "../services/blockchain.js";
import { getLatestPrices, formatPrice } from "../services/pyth.js";
import { PYTH, type FeedName } from "../config.js";
import { getUser } from "../db/database.js";
import type { Address } from "viem";

// ABI for getCurrentState view function
const GET_CURRENT_STATE_ABI = [
  {
    name: "getCurrentState",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{ name: "", type: "uint8" }],
  },
] as const;

function feedNameFromId(priceId: string): FeedName | "Unknown" {
  for (const [name, id] of Object.entries(PYTH.feeds)) {
    if (priceId.toLowerCase() === id.toLowerCase()) return name as FeedName;
  }
  return "Unknown";
}

function timeRemaining(expiryTime: number): string {
  const now = Math.floor(Date.now() / 1000);
  const diff = expiryTime - now;
  if (diff <= 0) return "Expired";
  const m = Math.floor(diff / 60);
  const s = diff % 60;
  if (m > 0) return `${m}m ${s}s`;
  return `${s}s`;
}

function formatTime(ts: number): string {
  const d = new Date(ts * 1000);
  return d.toISOString().slice(11, 16) + " UTC";
}

async function getComputedState(marketAddress: Address): Promise<MarketState> {
  const state = await publicClient.readContract({
    address: marketAddress,
    abi: GET_CURRENT_STATE_ABI,
    functionName: "getCurrentState",
  });
  return Number(state) as MarketState;
}

/**
 * Find the currently live (Open) market by checking computed state.
 * Scans from newest to oldest for efficiency.
 */
async function findLiveMarket(): Promise<MarketInfo | null> {
  const count = await getMarketCount();
  if (count === 0) return null;

  // Scan from newest market backwards (most likely to be open)
  const batchSize = 10;
  for (let offset = Math.max(0, count - batchSize); offset >= 0; offset = Math.max(0, offset - batchSize)) {
    const limit = Math.min(batchSize, count - offset);
    const addresses = await getMarketAddresses(offset, limit);

    // Check newest first
    for (let i = addresses.length - 1; i >= 0; i--) {
      try {
        const computedState = await getComputedState(addresses[i]);
        if (computedState === MarketState.Open || computedState === MarketState.Closed) {
          const info = await getMarketInfo(addresses[i]);
          // Override stored state with computed state
          info.state = computedState;
          return info;
        }
      } catch {
        // skip
      }
    }

    if (offset === 0) break;
  }

  return null;
}

export async function handleMarkets(ctx: Context) {
  try {
    const market = await findLiveMarket();

    if (!market) {
      await ctx.editMessageText(
        "⏳ No live market right now.\n\nA new BTC/USD round starts every 5 minutes. Check back shortly!",
        {
          reply_markup: new InlineKeyboard()
            .text("🔄 Refresh", "live")
            .row()
            .text("« Back", "main"),
        }
      );
      return;
    }

    const feed = feedNameFromId(market.priceId);

    // Get live price
    let livePrice: number | null = null;
    try {
      const prices = await getLatestPrices([feed as FeedName]);
      livePrice = prices[0]?.price ?? null;
    } catch {}

    const upPool = Number(formatEther(market.upPool)).toFixed(4);
    const downPool = Number(formatEther(market.downPool)).toFixed(4);
    const totalPool = Number(formatEther(market.totalPool)).toFixed(4);
    const window = `${formatTime(market.startTime)} → ${formatTime(market.expiryTime)}`;
    const isBettingOpen = market.state === MarketState.Open;
    const resolvesIn = timeRemaining(market.expiryTime);

    let priceDirection = "";
    if (livePrice) {
      const diff = livePrice - market.strikePrice;
      if (diff > 0) priceDirection = " 📈";
      else if (diff < 0) priceDirection = " 📉";
      else priceDirection = " ➡️";
    }

    let text = `⚡ LIVE — ${feed}\n\n`;
    text += `🕐 Window: ${window}\n`;
    if (isBettingOpen) {
      text += `⏱ Betting closes: ${timeRemaining(market.tradingEnd)}\n\n`;
    } else {
      text += `🔒 Betting closed — resolves in ${resolvesIn}\n\n`;
    }
    text += `🎯 Strike: $${formatPrice(market.strikePrice)}\n`;
    if (livePrice) {
      text += `💰 Current: $${formatPrice(livePrice)}${priceDirection}\n`;
      const pct = ((livePrice - market.strikePrice) / market.strikePrice) * 100;
      text += `📊 Change: ${pct >= 0 ? "+" : ""}${pct.toFixed(3)}%\n`;
    }
    text += `\n`;
    text += `🟢 UP Pool: ${upPool} BNB\n`;
    text += `🔴 DOWN Pool: ${downPool} BNB\n`;
    text += `💎 Total: ${totalPool} BNB\n`;

    // Show user's position if they have a bet
    const telegramId = ctx.from?.id;
    if (telegramId) {
      const user = getUser(telegramId);
      if (user) {
        try {
          const onChain = await getOnChainBets(market.address, user.wallet_address as Address);
          const userUp = Number(formatEther(onChain.upBet));
          const userDown = Number(formatEther(onChain.downBet));
          if (userUp > 0 || userDown > 0) {
            text += `\n📍 Your Position:\n`;
            if (userUp > 0) {
              text += `  🟢 UP: ${userUp.toFixed(4)} BNB (${Number(formatEther(onChain.upShares)).toFixed(4)} shares)`;
              try {
                const payout = await estimatePayout(market.address, Side.Up, onChain.upBet);
                text += ` → ~${Number(formatEther(payout)).toFixed(4)} BNB`;
              } catch {}
              text += `\n`;
            }
            if (userDown > 0) {
              text += `  🔴 DOWN: ${userDown.toFixed(4)} BNB (${Number(formatEther(onChain.downShares)).toFixed(4)} shares)`;
              try {
                const payout = await estimatePayout(market.address, Side.Down, onChain.downBet);
                text += ` → ~${Number(formatEther(payout)).toFixed(4)} BNB`;
              } catch {}
              text += `\n`;
            }
          }
        } catch {}
      }
    }

    const kb = new InlineKeyboard();

    if (isBettingOpen) {
      kb.text("🟢 UP 0.01", `bet:${market.address}:up:0.01`)
        .text("🟢 UP 0.05", `bet:${market.address}:up:0.05`)
        .text("🟢 UP 0.1", `bet:${market.address}:up:0.1`)
        .row()
        .text("🔴 DOWN 0.01", `bet:${market.address}:down:0.01`)
        .text("🔴 DOWN 0.05", `bet:${market.address}:down:0.05`)
        .text("🔴 DOWN 0.1", `bet:${market.address}:down:0.1`)
        .row()
        .text("🟢 UP Custom", `betcustom:${market.address}:up`)
        .text("🔴 DOWN Custom", `betcustom:${market.address}:down`)
        .row();
    }

    kb.text("🔄 Refresh", "live")
      .row()
      .text("« Back", "main");

    await ctx.editMessageText(text, { reply_markup: kb });
  } catch (err) {
    console.error("Live market error:", err);
    await ctx.editMessageText("Failed to load live market. Try again.", {
      reply_markup: new InlineKeyboard().text("Retry", "live").row().text("« Back", "main"),
    });
  }
}

export async function handleMarketDetail(ctx: Context, marketAddress: string) {
  try {
    const market = await getMarketInfo(marketAddress as `0x${string}`);
    const computedState = await getComputedState(marketAddress as Address);
    market.state = computedState;

    const feed = feedNameFromId(market.priceId);

    let livePrice: number | null = null;
    try {
      const prices = await getLatestPrices([feed as FeedName]);
      livePrice = prices[0]?.price ?? null;
    } catch {}

    const upPool = Number(formatEther(market.upPool)).toFixed(4);
    const downPool = Number(formatEther(market.downPool)).toFixed(4);
    const totalPool = Number(formatEther(market.totalPool)).toFixed(4);
    const window = `${formatTime(market.startTime)} → ${formatTime(market.expiryTime)}`;

    let text = `⚡ ${feed} Market\n\n`;
    text += `State: ${STATE_LABELS[market.state]}\n`;
    text += `🕐 Window: ${window}\n`;
    text += `🎯 Strike: $${formatPrice(market.strikePrice)}\n`;
    if (livePrice) {
      text += `💰 Current: $${formatPrice(livePrice)}\n`;
      const diff = ((livePrice - market.strikePrice) / market.strikePrice) * 100;
      text += `📊 Change: ${diff >= 0 ? "+" : ""}${diff.toFixed(2)}%\n`;
    }
    text += `\n`;
    text += `🟢 UP: ${upPool} BNB\n`;
    text += `🔴 DOWN: ${downPool} BNB\n`;
    text += `💎 Total: ${totalPool} BNB\n`;

    if (market.state === MarketState.Open) {
      text += `\n⏱ Betting closes: ${timeRemaining(market.tradingEnd)}\n`;
    }

    // Show user's position if they have a bet
    const detailTelegramId = ctx.from?.id;
    if (detailTelegramId) {
      const detailUser = getUser(detailTelegramId);
      if (detailUser) {
        try {
          const onChain = await getOnChainBets(marketAddress as Address, detailUser.wallet_address as Address);
          const userUp = Number(formatEther(onChain.upBet));
          const userDown = Number(formatEther(onChain.downBet));
          if (userUp > 0 || userDown > 0) {
            text += `\n📍 Your Position:\n`;
            if (userUp > 0) {
              text += `  🟢 UP: ${userUp.toFixed(4)} BNB (${Number(formatEther(onChain.upShares)).toFixed(4)} shares)`;
              try {
                const payout = await estimatePayout(marketAddress as Address, Side.Up, onChain.upBet);
                text += ` → ~${Number(formatEther(payout)).toFixed(4)} BNB`;
              } catch {}
              text += `\n`;
            }
            if (userDown > 0) {
              text += `  🔴 DOWN: ${userDown.toFixed(4)} BNB (${Number(formatEther(onChain.downShares)).toFixed(4)} shares)`;
              try {
                const payout = await estimatePayout(marketAddress as Address, Side.Down, onChain.downBet);
                text += ` → ~${Number(formatEther(payout)).toFixed(4)} BNB`;
              } catch {}
              text += `\n`;
            }
          }
        } catch {}
      }
    }

    const kb = new InlineKeyboard();

    if (market.state === MarketState.Open) {
      kb.text("🟢 UP 0.01", `bet:${marketAddress}:up:0.01`)
        .text("🟢 UP 0.05", `bet:${marketAddress}:up:0.05`)
        .text("🟢 UP 0.1", `bet:${marketAddress}:up:0.1`)
        .row()
        .text("🔴 DOWN 0.01", `bet:${marketAddress}:down:0.01`)
        .text("🔴 DOWN 0.05", `bet:${marketAddress}:down:0.05`)
        .text("🔴 DOWN 0.1", `bet:${marketAddress}:down:0.1`)
        .row()
        .text("🟢 UP Custom", `betcustom:${marketAddress}:up`)
        .text("🔴 DOWN Custom", `betcustom:${marketAddress}:down`)
        .row();
    }

    kb.text("🔄 Refresh", `market:${marketAddress}`).row();
    kb.text("« Back", "live");

    await ctx.editMessageText(text, { reply_markup: kb });
  } catch (err) {
    console.error("Market detail error:", err);
    await ctx.editMessageText("Failed to load market details.", {
      reply_markup: new InlineKeyboard().text("Back", "live"),
    });
  }
}
