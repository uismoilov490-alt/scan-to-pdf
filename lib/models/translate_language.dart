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
    TranslateLanguage('tr', 'Türkçe', 'Turk', 'Турецкий', 'Turkish'),
    TranslateLanguage('zh', '中文', 'Xitoy', 'Китайский', 'Chinese'),
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
    TranslateLanguage(
      'be',
      'Беларуская',
      'Belarus',
      'Белорусский',
      'Belarusian',
    ),
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
