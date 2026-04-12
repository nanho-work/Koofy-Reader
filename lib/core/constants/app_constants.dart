class AppConstants {
  static const String adHideExpiryKey = 'ad_hide_expiry';
  static const String readingProgressPrefix = 'reader_progress_';
  static const String readingBookmarkPrefix = 'reader_bookmark_';
  static const String recentBooksKey = 'recent_books';
  static const String readerSettingsKey = 'reader_settings';
  static const String readerSearchHistoryKey = 'reader_search_history';
  static const String readerStructureIndexPrefix = 'reader_structure_index_';
  static const String localBooksKey = 'library_local_books';
  static const String localBooksBackupKey = 'library_local_books_backup';
  static const String storageSchemaVersionKey = 'storage_schema_version';

  static const int maxTxtBytes = 20 * 1024 * 1024;
  static const int maxEpubBytes = 40 * 1024 * 1024;

  static const double libraryGridChildAspectRatio = 0.58;
  static const double libraryGridMainAxisSpacing = 18;
  static const double libraryGridCrossAxisSpacing = 14;
  static const List<double> libraryGridWidthBreakpoints = <double>[
    1400,
    1200,
    980,
    760,
  ];
  static const List<int> libraryGridCounts = <int>[8, 7, 6, 5];
  static const int libraryGridDefaultCount = 3;

  static const List<int> adRewardHourOptions = <int>[5, 6];
}
