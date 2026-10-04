/// Tarjima tillari. Kodlar server/src/languages.js bilan bir xil bo'lishi shart.
class TranslateLanguage {
  final String code;
  final String nativeName;
  final String uz;
  final String ru;
  final String en;

  const TranslateLanguage(
    this.code,
    this.nativeName,
    this.uz,
    this.ru,
    this.en,
  );

  /// Ilova tiliga mos nom (ro'yxatda ona-til nomi ostida ko'rsatiladi).
  String localName(String locale) => switch (locale) {
    'ru' => ru,
    'en' => en,
    _ => uz,
  };

  static const auto = 'auto';

  /// Ro'yxat tepasida turadigan eng ko'p ishlatiladigan tillar
  static const popularCodes = ['uz', 'uz-Cyrl', 'ru', 'en'];

  static const all = <TranslateLanguage>[
    TranslateLanguage(
      'uz',
      'Oʻzbekcha (lotin)',
      'Oʻzbek (lotin)',
      'Узбекский (латиница)',
      'Uzbek (Latin)',
    ),
    TranslateLanguage(
      'uz-Cyrl',
      'Ўзбекча (кирилл)',
      'Oʻzbek (kirill)',
      'Узбекский (кириллица)',
      'Uzbek (Cyrillic)',
    ),
    TranslateLanguage('ru', 'Русский', 'Rus', 'Русский', 'Russian'),
    TranslateLanguage('en', 'English', 'Ingliz', 'Английский', 'English'),
    TranslateLanguage(
      'kaa',
      'Qaraqalpaqsha',
      'Qoraqalpoq',
      'Каракалпакский',
      'Karakalpak',
    ),
    TranslateLanguage('kk', 'Қазақша', 'Qozoq', 'Казахский', 'Kazakh'),
    TranslateLanguage('ky', 'Кыргызча', 'Qirgʻiz', 'Киргизский', 'Kyrgyz'),
    TranslateLanguage('tg', 'Тоҷикӣ', 'Tojik', 'Таджикский', 'Tajik'),
    TranslateLanguage('tk', 'Türkmençe', 'Turkman', 'Туркменский', 'Turkmen'),
    TranslateLanguage('tr', 'Türkçe', 'Turk', 'Турецкий', 'Turkish'),
    TranslateLanguage(
      'az',
      'Azərbaycanca',
      'Ozarbayjon',
      'Азербайджанский',
      'Azerbaijani',
    ),
    TranslateLanguage('ko', '한국어', 'Koreys', 'Корейский', 'Korean'),
    TranslateLanguage('ja', '日本語', 'Yapon', 'Японский', 'Japanese'),
    TranslateLanguage('zh', '中文', 'Xitoy', 'Китайский', 'Chinese'),
    TranslateLanguage('ar', 'العربية', 'Arab', 'Арабский', 'Arabic'),
    TranslateLanguage('fa', 'فارسی', 'Fors', 'Персидский', 'Persian'),
    TranslateLanguage('de', 'Deutsch', 'Nemis', 'Немецкий', 'German'),
    TranslateLanguage('fr', 'Français', 'Fransuz', 'Французский', 'French'),
    TranslateLanguage('es', 'Español', 'Ispan', 'Испанский', 'Spanish'),
    TranslateLanguage('it', 'Italiano', 'Italyan', 'Итальянский', 'Italian'),
    TranslateLanguage(
      'pt',
      'Português',
      'Portugal',
      'Португальский',
      'Portuguese',
    ),
    TranslateLanguage('pl', 'Polski', 'Polyak', 'Польский', 'Polish'),
    TranslateLanguage('uk', 'Українська', 'Ukrain', 'Украинский', 'Ukrainian'),
    TranslateLanguage(
      'be',
      'Беларуская',
      'Belarus',
      'Белорусский',
      'Belarusian',
    ),
    TranslateLanguage('hi', 'हिन्दी', 'Hind', 'Хинди', 'Hindi'),
    TranslateLanguage('ur', 'اردو', 'Urdu', 'Урду', 'Urdu'),
    TranslateLanguage(
      'id',
      'Bahasa Indonesia',
      'Indonez',
      'Индонезийский',
      'Indonesian',
    ),
    TranslateLanguage('ms', 'Bahasa Melayu', 'Malay', 'Малайский', 'Malay'),
    TranslateLanguage(
      'vi',
      'Tiếng Việt',
      'Vyetnam',
      'Вьетнамский',
      'Vietnamese',
    ),
    TranslateLanguage('th', 'ไทย', 'Tay', 'Тайский', 'Thai'),
    TranslateLanguage('he', 'עברית', 'Ivrit', 'Иврит', 'Hebrew'),
    TranslateLanguage('el', 'Ελληνικά', 'Grek', 'Греческий', 'Greek'),
    TranslateLanguage('nl', 'Nederlands', 'Golland', 'Нидерландский', 'Dutch'),
    TranslateLanguage('sv', 'Svenska', 'Shved', 'Шведский', 'Swedish'),
    TranslateLanguage('cs', 'Čeština', 'Chex', 'Чешский', 'Czech'),
    TranslateLanguage('ro', 'Română', 'Rumin', 'Румынский', 'Romanian'),
    TranslateLanguage('hu', 'Magyar', 'Venger', 'Венгерский', 'Hungarian'),
    TranslateLanguage('bg', 'Български', 'Bolgar', 'Болгарский', 'Bulgarian'),
    TranslateLanguage('ka', 'ქართული', 'Gruzin', 'Грузинский', 'Georgian'),
    TranslateLanguage('hy', 'Հայերեն', 'Arman', 'Армянский', 'Armenian'),
    TranslateLanguage('mn', 'Монгол', 'Moʻgʻul', 'Монгольский', 'Mongolian'),
  ];

  static TranslateLanguage? byCode(String code) {
    for (final l in all) {
      if (l.code == code) return l;
    }
    return null;
  }
}
