// Barcha sozlamalar shu yerda — server boshqa joyga ko'chirilganda faqat .env o'zgaradi.

function int(name, fallback) {
  const v = parseInt(process.env[name] ?? '', 10);
  return Number.isFinite(v) ? v : fallback;
}

function list(name) {
  return (process.env[name] ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
}

const config = {
  port: int('PORT', 4100),
  host: process.env.HOST ?? '127.0.0.1',
  dbPath: process.env.DB_PATH ?? './data/scan.db',

  firebaseProjectId: process.env.FIREBASE_PROJECT_ID ?? 'scan-to-pdf-7fdf1',

  anthropicApiKey: process.env.ANTHROPIC_API_KEY ?? '',
  ocrModel: process.env.OCR_MODEL ?? 'claude-sonnet-5-5',
  nameModel: process.env.NAME_MODEL ?? 'claude-haiku-4-5',
  translateModel: process.env.TRANSLATE_MODEL ?? 'claude-sonnet-5-5',
  // Jadval, masala yechish va formula uchun
  visionModel: process.env.VISION_MODEL ?? 'claude-sonnet-5-5',
  // Tarjima: shuncha belgi = 1 birlik limit; bitta so'rovda eng ko'pi
  translateCharsPerUnit: int('TRANSLATE_CHARS_PER_UNIT', 4000),
  translateMaxChars: int('TRANSLATE_MAX_CHARS', 20000),

  // AI limiti (1 birlik = 1 sahifa/rasm o'qish):
  // bepul — kuniga N ta fayl, bitta faylda eng ko'pi M sahifa;
  // Pro — tarif davri (oy) ichida N sahifa
  freeDailyFiles: int('FREE_DAILY_FILES', 5),
  freeFileMaxPages: int('FREE_FILE_MAX_PAGES', 20),
  planUnits: {
    monthly: int('MONTHLY_UNITS', 100),
  },
  // Avtomatik nom berish limitga kirmaydi, lekin suiiste'mol uchun alohida chegara
  nameDailyCap: int('NAME_DAILY_CAP', 50),

  maxImageBytes: int('MAX_IMAGE_BYTES', 5 * 1024 * 1024),

  // Google Play obunasini tekshirish
  androidPackage: process.env.ANDROID_PACKAGE ?? 'uz.myhujjat.scan_to_pdf',
  playServiceAccountFile: process.env.PLAY_SERVICE_ACCOUNT_FILE ?? '',
  // Play Console'dagi obuna ID'si → tarif
  products: {
    scan_pro_monthly: 'monthly',
  },

  // Sinov uchun: bu Firebase UID'lar Play tekshiruvisiz Pro hisoblanadi
  devProUids: list('DEV_PRO_UIDS'),
};

module.exports = config;
