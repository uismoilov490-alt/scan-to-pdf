const { randomUUID } = require('node:crypto');
const { ApiError } = require('./errors');

// Kun chegarasi Toshkent vaqti bo'yicha (UTC+5), foydalanuvchi uchun tushunarli.
function today(now = Date.now()) {
  return new Date(now + 5 * 3600 * 1000).toISOString().slice(0, 10);
}

// Ikki xil limit:
//  - bepul: kuniga N ta fayl (fayl ichidagi sahifalar bitta fayl hisoblanadi,
//    lekin bitta faylga ham sahifa chegarasi bor — suiiste'mol bo'lmasin);
//  - Pro: tarif davri (oy) ichida N ta sahifa.
// `sub` — billing.proStatus() natijasi.
function createQuota(db, config) {
  const getDaily = db.prepare(
    'SELECT count FROM usage_daily WHERE uid = ? AND day = ? AND kind = ?',
  );
  const addDaily = db.prepare(`
    INSERT INTO usage_daily (uid, day, kind, count) VALUES (?, ?, ?, ?)
    ON CONFLICT (uid, day, kind) DO UPDATE SET count = count + excluded.count
  `);
  const sumSince = db.prepare(
    'SELECT COALESCE(SUM(units), 0) AS n FROM usage_log WHERE uid = ? AND created_at >= ?',
  );
  const logUsage = db.prepare(
    'INSERT INTO usage_log (uid, units, file_id, created_at) VALUES (?, ?, ?, ?)',
  );
  const countFree = db.prepare('SELECT COUNT(*) AS n FROM free_files WHERE uid = ? AND day = ?');
  const getFree = db.prepare('SELECT units FROM free_files WHERE uid = ? AND file_id = ?');
  const addFree = db.prepare(`
    INSERT INTO free_files (uid, file_id, day, units, created_at) VALUES (?, ?, ?, ?, ?)
    ON CONFLICT (uid, file_id) DO UPDATE SET units = units + excluded.units
  `);

  function status(uid, sub) {
    if (sub.pro) {
      const limit = config.planUnits[sub.plan] ?? 0;
      const used = sumSince.get(uid, sub.periodStart).n;
      return {
        plan: sub.plan,
        unit: 'page',
        used,
        limit,
        remaining: Math.max(0, limit - used),
        resetsAt: sub.proUntil,
      };
    }
    const used = countFree.get(uid, today()).n;
    return {
      plan: 'free',
      unit: 'file',
      used,
      limit: config.freeDailyFiles,
      remaining: Math.max(0, config.freeDailyFiles - used),
      maxPagesPerFile: config.freeFileMaxPages,
    };
  }

  // Avval tekshiramiz, AI muvaffaqiyatli ishlagandan keyingina yozamiz (charge) —
  // xato bo'lsa foydalanuvchi limiti yonmaydi.
  function assertUnits(uid, sub, units, fileId) {
    const s = status(uid, sub);
    if (sub.pro) {
      if (s.remaining < units) {
        throw new ApiError(429, 'QUOTA_EXCEEDED', 'Tarif limiti tugadi', { quota: s, pro: true });
      }
      return;
    }
    const file = fileId ? getFree.get(uid, fileId) : undefined;
    if (!file && s.remaining < 1) {
      throw new ApiError(429, 'QUOTA_EXCEEDED', 'Bugungi bepul AI limiti tugadi', { quota: s, pro: false });
    }
    if ((file?.units ?? 0) + units > config.freeFileMaxPages) {
      throw new ApiError(429, 'FILE_TOO_BIG', 'Bepul rejada fayl juda katta', { quota: s, pro: false });
    }
  }

  function charge(uid, sub, units, fileId) {
    const now = Date.now();
    logUsage.run(uid, units, fileId ?? null, now);
    // fileId berilmasa har bir so'rov alohida fayl hisoblanadi
    if (!sub.pro) addFree.run(uid, fileId ?? randomUUID(), today(now), units, now);
  }

  function assertNameCap(uid) {
    if ((getDaily.get(uid, today(), 'name')?.count ?? 0) >= config.nameDailyCap) {
      throw new ApiError(429, 'NAME_CAP_EXCEEDED', 'Kunlik nom berish chegarasi tugadi');
    }
  }

  function addName(uid) {
    addDaily.run(uid, today(), 'name', 1);
  }

  return { status, assertUnits, charge, assertNameCap, addName };
}

module.exports = { createQuota, today };
