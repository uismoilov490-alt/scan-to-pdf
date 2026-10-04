const { ApiError } = require('./errors');

// Kun chegarasi Toshkent vaqti bo'yicha (UTC+5), foydalanuvchi uchun tushunarli.
function today(now = Date.now()) {
  return new Date(now + 5 * 3600 * 1000).toISOString().slice(0, 10);
}

function createQuota(db, config) {
  const getStmt = db.prepare(
    'SELECT count FROM usage_daily WHERE uid = ? AND day = ? AND kind = ?',
  );
  const addStmt = db.prepare(`
    INSERT INTO usage_daily (uid, day, kind, count) VALUES (?, ?, ?, ?)
    ON CONFLICT (uid, day, kind) DO UPDATE SET count = count + excluded.count
  `);

  function used(uid, kind) {
    return getStmt.get(uid, today(), kind)?.count ?? 0;
  }

  function status(uid, isPro) {
    const limit = isPro ? config.proDailyUnits : config.freeDailyUnits;
    const u = used(uid, 'units');
    return { used: u, limit, remaining: Math.max(0, limit - u) };
  }

  // Avval tekshiramiz, AI muvaffaqiyatli ishlagandan keyingina yozamiz —
  // xato bo'lsa foydalanuvchi limiti yonmaydi.
  function assertUnits(uid, isPro, units) {
    const s = status(uid, isPro);
    if (s.remaining < units) {
      throw new ApiError(429, 'QUOTA_EXCEEDED', 'Kunlik AI limiti tugadi', {
        quota: s,
        pro: isPro,
      });
    }
  }

  function assertNameCap(uid) {
    if (used(uid, 'name') >= config.nameDailyCap) {
      throw new ApiError(429, 'NAME_CAP_EXCEEDED', 'Kunlik nom berish chegarasi tugadi');
    }
  }

  function add(uid, kind, n) {
    addStmt.run(uid, today(), kind, n);
  }

  return { status, assertUnits, assertNameCap, add };
}

module.exports = { createQuota, today };
