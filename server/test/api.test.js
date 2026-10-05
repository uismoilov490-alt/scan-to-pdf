const test = require('node:test');
const assert = require('node:assert/strict');
const { openDb } = require('../src/db');
const { createApp } = require('../src/app');
const { ApiError } = require('../src/errors');
const { sanitizeTitle } = require('../src/ai');

const baseConfig = {
  translateModel: 'test-translate',
  visionModel: 'test-vision',
  translateCharsPerUnit: 10,
  translateMaxChars: 50,
  freeDailyFiles: 2,
  freeFileMaxPages: 3,
  planUnits: { weekly: 4, monthly: 5 },
  nameDailyCap: 2,
  maxImageBytes: 1024,
  ocrModel: 'test-ocr',
  nameModel: 'test-name',
  androidPackage: 'uz.test',
  playServiceAccountFile: '',
  products: { scan_pro_weekly: 'weekly', scan_pro_monthly: 'monthly' },
  devProUids: ['pro-user'],
};

function fakeAi({ failOcr = false } = {}) {
  return {
    enabled: true,
    async ocr({ hint }) {
      if (failOcr) throw new ApiError(503, 'AI_UNAVAILABLE', 'down');
      return { text: `matn:${hint}`, usage: { input_tokens: 10, output_tokens: 5 }, model: 'test-ocr' };
    },
    async suggestName() {
      return { title: 'Elektr hisobi', category: 'invoice', usage: {}, model: 'test-name' };
    },
    async vision({ task, languageName }) {
      return { result: { task, languageName }, usage: {}, model: 'test-vision' };
    },
    async translate({ text, imageBase64, sourceName, targetName }) {
      return {
        translation: `[${sourceName ?? 'auto'}→${targetName}] ${imageBase64 ? 'rasm' : text}`,
        detected: 'ru',
        usage: {},
        model: 'test-translate',
      };
    },
  };
}

async function start(opts = {}) {
  const db = opts.db ?? openDb(':memory:');
  const app = createApp({
    config: { ...baseConfig, ...opts.config },
    db,
    ai: opts.ai ?? fakeAi(),
    verifyToken: async (token) => {
      if (!token.startsWith('ok:')) throw new Error('bad token');
      return { uid: token.slice(3) };
    },
  });
  const server = app.listen(0);
  await new Promise((r) => server.once('listening', r));
  const base = `http://127.0.0.1:${server.address().port}`;
  const call = (method, path, { uid, body } = {}) =>
    fetch(base + path, {
      method,
      headers: {
        'content-type': 'application/json',
        ...(uid ? { authorization: `Bearer ok:${uid}` } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    }).then(async (r) => ({ status: r.status, json: await r.json().catch(() => null) }));
  return { call, db, close: () => server.close() };
}

const img = { image: 'aGVsbG8=', mediaType: 'image/jpeg' };

test('health ochiq, me esa login talab qiladi', async (t) => {
  const s = await start();
  t.after(s.close);
  assert.equal((await s.call('GET', '/v1/health')).status, 200);
  const r = await s.call('GET', '/v1/me');
  assert.equal(r.status, 401);
  assert.equal(r.json.error.code, 'AUTH_REQUIRED');
});

test('bepul: kunlik fayllar soni sanaladi, limit tugasa 429', async (t) => {
  const s = await start();
  t.after(s.close);
  for (let i = 0; i < 2; i++) {
    const r = await s.call('POST', '/v1/ai/ocr', { uid: 'u1', body: { ...img, hint: 'cyrillic' } });
    assert.equal(r.status, 200);
    assert.equal(r.json.text, 'matn:cyrillic');
  }
  const over = await s.call('POST', '/v1/ai/ocr', { uid: 'u1', body: img });
  assert.equal(over.status, 429);
  assert.equal(over.json.error.code, 'QUOTA_EXCEEDED');
  assert.equal(over.json.error.quota.remaining, 0);
  assert.equal(over.json.error.pro, false);
  assert.equal(over.json.error.quota.unit, 'file');

  // Boshqa foydalanuvchining limiti alohida
  assert.equal((await s.call('POST', '/v1/ai/ocr', { uid: 'u2', body: img })).status, 200);
});

test('bepul: bitta fileId ichidagi sahifalar bitta fayl, lekin sahifa chegarasi bor', async (t) => {
  const s = await start();
  t.after(s.close);
  const body = { ...img, fileId: 'fayl-aaaa-1' };
  for (let i = 0; i < 3; i++) {
    const r = await s.call('POST', '/v1/ai/ocr', { uid: 'u1', body });
    assert.equal(r.status, 200);
    assert.equal(r.json.quota.used, 1);
  }
  const big = await s.call('POST', '/v1/ai/ocr', { uid: 'u1', body });
  assert.equal(big.status, 429);
  assert.equal(big.json.error.code, 'FILE_TOO_BIG');

  // Ikkinchi fayl hali mumkin, uchinchisi yo'q (limit 2)
  assert.equal((await s.call('POST', '/v1/ai/ocr', { uid: 'u1', body: { ...img, fileId: 'fayl-bbbb-2' } })).status, 200);
  const third = await s.call('POST', '/v1/ai/ocr', { uid: 'u1', body: { ...img, fileId: 'fayl-cccc-3' } });
  assert.equal(third.json.error.code, 'QUOTA_EXCEEDED');
  // Boshlangan faylni davom ettirish mumkin emas — u allaqachon to'la
  // (lekin 2-faylni davom ettirish mumkin)
  assert.equal((await s.call('POST', '/v1/ai/ocr', { uid: 'u1', body: { ...img, fileId: 'fayl-bbbb-2' } })).status, 200);
});

test('bepul: kechagi fayllar bugungi limitga kirmaydi', async (t) => {
  const s = await start();
  t.after(s.close);
  const ins = s.db.prepare('INSERT INTO free_files (uid, file_id, day, units, created_at) VALUES (?, ?, ?, ?, ?)');
  ins.run('u1', 'eski-fayl-1', '2000-01-01', 1, 0);
  ins.run('u1', 'eski-fayl-2', '2000-01-01', 1, 0);
  const me = await s.call('GET', '/v1/me', { uid: 'u1' });
  assert.equal(me.json.quota.used, 0);
  assert.equal((await s.call('POST', '/v1/ai/ocr', { uid: 'u1', body: img })).status, 200);
});

test('Pro: tarif bo\'yicha davr limiti', async (t) => {
  const s = await start();
  t.after(s.close);
  const me = await s.call('GET', '/v1/me', { uid: 'pro-user' });
  assert.equal(me.json.pro, true);
  assert.equal(me.json.plan, 'monthly');
  assert.equal(me.json.quota.unit, 'page');
  assert.equal(me.json.quota.limit, 5);

  // Haftalik obunachi: davr = obuna tugashidan 7 kun oldin
  const now = Date.now();
  s.db.prepare(
    'INSERT INTO subscriptions (purchase_token, uid, product_id, expires_at, state, checked_at) VALUES (?, ?, ?, ?, ?, ?)',
  ).run('tok', 'w1', 'scan_pro_weekly', now + 2 * 86400000, 'SUBSCRIPTION_STATE_ACTIVE', now);
  // Davrdan oldingi sarf hisobga olinmaydi
  s.db.prepare('INSERT INTO usage_log (uid, units, file_id, created_at) VALUES (?, ?, ?, ?)')
    .run('w1', 4, null, now - 6 * 86400000);
  const w = await s.call('GET', '/v1/me', { uid: 'w1' });
  assert.equal(w.json.plan, 'weekly');
  assert.equal(w.json.quota.limit, 4);
  assert.equal(w.json.quota.used, 0);
  assert.equal(w.json.quota.resetsAt, now + 2 * 86400000);
  for (let i = 0; i < 4; i++) {
    assert.equal((await s.call('POST', '/v1/ai/ocr', { uid: 'w1', body: img })).status, 200);
  }
  const over = await s.call('POST', '/v1/ai/ocr', { uid: 'w1', body: img });
  assert.equal(over.status, 429);
  assert.equal(over.json.error.pro, true);
});

test('AI xato bersa limit yonmaydi', async (t) => {
  const s = await start({ ai: fakeAi({ failOcr: true }) });
  t.after(s.close);
  const r = await s.call('POST', '/v1/ai/ocr', { uid: 'u1', body: img });
  assert.equal(r.status, 503);
  const me = await s.call('GET', '/v1/me', { uid: 'u1' });
  assert.equal(me.json.quota.used, 0);
});

test('katta yoki noto\'g\'ri rasm rad etiladi', async (t) => {
  const s = await start();
  t.after(s.close);
  const big = await s.call('POST', '/v1/ai/ocr', { uid: 'u1', body: { image: 'A'.repeat(4000) } });
  assert.equal(big.status, 413);
  const gif = await s.call('POST', '/v1/ai/ocr', { uid: 'u1', body: { ...img, mediaType: 'image/gif' } });
  assert.equal(gif.status, 400);
  const none = await s.call('POST', '/v1/ai/ocr', { uid: 'u1', body: {} });
  assert.equal(none.status, 400);
});

test('nom berish limitga kirmaydi, lekin o\'z chegarasi bor', async (t) => {
  const s = await start();
  t.after(s.close);
  for (let i = 0; i < 2; i++) {
    const r = await s.call('POST', '/v1/ai/suggest-name', { uid: 'u1', body: img });
    assert.equal(r.status, 200);
    assert.equal(r.json.title, 'Elektr hisobi');
  }
  const over = await s.call('POST', '/v1/ai/suggest-name', { uid: 'u1', body: img });
  assert.equal(over.status, 429);
  const me = await s.call('GET', '/v1/me', { uid: 'u1' });
  assert.equal(me.json.quota.used, 0);
});

test('billing sozlanmagan bo\'lsa aniq xato qaytadi', async (t) => {
  const s = await start();
  t.after(s.close);
  const r = await s.call('POST', '/v1/billing/verify', {
    uid: 'u1',
    body: { productId: 'scan_pro_monthly', purchaseToken: 'x' },
  });
  assert.equal(r.status, 503);
  assert.equal(r.json.error.code, 'BILLING_NOT_CONFIGURED');
  const unknown = await s.call('POST', '/v1/billing/verify', {
    uid: 'u1',
    body: { productId: 'boshqa', purchaseToken: 'x' },
  });
  assert.equal(unknown.status, 400);
});

test('hisobni o\'chirish ma\'lumotlarni tozalaydi', async (t) => {
  const s = await start();
  t.after(s.close);
  await s.call('POST', '/v1/ai/ocr', { uid: 'u1', body: img });
  assert.equal((await s.call('DELETE', '/v1/me', { uid: 'u1' })).status, 200);
  const me = await s.call('GET', '/v1/me', { uid: 'u1' });
  assert.equal(me.json.quota.used, 0);
});

test('sanitizeTitle fayl nomiga yaroqsiz belgilarni olib tashlaydi', () => {
  assert.equal(sanitizeTitle('Hisob: sentabr/2026 "yangi"'), 'Hisob sentabr 2026 yangi');
  assert.equal(sanitizeTitle('a'.repeat(100)).length, 60);
});

test('tarjima: matn, til tekshiruvi va limit birliklari', async (t) => {
  const s = await start();
  t.after(s.close);
  const ok = await s.call('POST', '/v1/ai/translate', { uid: 'u1', body: { text: 'Привет', source: 'auto', target: 'uz', fileId: 'tarjima-0001' } });
  assert.equal(ok.status, 200);
  assert.equal(ok.json.translation, '[auto→Uzbek (Latin script)] Привет');
  assert.equal(ok.json.detected, 'ru');
  assert.equal(ok.json.quota.used, 1);

  // Shu faylga 25 belgi / 10 = 3 birlik qo'shilsa — 1+3 > 3 sahifa chegarasi
  const over = await s.call('POST', '/v1/ai/translate', { uid: 'u1', body: { text: 'a'.repeat(25), target: 'en', fileId: 'tarjima-0001' } });
  assert.equal(over.status, 429);
  assert.equal(over.json.error.code, 'FILE_TOO_BIG');

  const badLang = await s.call('POST', '/v1/ai/translate', { uid: 'u1', body: { text: 'x', target: 'xx' } });
  assert.equal(badLang.status, 400);
  const badSrc = await s.call('POST', '/v1/ai/translate', { uid: 'u1', body: { text: 'x', source: 'yy', target: 'en' } });
  assert.equal(badSrc.status, 400);
  const tooLong = await s.call('POST', '/v1/ai/translate', { uid: 'u1', body: { text: 'a'.repeat(51), target: 'en' } });
  assert.equal(tooLong.status, 413);
  const empty = await s.call('POST', '/v1/ai/translate', { uid: 'u1', body: { text: '   ', target: 'en' } });
  assert.equal(empty.status, 400);
});

test('tarjima: rasm 1 birlik, manba tili berilsa nomi uzatiladi', async (t) => {
  const s = await start();
  t.after(s.close);
  const r = await s.call('POST', '/v1/ai/translate', { uid: 'u1', body: { ...img, source: 'uz-Cyrl', target: 'ru' } });
  assert.equal(r.status, 200);
  assert.equal(r.json.translation, '[Uzbek (Cyrillic script)→Russian] rasm');
  assert.equal(r.json.quota.used, 1);
});

test('vision: vazifa tekshiriladi, til nomi uzatiladi, limit sarflanadi', async (t) => {
  const s = await start();
  t.after(s.close);
  const bad = await s.call('POST', '/v1/ai/vision', { uid: 'u1', body: { ...img, task: 'hack' } });
  assert.equal(bad.status, 400);
  const proto = await s.call('POST', '/v1/ai/vision', { uid: 'u1', body: { ...img, task: 'toString' } });
  assert.equal(proto.status, 400);

  const ok = await s.call('POST', '/v1/ai/vision', { uid: 'u1', body: { ...img, task: 'solve', lang: 'uz' } });
  assert.equal(ok.status, 200);
  assert.equal(ok.json.result.task, 'solve');
  assert.equal(ok.json.result.languageName, 'Uzbek (Latin script)');
  assert.equal(ok.json.quota.used, 1);

  const unknownLang = await s.call('POST', '/v1/ai/vision', { uid: 'u1', body: { ...img, task: 'table', lang: 'xx' } });
  assert.equal(unknownLang.json.result.languageName, 'English');
  // Bepul kunlik limit (testda 2 fayl) tugagach — 429
  const over = await s.call('POST', '/v1/ai/vision', { uid: 'u1', body: { ...img, task: 'formula' } });
  assert.equal(over.status, 429);
});
