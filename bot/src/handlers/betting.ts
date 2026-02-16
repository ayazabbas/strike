import { type Context, InlineKeyboard } from "grammy";
import { getUser, insertBet, updateBetTx } from "../db/database.js";
import { sendTransaction } from "../services/privy.js";
import {
  encodeBetCall,
  Side,
  parseEther,
  formatEther,
  estimatePayout,
  getMarketInfo,
  MarketState,
} from "../services/blockchain.js";
import { config } from "../config.js";
import { formatPrice } from "../services/pyth.js";

export async function handleBetConfirm(ctx: Context, marketAddress: string, side: string, amount: string) {
  const telegramId = ctx.from!.id;
  const user = getUser(telegramId);
  if (!user) {
    await ctx.editMessageText("You need to /start first to create a wallet.");
    return;
  }

  const betSide = side === "up" ? Side.Up : Side.Down;
  const amountWei = parseEther(amount);

  try {
    const market = await getMarketInfo(marketAddress as `0x${string}`);
    if (market.state !== MarketState.Open) {
      await ctx.editMessageText("This market is no longer accepting bets.", {
        reply_markup: new InlineKeyboard().text("Back to Markets", "markets"),
      });
      return;
    }

    let payoutText = "";
    try {
      const payout = await estimatePayout(marketAddress as `0x${string}`, betSide, amountWei);
      payoutText = `\nEstimated Payout: ${Number(formatEther(payout)).toFixed(4)} BNB`;
    } catch {}

    const sideLabel = side.toUpperCase();
    const text = [
      `Confirm your bet:\n`,
      `Side: ${sideLabel}`,
      `Amount: ${amount} BNB`,
      `Strike: $${formatPrice(market.strikePrice)}`,
      payoutText,
      `\n3% protocol fee applies to winnings.`,
    ].join("\n");

    const kb = new InlineKeyboard()
      .text("Confirm", `execbet:${marketAddress}:${side}:${amount}`)
      .text("Cancel", `market:${marketAddress}`);

    await ctx.editMessageText(text, { reply_markup: kb });
  } catch (err) {
    console.error("Bet confirm error:", err);
    await ctx.editMessageText("Failed to prepare bet. Try again.", {
      reply_markup: new InlineKeyboard().text("Back", `market:${marketAddress}`),
    });
  }
}

export async function handleBetExecute(ctx: Context, marketAddress: string, side: string, amount: string) {
  const telegramId = ctx.from!.id;
  const user = getUser(telegramId);
  if (!user) {
    await ctx.editMessageText("You need to /start first.");
    return;
  }

  const betSide = side === "up" ? Side.Up : Side.Down;
  const amountWei = parseEther(amount);

  await ctx.editMessageText(`Sending ${side.toUpperCase()} bet of ${amount} BNB...`);

  const betId = insertBet(telegramId, marketAddress, side as "up" | "down", amount);

  try {
    const data = encodeBetCall(betSide);
    const txHash = await sendTransaction(user.wallet_id, {
      to: marketAddress,
      value: "0x" + amountWei.toString(16),
      data,
      chainId: config.chainId,
    });

    updateBetTx(betId, txHash, "confirmed");

    const explorer = config.chainId === 56
      ? `https://bscscan.com/tx/${txHash}`
      : `https://testnet.bscscan.com/tx/${txHash}`;

    await ctx.editMessageText(
      `Bet placed!\n\n` +
      `${side.toUpperCase()} ${amount} BNB\n` +
      `TX: [View on BSCScan](${explorer})`,
      {
        parse_mode: "Markdown",
        link_preview_options: { is_disabled: true },
        reply_markup: new InlineKeyboard()
          .text("Back to Market", `market:${marketAddress}`)
          .row()
          .text("Main Menu", "main"),
      }
    );
  } catch (err: any) {
    updateBetTx(betId, "", "failed");
    console.error("Bet execution failed:", err);
    await ctx.editMessageText(
      `Bet failed: ${err.message ?? "Unknown error"}\n\nMake sure your wallet has enough BNB.`,
      {
        reply_markup: new InlineKeyboard()
          .text("Try Again", `bet:${marketAddress}:${side}:${amount}`)
          .row()
          .text("Back", `market:${marketAddress}`),
      }
    );
  }
}

// Tracks users awaiting custom amount input
export const pendingCustomBets = new Map<number, { marketAddress: string; side: string }>();

export async function handleCustomBetPrompt(ctx: Context, marketAddress: string, side: string) {
  const telegramId = ctx.from!.id;
  pendingCustomBets.set(telegramId, { marketAddress, side });

  await ctx.editMessageText(
    `Enter your ${side.toUpperCase()} bet amount in BNB (e.g. 0.05):\n\nMinimum: 0.001 BNB`,
    {
      reply_markup: new InlineKeyboard().text("Cancel", `market:${marketAddress}`),
    }
  );
}

export async function handleCustomBetAmount(ctx: Context) {
  const telegramId = ctx.from!.id;
  const pending = pendingCustomBets.get(telegramId);
  if (!pending) return false;

  const text = ctx.message?.text?.trim();
  if (!text) return false;

  const amount = parseFloat(text);
  if (isNaN(amount) || amount < 0.001) {
    await ctx.reply("Invalid amount. Minimum bet is 0.001 BNB. Try again:");
    return true;
  }

  pendingCustomBets.delete(telegramId);

  const { marketAddress, side } = pending;
  // Limit decimal places to avoid exceeding Telegram's 64-byte callback_data limit
  const amountStr = parseFloat(amount.toFixed(6)).toString();

  const kb = new InlineKeyboard()
    .text("Confirm", `execbet:${marketAddress}:${side}:${amountStr}`)
    .text("Cancel", `market:${marketAddress}`);

  await ctx.reply(
    `Confirm ${side.toUpperCase()} bet of ${amountStr} BNB?`,
    { reply_markup: kb }
  );
  return true;
}
