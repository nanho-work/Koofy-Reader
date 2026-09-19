class AppConstants {
  static const String adHideExpiryKey = 'ad_hide_expiry';
  static const String readingProgressPrefix = 'reader_progress_';
  static const String readingBookmarkPrefix = 'reader_bookmark_';
  static const String recentBooksKey = 'recent_books';
  static const String readerSettingsKey = 'reader_settings';
  static const String readerSearchHistoryKey = 'reader_search_history';
  static const String localBooksKey = 'library_local_books';
  static const String localBooksBackupKey = 'library_local_books_backup';
  static const String hiddenBooksKey = 'library_hidden_books';

  static const int maxTxtBytes = 20 * 1024 * 1024;
  static const int maxEpubBytes = 40 * 1024 * 1024;

  static const List<int> adRewardHourOptions = <int>[5, 6];
}
