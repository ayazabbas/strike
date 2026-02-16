import { Bot, type BotError, GrammyError, HttpError } from "grammy";
import { config } from "./config.js";
import { handleStart, mainMenuKeyboard } from "./handlers/start.js";
import { handleMarkets, handleMarketDetail } from "./handlers/markets.js";
import { handleBetConfirm, handleBetExecute, handleCustomBetPrompt, handleCustomBetAmount } from "./handlers/betting.js";
import { handleWallet, handleCopyAddress } from "./handlers/wallet.js";
import { handleMyBets, handleClaimAll } from "./handlers/mybets.js";
import { handleSettings } from "./handlers/settings.js";
import { handleHelp } from "./handlers/help.js";
import { handleHowItWorks } from "./handlers/howitworks.js";
import { handleAdmin } from "./handlers/admin.js";
import { handleHistory } from "./handlers/history.js";

const bot = new Bot(config.botToken);

// ── Commands ──────────────────────────────────────────────────────────
bot.command("start", handleStart);
bot.command("help", handleHelp);
bot.command("history", (ctx) => handleHistory(ctx));
bot.command("admin", handleAdmin);

// ── Text messages (for custom bet amounts) ────────────────────────────
bot.on("message:text", async (ctx) => {
  const handled = await handleCustomBetAmount(ctx);
  if (!handled) {
    await ctx.reply("Use /start to begin, or tap a button below.", {
      reply_markup: mainMenuKeyboard(),
    });
  }
});

// ── Callback queries (button presses) ─────────────────────────────────
bot.on("callback_query:data", async (ctx) => {
  const data = ctx.callbackQuery.data;

  try {
    // Main menu
    if (data === "main") {
      const text = "What would you like to do?";
      await ctx.editMessageText(text, { reply_markup: mainMenuKeyboard() });
    }

    // How it works
    else if (data === "howitworks" || data.startsWith("howitworks:")) {
      const page = data.includes(":") ? parseInt(data.split(":")[1]) : 0;
      await handleHowItWorks(ctx, page);
    }

    // Live market
    else if (data === "live" || data === "markets") {
      await handleMarkets(ctx);
    }

    // Market detail: market:0x...
    else if (data.startsWith("market:")) {
      const addr = data.split(":")[1];
      await handleMarketDetail(ctx, addr);
    }

    // Bet with preset amount: bet:0x...:up:0.1
    else if (data.startsWith("bet:")) {
      const [, addr, side, amount] = data.split(":");
      await handleBetConfirm(ctx, addr, side, amount);
    }

    // Custom bet prompt: betcustom:0x...:up
    else if (data.startsWith("betcustom:")) {
      const [, addr, side] = data.split(":");
      await handleCustomBetPrompt(ctx, addr, side);
    }

    // Execute bet: execbet:0x...:up:0.1
    else if (data.startsWith("execbet:")) {
      const [, addr, side, amount] = data.split(":");
      await handleBetExecute(ctx, addr, side, amount);
    }

    // Wallet
    else if (data === "wallet") {
      await handleWallet(ctx);
    }

    // Copy address (handler answers callback query internally)
    else if (data === "copyaddr") {
      await handleCopyAddress(ctx);
      return;
    }

    // My bets
    else if (data === "mybets") {
      await handleMyBets(ctx);
    }

    // Claim all winnings
    else if (data === "claimall") {
      await handleClaimAll(ctx);
    }

    // History
    else if (data === "history" || data.startsWith("history:")) {
      const page = data.includes(":") ? parseInt(data.split(":")[1]) : 0;
      await handleHistory(ctx, page);
    }

    // Settings
    else if (data === "settings") {
      await handleSettings(ctx);
    }

    await ctx.answerCallbackQuery();
  } catch (err: any) {
    console.error(`Callback error [${data}]:`, err);
    await ctx.answerCallbackQuery({ text: "Something went wrong." }).catch(() => {});
  }
});

// ── Error handler ─────────────────────────────────────────────────────
bot.catch((err: BotError) => {
  const { ctx, error } = err;
  const chatId = ctx.chat?.id ?? "unknown";
  const update = ctx.update.update_id;

  if (error instanceof GrammyError) {
    console.error(`Grammy error [chat=${chatId} update=${update}]:`, error.description);
  } else if (error instanceof HttpError) {
    console.error(`HTTP error [chat=${chatId} update=${update}]:`, error.message);
  } else {
    console.error(`Unexpected error [chat=${chatId} update=${update}]:`, error);
  }
});

// ── Start ─────────────────────────────────────────────────────────────
console.log("Starting Strike bot...");
bot.start();
