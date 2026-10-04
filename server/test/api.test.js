const test = require('node:test');
const assert = require('node:assert/strict');
const { openDb } = require('../src/db');
const { createApp } = require('../src/app');
const { ApiError } = require('../src/errors');
const { sanitizeTitle } = require('../src/ai');

const baseConfig = {
  translateModel: 'test-translate',
  translateCharsPerUnit: 10,
  translateMaxChars: 50,
  freeDailyUnits: 2,
  proDailyUnits: 5,
  nameDailyCap: 2,
  maxImageBytes: 1024,
  ocrModel: 'test-ocr',
  nameModel: 'test-name',
  androidPackage: 'uz.test',
  playServiceAccountFile: '',
  proProductIds: ['scan_pro_monthly'],
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
  const db = openDb(':memory:');
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
  return { call, close: () => server.close() };
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

test('bepul foydalanuvchi limiti tugaydi va 429 qaytadi', async (t) => {
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

  // Boshqa foydalanuvchining limiti alohida
  assert.equal((await s.call('POST', '/v1/ai/ocr', { uid: 'u2', body: img })).status, 200);
});

test('Pro foydalanuvchi kattaroq limit oladi', async (t) => {
  const s = await start();
  t.after(s.close);
  const me = await s.call('GET', '/v1/me', { uid: 'pro-user' });
  assert.equal(me.json.pro, true);
  assert.equal(me.json.quota.limit, 5);
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
  const s = await start({ config: { freeDailyUnits: 3 } });
  t.after(s.close);
  const ok = await s.call('POST', '/v1/ai/translate', { uid: 'u1', body: { text: 'Привет', source: 'auto', target: 'uz' } });
  assert.equal(ok.status, 200);
  assert.equal(ok.json.translation, '[auto→Uzbek (Latin script)] Привет');
  assert.equal(ok.json.detected, 'ru');
  assert.equal(ok.json.quota.used, 1);

  // 25 belgi / 10 = 3 birlik — qolgan 2 tadan ko'p
  const over = await s.call('POST', '/v1/ai/translate', { uid: 'u1', body: { text: 'a'.repeat(25), target: 'en' } });
  assert.equal(over.status, 429);

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
