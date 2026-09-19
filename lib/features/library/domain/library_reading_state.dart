import 'dart:convert';

import 'package:koofy_reader/features/native_reader/data/native_reader_store.dart';
import 'package:koofy_reader/features/native_reader/migration/legacy_reading_progress.dart';

enum LibraryBookStatus { unread, reading, finished }

class LibraryReadingState {
  const LibraryReadingState({
    this.needsMigration = false,
    this.progression,
    this.lastReadAt,
    this.chapterTitle,
    this.finished = false,
  });

  final bool needsMigration;
  final double? progression;
  final DateTime? lastReadAt;
  final String? chapterTitle;
  final bool finished;

  String get progressLabel => needsMigration
      ? '이전 읽기 기록 확인'
      : progression == null
      ? '읽던 위치 저장됨'
      : '${(progression! * 100).floor()}% 읽음';
}

/// Presentation only: never translate an old text offset into a Readium locator.
Map<String, LibraryReadingState> mergeLibraryReadingStates({
  required Map<String, ReadingProgress> legacy,
  required List<NativeLibraryPosition> native,
  required Map<String, bool> completion,
}) {
  final result = <String, LibraryReadingState>{};
  for (final entry in legacy.entries) {
    final progress = entry.value;
    result[entry.key] = LibraryReadingState(
      needsMigration: true,
      progression: progress.positionRatio.isFinite
          ? progress.positionRatio.clamp(0, 1)
          : null,
      lastReadAt: progress.updatedAt,
      finished: completion[entry.key] ?? false,
    );
  }
  for (final position in native) {
    // Once a Readium checkpoint exists it owns resume, regardless of timestamp.
    try {
      final locator = jsonDecode(position.locatorJson);
      if (locator is! Map ||
          locator['href'] is! String ||
          (locator['href'] as String).isEmpty) {
        continue;
      }
      final locations = locator['locations'];
      final ratio = locations is Map ? locations['totalProgression'] : null;
      final title = locator['title'];
      result[position.publicationId] = LibraryReadingState(
        // Resource progression is NOT whole-book progression.
        progression: ratio is num && ratio.isFinite && ratio >= 0 && ratio <= 1
            ? ratio.toDouble()
            : null,
        lastReadAt: position.lastOpenedAt,
        chapterTitle: title is String && title.trim().isNotEmpty
            ? title.trim()
            : null,
        finished: completion[position.publicationId] ?? false,
      );
    } on FormatException {
      // A damaged presentation field must not hide the rest of the library.
    }
  }
  return result;
}
