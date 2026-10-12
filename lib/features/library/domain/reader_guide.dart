import 'package:koofy_reader/core/localization/app_language.dart';

/// The guide is app-owned content. Its library identity stays stable across
/// languages; each translated source produces a separate reading revision.
abstract final class ReaderGuide {
  static const id = 'sample_2';
  static const canonicalAsset = 'assets/books/sample_2.txt';
  static String get language => AppLanguage.instance.code;
  static String get title => switch (language) {
    'en' => 'Getting started with Koofy Reader',
    'ja' => 'Koofy Readerの使い方',
    _ => '쿠피리더 시작하기',
  };
  static String get description => switch (language) {
    'en' => 'From adding books to reading your way',
    'ja' => '本の追加から自分好みの読書設定まで',
    _ => '책 가져오기부터 나만의 독서 설정까지',
  };
  static String get sourceAsset => language == 'ko'
      ? canonicalAsset
      : 'assets/books/reader_guide_$language.txt';
  static String get coverAsset => language == 'ko'
      ? 'assets/books/reader_guide.png'
      : 'assets/books/reader_guide_$language.png';
}
