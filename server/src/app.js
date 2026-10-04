const path = require('node:path');
const express = require('express');
const { ApiError } = require('./errors');
const { requireAuth } = require('./auth');
const { createQuota } = require('./quota');
const { createBilling } = require('./billing');
const { LANGUAGES } = require('./languages');

const MEDIA_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp']);

// db, ai va verifyToken tashqaridan beriladi — testlarda soxtasini qo'yish uchun.
function createApp({ config, db, ai, verifyToken }) {
  const quota = createQuota(db, config);
  const billing = createBilling(db, config);
  const auth = requireAuth(verifyToken);

  const logCall = db.prepare(`
    INSERT INTO ai_calls (uid, kind, model, input_tokens, output_tokens, ok, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `);

  function readImage(body) {
    const { image, mediaType = 'image/jpeg' } = body ?? {};
    if (typeof image !== 'string' || image.length === 0) {
      throw new ApiError(400, 'BAD_REQUEST', 'Rasm yuborilmadi');
    }
    if (!MEDIA_TYPES.has(mediaType)) {
      throw new ApiError(400, 'BAD_REQUEST', 'Rasm formati qo\'llab-quvvatlanmaydi');
    }
    const bytes = Math.floor((image.length * 3) / 4);
    if (bytes > config.maxImageBytes) {
      throw new ApiError(413, 'IMAGE_TOO_LARGE', 'Rasm juda katta');
    }
    return { imageBase64: image, mediaType };
  }

  // Ko'p sahifali fayl bir nechta so'rovda yuboriladi — ilova ularni bitta fileId
  // bilan bog'laydi (bepul rejada fayllar soni shu bo'yicha sanaladi).
  function readFileId(body) {
    const id = body?.fileId;
    return typeof id === 'string' && /^[A-Za-z0-9_-]{8,64}$/.test(id) ? id : null;
  }

  function me(uid) {
    const sub = billing.proStatus(uid);
    return { pro: sub.pro, plan: sub.plan, proUntil: sub.proUntil, quota: quota.status(uid, sub) };
  }

  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', 'loopback');

  // Play Market talab qiladigan ochiq sahifalar: /privacy, /delete-account
  app.use(express.static(path.join(__dirname, '..', 'public'), { extensions: ['html'] }));

  const v1 = express.Router();
  v1.use(express.json({ limit: '8mb' }));

  v1.get('/health', (_req, res) => {
    res.json({ ok: true, ai: ai.enabled, billing: billing.configured });
  });

  v1.get('/me', auth, (req, res) => {
    res.json(me(req.uid));
  });

  // Hisobni o'chirish: serverdagi barcha yozuvlar o'chadi
  // (Firebase foydalanuvchisini ilovaning o'zi o'chiradi).
  v1.delete('/me', auth, (req, res) => {
    for (const table of ['usage_daily', 'usage_log', 'free_files', 'subscriptions', 'ai_calls']) {
      db.prepare(`DELETE FROM ${table} WHERE uid = ?`).run(req.uid);
    }
    res.json({ ok: true });
  });

  v1.post('/ai/ocr', auth, async (req, res, next) => {
    try {
      const img = readImage(req.body);
      const hint = typeof req.body.hint === 'string' ? req.body.hint : 'auto';
      const fileId = readFileId(req.body);
      const sub = billing.proStatus(req.uid);
      quota.assertUnits(req.uid, sub, 1, fileId);

      let result;
      try {
        result = await ai.ocr({ ...img, hint });
      } catch (err) {
        logCall.run(req.uid, 'ocr', config.ocrModel, null, null, 0, Date.now());
        throw err;
      }
      quota.charge(req.uid, sub, 1, fileId);
      logCall.run(
        req.uid, 'ocr', result.model,
        result.usage?.input_tokens ?? null, result.usage?.output_tokens ?? null,
        1, Date.now(),
      );
      res.json({ text: result.text, quota: quota.status(req.uid, sub) });
    } catch (err) {
      next(err);
    }
  });

  v1.post('/ai/suggest-name', auth, async (req, res, next) => {
    try {
      const img = readImage(req.body);
      const lang = typeof req.body.lang === 'string' ? req.body.lang : 'uz';
      quota.assertNameCap(req.uid);

      const result = await ai.suggestName({ ...img, lang });
      quota.addName(req.uid);
      logCall.run(
        req.uid, 'name', result.model,
        result.usage?.input_tokens ?? null, result.usage?.output_tokens ?? null,
        1, Date.now(),
      );
      res.json({ title: result.title, category: result.category });
    } catch (err) {
      next(err);
    }
  });

  // Tarjima: { text } yoki { image, mediaType } + { source: 'auto'|kod, target: kod }
  v1.post('/ai/translate', auth, async (req, res, next) => {
    try {
      const { source = 'auto', target, text } = req.body ?? {};
      if (!LANGUAGES[target]) {
        throw new ApiError(400, 'BAD_LANGUAGE', 'Tarjima tili noto\'g\'ri');
      }
      if (source !== 'auto' && !LANGUAGES[source]) {
        throw new ApiError(400, 'BAD_LANGUAGE', 'Manba tili noto\'g\'ri');
      }

      let input;
      let units;
      if (typeof req.body?.image === 'string') {
        input = readImage(req.body);
        units = 1;
      } else {
        const clean = typeof text === 'string' ? text.trim() : '';
        if (!clean) throw new ApiError(400, 'BAD_REQUEST', 'Tarjima uchun matn yo\'q');
        if (clean.length > config.translateMaxChars) {
          throw new ApiError(413, 'TEXT_TOO_LONG', 'Matn juda uzun', { maxChars: config.translateMaxChars });
        }
        input = { text: clean };
        units = Math.ceil(clean.length / config.translateCharsPerUnit);
      }

      const fileId = readFileId(req.body);
      const sub = billing.proStatus(req.uid);
      quota.assertUnits(req.uid, sub, units, fileId);

      let result;
      try {
        result = await ai.translate({
          ...input,
          sourceName: source === 'auto' ? null : LANGUAGES[source],
          targetName: LANGUAGES[target],
        });
      } catch (err) {
        logCall.run(req.uid, 'translate', config.translateModel, null, null, 0, Date.now());
        throw err;
      }
      quota.charge(req.uid, sub, units, fileId);
      logCall.run(
        req.uid, 'translate', result.model,
        result.usage?.input_tokens ?? null, result.usage?.output_tokens ?? null,
        1, Date.now(),
      );
      res.json({
        translation: result.translation,
        detected: LANGUAGES[result.detected] ? result.detected : null,
        quota: quota.status(req.uid, sub),
      });
    } catch (err) {
      next(err);
    }
  });

  v1.post('/billing/verify', auth, async (req, res, next) => {
    try {
      const { productId, purchaseToken } = req.body ?? {};
      if (typeof productId !== 'string' || typeof purchaseToken !== 'string') {
        throw new ApiError(400, 'BAD_REQUEST', 'productId va purchaseToken kerak');
      }
      await billing.verify(req.uid, { productId, purchaseToken });
      res.json(me(req.uid));
    } catch (err) {
      next(err);
    }
  });

  app.use('/v1', v1);

  app.use((_req, _res, next) => next(new ApiError(404, 'NOT_FOUND', 'Topilmadi')));

  // eslint-disable-next-line no-unused-vars
  app.use((err, _req, res, _next) => {
    if (err?.type === 'entity.too.large') {
      err = new ApiError(413, 'IMAGE_TOO_LARGE', 'Rasm juda katta');
    } else if (err?.type === 'entity.parse.failed') {
      err = new ApiError(400, 'BAD_REQUEST', 'Noto\'g\'ri JSON');
    }
    if (!(err instanceof ApiError)) {
      console.error('[api] unhandled', err);
      err = new ApiError(500, 'INTERNAL', 'Server xatosi');
    }
    res.status(err.status).json({ error: { code: err.code, message: err.message, ...err.extra } });
  });

  return app;
}

module.exports = { createApp };
