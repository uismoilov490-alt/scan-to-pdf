const Anthropic = require('@anthropic-ai/sdk');
const { zodOutputFormat } = require('@anthropic-ai/sdk/helpers/zod');
const { z } = require('zod');
const { ApiError } = require('./errors');

const OCR_SYSTEM = `You transcribe text from a single document photo or scanned page for a document-scanner app used mainly in Uzbekistan.

Output ONLY the transcribed text — no commentary, no preamble, no markdown fences.

Rules:
- Keep the original script exactly as written. Cyrillic stays Cyrillic, Latin stays Latin. Never transliterate or translate.
- Uzbek Latin letters: write oʻ and gʻ with the modifier letter ʻ (U+02BB), and the tutuq belgisi as ʼ (U+02BC).
- Uzbek Cyrillic letters ў, қ, ғ, ҳ must be kept as they are, not replaced with Russian look-alikes.
- Preserve line breaks and paragraph order. For multi-column layouts read column by column.
- Tables: one row per line, cells separated by " | ".
- Handwriting: transcribe as best you can; put [?] after a word you are unsure of.
- Stamps, signatures and seals: write [muhr] or [imzo] in their place instead of guessing their text, unless the text is clearly readable.
- If the image contains no readable text, output nothing.`;

const OCR_HINTS = {
  auto: '',
  cyrillic: 'The document is mostly in Cyrillic script.',
  latin: 'The document is mostly in Latin script.',
  handwriting: 'The document is handwritten.',
};

const CATEGORIES = [
  'passport',
  'id_card',
  'receipt',
  'invoice',
  'contract',
  'certificate',
  'application',
  'letter',
  'form',
  'notes',
  'other',
];

const NameSchema = z.object({
  title: z.string(),
  category: z.enum(CATEGORIES),
});

const LANG_NAMES = { uz: 'Uzbek (Latin script)', ru: 'Russian', en: 'English' };

const TRANSLATE_SYSTEM = `You are a professional translator inside a document app used mainly in Uzbekistan.

Translate the user's text (or the text visible in the image) into the requested target language.

Rules:
- Translate faithfully and completely. Do not summarise, add explanations, or omit anything.
- Keep the structure: line breaks, paragraphs, numbering, lists. Tables stay one row per line with " | " between cells.
- Keep proper names, numbers, dates, document numbers, amounts and codes exactly as in the original.
- Official documents (applications, contracts, certificates) must keep an official register in the target language.
- Uzbek Latin output: use oʻ and gʻ with the modifier letter ʻ (U+02BB) and the tutuq belgisi ʼ (U+02BC).
- Uzbek Cyrillic output: use ў, қ, ғ, ҳ (not Russian look-alikes).
- If the source is already in the target language, return it unchanged.
- For an image: translate only the readable text; write [muhr] / [imzo] for stamps and signatures.
- detected_language: the ISO code of the source language (for Uzbek use "uz" for Latin script and "uz-Cyrl" for Cyrillic script).
- If there is no text to translate, return an empty translation.`;

const TRANSLATE_SCHEMA = {
  type: 'object',
  properties: {
    detected_language: { type: 'string' },
    translation: { type: 'string' },
  },
  required: ['detected_language', 'translation'],
  additionalProperties: false,
};

function createAi(config) {
  const client = config.anthropicApiKey
    ? new Anthropic({ apiKey: config.anthropicApiKey, maxRetries: 2, timeout: 90_000 })
    : null;

  function ensureClient() {
    if (!client) {
      throw new ApiError(503, 'AI_UNAVAILABLE', 'AI xizmati sozlanmagan');
    }
    return client;
  }

  function mapError(err) {
    if (err instanceof ApiError) return err;
    if (err instanceof Anthropic.RateLimitError) {
      return new ApiError(503, 'AI_BUSY', 'AI hozir band, birozdan keyin urinib ko\'ring');
    }
    if (err instanceof Anthropic.APIError) {
      // Kredit tugashi ham shu yerga tushadi (400) — logda aniq ko'rinsin.
      console.error(`[ai] Anthropic API error ${err.status}: ${err.message}`);
      return new ApiError(503, 'AI_UNAVAILABLE', 'AI xizmati vaqtincha ishlamayapti');
    }
    console.error('[ai] unexpected error', err);
    return new ApiError(503, 'AI_UNAVAILABLE', 'AI xizmati vaqtincha ishlamayapti');
  }

  async function ocr({ imageBase64, mediaType, hint }) {
    const c = ensureClient();
    const hintText = OCR_HINTS[hint] ?? '';
    try {
      const response = await c.beta.messages.create({
        model: config.ocrModel,
        max_tokens: 16000,
        betas: ['server-side-fallback-2026-07-01'],
        fallbacks: 'default',
        output_config: { effort: 'low' },
        system: OCR_SYSTEM,
        messages: [
          {
            role: 'user',
            content: [
              { type: 'image', source: { type: 'base64', media_type: mediaType, data: imageBase64 } },
              { type: 'text', text: `Transcribe this page.${hintText ? ' ' + hintText : ''}` },
            ],
          },
        ],
      });
      if (response.stop_reason === 'refusal') {
        throw new ApiError(422, 'AI_REFUSED', 'AI bu rasmni qayta ishlay olmadi');
      }
      const text = response.content
        .filter((b) => b.type === 'text')
        .map((b) => b.text)
        .join('')
        .trim();
      return { text, usage: response.usage, model: response.model };
    } catch (err) {
      throw mapError(err);
    }
  }

  async function suggestName({ imageBase64, mediaType, lang }) {
    const c = ensureClient();
    const language = LANG_NAMES[lang] ?? LANG_NAMES.uz;
    try {
      const response = await c.messages.parse({
        model: config.nameModel,
        max_tokens: 300,
        system:
          'You name scanned documents for a scanner app. Look at the first page and return a short, specific file title ' +
          `in ${language} (max 50 characters) that a person would recognise later, e.g. "Elektr hisobi — sentabr 2026" or "Ijara shartnomasi". ` +
          'Include the month/year or the person or company name if clearly visible. Do not include personal ID numbers, ' +
          'passport numbers or phone numbers in the title. Also pick the closest category.',
        messages: [
          {
            role: 'user',
            content: [
              { type: 'image', source: { type: 'base64', media_type: mediaType, data: imageBase64 } },
              { type: 'text', text: 'Name this document.' },
            ],
          },
        ],
        output_config: { format: zodOutputFormat(NameSchema) },
      });
      const parsed = response.parsed_output;
      if (!parsed) {
        throw new ApiError(502, 'AI_BAD_OUTPUT', 'AI javobi noto\'g\'ri');
      }
      return {
        title: sanitizeTitle(parsed.title),
        category: parsed.category,
        usage: response.usage,
        model: response.model,
      };
    } catch (err) {
      throw mapError(err);
    }
  }

  // text YOKI (imageBase64 + mediaType) beriladi. sourceName null bo'lsa — avtomatik aniqlash.
  async function translate({ text, imageBase64, mediaType, sourceName, targetName }) {
    const c = ensureClient();
    const instruction =
      `Translate ${sourceName ? `from ${sourceName} ` : '(detect the source language) '}` +
      `into ${targetName}.`;
    const content = imageBase64
      ? [
          { type: 'image', source: { type: 'base64', media_type: mediaType, data: imageBase64 } },
          { type: 'text', text: instruction },
        ]
      : [{ type: 'text', text: `${instruction}\n\n<text>\n${text}\n</text>` }];
    try {
      const response = await c.beta.messages.create({
        model: config.translateModel,
        max_tokens: 16000,
        betas: ['server-side-fallback-2026-07-01'],
        fallbacks: 'default',
        output_config: { effort: 'low', format: { type: 'json_schema', schema: TRANSLATE_SCHEMA } },
        system: TRANSLATE_SYSTEM,
        messages: [{ role: 'user', content }],
      });
      if (response.stop_reason === 'refusal') {
        throw new ApiError(422, 'AI_REFUSED', 'AI bu matnni tarjima qila olmadi');
      }
      if (response.stop_reason === 'max_tokens') {
        throw new ApiError(413, 'TEXT_TOO_LONG', 'Matn juda uzun, qismlarga bo\'lib yuboring');
      }
      const raw = response.content.filter((b) => b.type === 'text').map((b) => b.text).join('');
      let parsed;
      try {
        parsed = JSON.parse(raw);
      } catch {
        throw new ApiError(502, 'AI_BAD_OUTPUT', 'AI javobi noto\'g\'ri');
      }
      return {
        translation: String(parsed.translation ?? '').trim(),
        detected: String(parsed.detected_language ?? '').trim(),
        usage: response.usage,
        model: response.model,
      };
    } catch (err) {
      throw mapError(err);
    }
  }

  return { ocr, suggestName, translate, enabled: Boolean(client) };
}

// Fayl nomiga yaroqsiz belgilarni olib tashlaymiz.
function sanitizeTitle(title) {
  return title
    .replace(/[\\/:*?"<>|\r\n\t]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 60);
}

module.exports = { createAi, sanitizeTitle, CATEGORIES };
