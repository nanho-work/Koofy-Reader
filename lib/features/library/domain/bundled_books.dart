import 'book.dart';

/// Stable identities: a replacement story must never inherit another book's
/// reading position, bookmarks, cover override or completion state.
abstract final class BundledBooks {
  static const mermaidId = 'sample_mermaid_001';
  static const mermaidSeries = '인어공주는 파도를 벤다';
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
  static const defaults = [mermaid, guide];
  static const supported = [mermaid, guide, legacy];
  static Set<String> get ids => supported.map((book) => book.id).toSet();

  static bool matches(Book book, Book bundled) =>
      !book.isLocalFile &&
      book.id == bundled.id &&
      book.assetPath == bundled.assetPath;
  static bool isSupported(Book book) =>
      supported.any((bundled) => matches(book, bundled));
  static bool hasContinuation(Book book) => matches(book, mermaid);
}
