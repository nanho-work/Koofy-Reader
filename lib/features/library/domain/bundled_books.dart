import 'package:koofy_reader/core/localization/app_language.dart';
import 'book.dart';

/// Stable identities: a replacement story must never inherit another book's
/// reading position, bookmarks, cover override or completion state.
abstract final class BundledBooks {
  static const mermaidId = 'sample_mermaid_001';
  static String get mermaidSeries => switch (AppLanguage.instance.code) {
    'en' => 'The Mermaid Princess Cuts the Waves',
    'ja' => '人魚姫は波を斬る',
    _ => '인어공주는 파도를 벤다',
  };
  static const continuationUrl = 'koofy-reader://catalog/mermaid';
  static const retainLegacyKey = 'library_retain_dawn_sample_v1';

  static const mermaid = Book(
    id: mermaidId,
    title: '인어공주는 파도를 벤다 1화',
    author: '',
    description: '물이 듣지 않는 날 · 오프라인으로 읽는 첫 이야기',
    sourceType: BookSourceType.asset,
    assetPath: 'assets/books/sample_mermaid_001.txt',
    coverAssetPath: 'assets/books/sample_mermaid_001.jpg',
  );
  static const guide = Book(
    id: 'sample_2',
    title: '쿠피리더 시작하기',
    author: 'Koofy Team',
    description: '책 가져오기부터 나만의 독서 설정까지',
    sourceType: BookSourceType.asset,
    assetPath: 'assets/books/sample_2.txt',
    coverAssetPath: 'assets/books/reader_guide.png',
  );
  static const legacy = Book(
    id: 'sample_1',
    title: '새벽의 쿠피',
    author: 'Koofy Studio',
    description: '오프라인에서도 바로 열 수 있는 샘플 소설',
    sourceType: BookSourceType.asset,
    assetPath: 'assets/books/sample_1.txt',
  );
  static const mermaidEn = Book(
    id: 'sample_mermaid_001_en',
    title: 'The Mermaid Princess Cuts the Waves — Chapter 1',
    author: '',
    description: 'The Day the Water Would Not Answer',
    sourceType: BookSourceType.asset,
    assetPath: 'assets/books/sample_mermaid_001_en.txt',
    coverAssetPath: 'assets/books/sample_mermaid_001_en.jpg',
  );
  static const mermaidJa = Book(
    id: 'sample_mermaid_001_ja',
    title: '人魚姫は波を斬る — 第1話',
    author: '',
    description: '水が応えなくなった日',
    sourceType: BookSourceType.asset,
    assetPath: 'assets/books/sample_mermaid_001_ja.txt',
    coverAssetPath: 'assets/books/sample_mermaid_001_ja.jpg',
  );
  static Book get localizedMermaid => switch (AppLanguage.instance.code) {
    'en' => mermaidEn,
    'ja' => mermaidJa,
    _ => mermaid,
  };
  static List<Book> get defaults => [localizedMermaid, guide];
  static String languageOf(Book book) => matches(book, mermaidEn)
      ? 'en'
      : matches(book, mermaidJa)
      ? 'ja'
      : 'ko';
  static const supported = [mermaid, mermaidEn, mermaidJa, guide, legacy];
  static Set<String> get ids => supported.map((book) => book.id).toSet();

  static bool matches(Book book, Book bundled) =>
      !book.isLocalFile &&
      book.id == bundled.id &&
      book.assetPath == bundled.assetPath;
  static bool isSupported(Book book) =>
      supported.any((bundled) => matches(book, bundled));
  static bool hasContinuation(Book book) =>
      [mermaid, mermaidEn, mermaidJa].any((sample) => matches(book, sample));
}
