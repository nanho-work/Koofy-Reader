import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/reader/domain/reading_progress.dart';

void main() {
  test('ReadingProgress persists anchor and locator fields', () {
    final progress = ReadingProgress(
      bookId: 'book_1',
      positionRatio: 0.42,
      contentOffset: 1234,
      doublePageStartOffset: 1200,
      pageIndex: 0,
      totalPages: 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      anchor: ReadingAnchor(
        chapterId: 'ch_12',
        paragraphIndex: 45,
        charOffset: 128,
      ),
      locator: const ReadingLocator(
        chapterId: 'ch_12',
        paragraphIndex: 45,
        charOffset: 128,
        globalOffset: 1234,
        progression: 0.42,
      ),
    );

    final decoded = ReadingProgress.fromRaw(progress.toRaw());

    expect(decoded, isNotNull);
    expect(decoded!.bookId, 'book_1');
    expect(decoded.contentOffset, 1234);
    expect(decoded.doublePageStartOffset, 1200);
    expect(decoded.anchor, isNotNull);
    expect(decoded.anchor!.chapterId, 'ch_12');
    expect(decoded.anchor!.paragraphIndex, 45);
    expect(decoded.anchor!.charOffset, 128);
    expect(decoded.locator, isNotNull);
    expect(decoded.locator!.globalOffset, 1234);
    expect(decoded.locator!.progression, 0.42);
  });

  test('ReadingProgress keeps backward compatibility without anchor', () {
    final legacyRaw = jsonEncode({
      'bookId': 'legacy_book',
      'positionRatio': 0.7,
      'contentOffset': 987,
      'pageIndex': 1,
      'totalPages': 20,
      'updatedAt': 1700000000000,
    });

    final decoded = ReadingProgress.fromRaw(legacyRaw);

    expect(decoded, isNotNull);
    expect(decoded!.bookId, 'legacy_book');
    expect(decoded.contentOffset, 987);
    expect(decoded.anchor, isNull);
    expect(decoded.locator, isNull);
  });

  test('ReadingProgress ignores malformed anchor payload', () {
    final malformedAnchorRaw = jsonEncode({
      'bookId': 'book_x',
      'positionRatio': 0.1,
      'contentOffset': 50,
      'pageIndex': 0,
      'totalPages': 0,
      'updatedAt': 1700000000000,
      'anchor': {
        'chapterId': 'ch_1',
        'paragraphIndex': 'bad_type',
        'charOffset': 4,
      },
    });

    final decoded = ReadingProgress.fromRaw(malformedAnchorRaw);

    expect(decoded, isNotNull);
    expect(decoded!.anchor, isNull);
    expect(decoded.contentOffset, 50);
  });

  test('ReadingProgress parses numeric offsets from legacy payloads', () {
    final raw = jsonEncode({
      'bookId': 'book_num',
      'positionRatio': 0.3,
      'contentOffset': 42.9,
      'doublePageStartOffset': 40.2,
      'pageIndex': 2.0,
      'totalPages': 10.0,
      'updatedAt': 1700000000000,
    });

    final decoded = ReadingProgress.fromRaw(raw);

    expect(decoded, isNotNull);
    expect(decoded!.contentOffset, 42);
    expect(decoded.doublePageStartOffset, 40);
    expect(decoded.pageIndex, 2);
    expect(decoded.totalPages, 10);
  });
}
