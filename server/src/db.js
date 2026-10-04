// SQLite (Node'ning o'zidagi node:sqlite) — bitta fayl, yangi serverga nusxalash oson.
const fs = require('node:fs');
const path = require('node:path');
const { DatabaseSync } = require('node:sqlite');

function openDb(dbPath) {
  if (dbPath !== ':memory:') {
    fs.mkdirSync(path.dirname(path.resolve(dbPath)), { recursive: true });
  }
  const db = new DatabaseSync(dbPath);
  db.exec(`
    PRAGMA journal_mode = WAL;

    CREATE TABLE IF NOT EXISTS usage_daily (
      uid   TEXT NOT NULL,
      day   TEXT NOT NULL,          -- YYYY-MM-DD (Toshkent vaqti)
      kind  TEXT NOT NULL,          -- 'units' | 'name'
      count INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (uid, day, kind)
    );

    CREATE TABLE IF NOT EXISTS subscriptions (
      purchase_token TEXT PRIMARY KEY,
      uid            TEXT NOT NULL,
      product_id     TEXT NOT NULL,
      expires_at     INTEGER NOT NULL,  -- unix ms
      state          TEXT NOT NULL,
      checked_at     INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS subscriptions_uid ON subscriptions(uid);

    -- AI sarfi (sahifa birliklarida): Pro davr limiti shundan hisoblanadi
    CREATE TABLE IF NOT EXISTS usage_log (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      uid        TEXT NOT NULL,
      units      INTEGER NOT NULL,
      file_id    TEXT,
      created_at INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS usage_log_uid ON usage_log(uid, created_at);

    -- Bepul rejada AI bilan ishlangan fayllar (kuniga N ta; day — boshlangan kun)
    CREATE TABLE IF NOT EXISTS free_files (
      uid        TEXT NOT NULL,
      file_id    TEXT NOT NULL,
      day        TEXT NOT NULL,
      units      INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      PRIMARY KEY (uid, file_id)
    );

    CREATE TABLE IF NOT EXISTS ai_calls (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      uid           TEXT NOT NULL,
      kind          TEXT NOT NULL,
      model         TEXT NOT NULL,
      input_tokens  INTEGER,
      output_tokens INTEGER,
      ok            INTEGER NOT NULL,
      created_at    INTEGER NOT NULL
    );
  `);
  return db;
}

module.exports = { openDb };
