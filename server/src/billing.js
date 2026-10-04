const fs = require('node:fs');
const { GoogleAuth } = require('google-auth-library');
const { ApiError } = require('./errors');

// Bekor qilingan (CANCELED) obuna ham to'langan muddat tugaguncha amal qiladi.
const VALID_STATES = new Set([
  'SUBSCRIPTION_STATE_ACTIVE',
  'SUBSCRIPTION_STATE_IN_GRACE_PERIOD',
  'SUBSCRIPTION_STATE_CANCELED',
]);

const DAY_MS = 24 * 3600 * 1000;
const WEEK_MS = 7 * DAY_MS;

function createBilling(db, config) {
  const configured =
    Boolean(config.playServiceAccountFile) && fs.existsSync(config.playServiceAccountFile);

  const auth = configured
    ? new GoogleAuth({
        keyFile: config.playServiceAccountFile,
        scopes: ['https://www.googleapis.com/auth/androidpublisher'],
      })
    : null;

  const activeStmt = db.prepare(
    'SELECT product_id, expires_at FROM subscriptions WHERE uid = ? AND expires_at > ? ' +
      'ORDER BY expires_at DESC LIMIT 1',
  );
  const upsertStmt = db.prepare(`
    INSERT INTO subscriptions (purchase_token, uid, product_id, expires_at, state, checked_at)
    VALUES (?, ?, ?, ?, ?, ?)
    ON CONFLICT (purchase_token) DO UPDATE SET
      uid = excluded.uid, product_id = excluded.product_id,
      expires_at = excluded.expires_at, state = excluded.state, checked_at = excluded.checked_at
  `);

  // Joriy to'lov davri boshi: limit shu paytdan beri sarflangan sahifalardan hisoblanadi
  function periodStart(plan, expiresAt) {
    if (plan === 'weekly') return expiresAt - WEEK_MS;
    const d = new Date(expiresAt);
    d.setUTCMonth(d.getUTCMonth() - 1);
    return d.getTime();
  }

  function proStatus(uid) {
    if (config.devProUids.includes(uid)) {
      return { pro: true, plan: 'monthly', proUntil: null, periodStart: Date.now() - 30 * DAY_MS };
    }
    const row = activeStmt.get(uid, Date.now());
    const plan = row && config.products[row.product_id];
    if (!plan) return { pro: false, plan: 'free', proUntil: null, periodStart: null };
    return { pro: true, plan, proUntil: row.expires_at, periodStart: periodStart(plan, row.expires_at) };
  }

  async function verify(uid, { productId, purchaseToken }) {
    if (!config.products[productId]) {
      throw new ApiError(400, 'BAD_PRODUCT', 'Noma\'lum mahsulot');
    }
    if (!auth) {
      throw new ApiError(503, 'BILLING_NOT_CONFIGURED', 'Obunani tekshirish hali sozlanmagan');
    }

    const client = await auth.getClient();
    const url =
      `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/` +
      `${encodeURIComponent(config.androidPackage)}/purchases/subscriptionsv2/tokens/` +
      encodeURIComponent(purchaseToken);

    let data;
    try {
      ({ data } = await client.request({ url }));
    } catch (err) {
      const status = err?.response?.status;
      if (status === 400 || status === 404 || status === 410) {
        throw new ApiError(400, 'PURCHASE_INVALID', 'Xarid topilmadi');
      }
      console.error('[billing] Play API error', status, err?.message);
      throw new ApiError(503, 'BILLING_UNAVAILABLE', 'Obunani hozir tekshirib bo\'lmadi');
    }

    const item = (data.lineItems ?? []).find((li) => li.productId === productId);
    const expiresAt = item?.expiryTime ? Date.parse(item.expiryTime) : 0;
    const state = data.subscriptionState ?? 'UNKNOWN';
    const effectiveExpiry = VALID_STATES.has(state) ? expiresAt : 0;

    upsertStmt.run(purchaseToken, uid, productId, effectiveExpiry, state, Date.now());
    return proStatus(uid);
  }

  return { proStatus, verify, configured };
}

module.exports = { createBilling };
