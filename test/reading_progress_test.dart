import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/reader/domain/reading_progress.dart';

void main() {
  test('ReadingProgress persists anchor fields', () {
    final progress = ReadingProgress(
      bookId: 'book_1',
      positionRatio: 0.42,
      contentOffset: 1234,
      pageIndex: 0,
      totalPages: 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      anchor: ReadingAnchor(
        chapterId: 'ch_12',
        paragraphIndex: 45,
        charOffset: 128,
      ),
    );

    final decoded = ReadingProgress.fromRaw(progress.toRaw());

    expect(decoded, isNotNull);
    expect(decoded!.bookId, 'book_1');
    expect(decoded.contentOffset, 1234);
    expect(decoded.anchor, isNotNull);
    expect(decoded.anchor!.chapterId, 'ch_12');
    expect(decoded.anchor!.paragraphIndex, 45);
    expect(decoded.anchor!.charOffset, 128);
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
}
