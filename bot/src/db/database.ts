import Database from "better-sqlite3";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DB_PATH = path.join(__dirname, "../../data/strike.db");

let db: Database.Database;

export function getDb(): Database.Database {
  if (!db) {
    db = new Database(DB_PATH);
    db.pragma("journal_mode = WAL");
    db.pragma("foreign_keys = ON");
    initTables(db);
  }
  return db;
}

function initTables(db: Database.Database) {
  db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      telegram_id INTEGER PRIMARY KEY,
      username TEXT,
      wallet_address TEXT NOT NULL,
      wallet_id TEXT NOT NULL,
      created_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS bets (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      telegram_id INTEGER NOT NULL,
      market_address TEXT NOT NULL,
      side TEXT NOT NULL CHECK(side IN ('up', 'down')),
      amount TEXT NOT NULL,
      tx_hash TEXT,
      status TEXT DEFAULT 'pending' CHECK(status IN ('pending', 'confirmed', 'failed')),
      created_at TEXT DEFAULT (datetime('now')),
      FOREIGN KEY (telegram_id) REFERENCES users(telegram_id)
    );

    CREATE INDEX IF NOT EXISTS idx_bets_user ON bets(telegram_id);
    CREATE INDEX IF NOT EXISTS idx_bets_market ON bets(market_address);
  `);
}

export interface DbUser {
  telegram_id: number;
  username: string | null;
  wallet_address: string;
  wallet_id: string;
  created_at: string;
}

export interface DbBet {
  id: number;
  telegram_id: number;
  market_address: string;
  side: "up" | "down";
  amount: string;
  tx_hash: string | null;
  status: "pending" | "confirmed" | "failed";
  created_at: string;
}

export function getUser(telegramId: number): DbUser | undefined {
  return getDb().prepare("SELECT * FROM users WHERE telegram_id = ?").get(telegramId) as DbUser | undefined;
}

export function createUser(telegramId: number, username: string | null, walletAddress: string, walletId: string): DbUser {
  getDb().prepare(
    "INSERT INTO users (telegram_id, username, wallet_address, wallet_id) VALUES (?, ?, ?, ?)"
  ).run(telegramId, username, walletAddress, walletId);
  return getUser(telegramId)!;
}

export function getUserBets(telegramId: number): DbBet[] {
  return getDb().prepare("SELECT * FROM bets WHERE telegram_id = ? ORDER BY created_at DESC LIMIT 20").all(telegramId) as DbBet[];
}

export function insertBet(telegramId: number, marketAddress: string, side: "up" | "down", amount: string): number {
  const result = getDb().prepare(
    "INSERT INTO bets (telegram_id, market_address, side, amount) VALUES (?, ?, ?, ?)"
  ).run(telegramId, marketAddress, side, amount);
  return Number(result.lastInsertRowid);
}

export function getBettorsByMarket(marketAddress: string): DbBet[] {
  return getDb().prepare(
    "SELECT * FROM bets WHERE market_address = ? AND status = 'confirmed' GROUP BY telegram_id"
  ).all(marketAddress) as DbBet[];
}

export function getUserCount(): number {
  const row = getDb().prepare("SELECT COUNT(*) as count FROM users").get() as { count: number };
  return row.count;
}

export function getBetCount(): { total: number; confirmed: number; failed: number } {
  const rows = getDb().prepare(
    "SELECT status, COUNT(*) as count FROM bets GROUP BY status"
  ).all() as Array<{ status: string; count: number }>;
  const result = { total: 0, confirmed: 0, failed: 0 };
  for (const r of rows) {
    result.total += r.count;
    if (r.status === "confirmed") result.confirmed = r.count;
    if (r.status === "failed") result.failed = r.count;
  }
  return result;
}

export function updateBetTx(betId: number, txHash: string, status: "confirmed" | "failed") {
  getDb().prepare("UPDATE bets SET tx_hash = ?, status = ? WHERE id = ?").run(txHash, status, betId);
}
