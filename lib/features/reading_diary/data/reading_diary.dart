import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/library/domain/book.dart';

String diaryDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

/// Self-contained display metadata: deleting a library book never erases history.
class DiaryBook {
  const DiaryBook({
    required this.id,
    required this.title,
    this.cover,
    this.memberTitle,
  });
  final String id;
  final String title;
  final String? cover;
  final String? memberTitle;
  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'cover': cover};
  static DiaryBook fromJson(Map<String, dynamic> json) => DiaryBook(
    id: json['id'] as String,
    title: json['title'] as String,
    cover: json['cover'] as String?,
  );

  static Future<DiaryBook> snapshot(Book book, {Book? group}) async {
    final display = group ?? book;
    String? thumbnail;
    try {
      final bytes = display.coverPath != null
          ? await File(display.coverPath!).readAsBytes()
          : display.coverAssetPath != null
          ? (await rootBundle.load(
              display.coverAssetPath!,
            )).buffer.asUint8List()
          : null;
      if (bytes != null && bytes.length <= 20 * 1024 * 1024) {
        final codec = await ui.instantiateImageCodec(
          bytes,
          targetWidth: 96,
          targetHeight: 144,
          allowUpscaling: false,
        );
        try {
          final frame = await codec.getNextFrame();
          try {
            final png = await frame.image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            if (png != null && png.lengthInBytes <= 100000) {
              thumbnail = base64Encode(png.buffer.asUint8List());
            }
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      }
    } catch (_) {
      /* A missing cover must not block reading. */
    }
    return DiaryBook(
      id: display.id,
      title: display.title,
      cover: thumbnail,
      memberTitle: group == null ? null : book.title,
    );
  }
}

class DiaryEntry {
  const DiaryEntry(this.book, this.milliseconds, this.members);
  final DiaryBook book;
  final int milliseconds;
  final Map<String, int> members;
  Duration get duration => Duration(milliseconds: milliseconds);
  Map<String, dynamic> toJson() => {
    ...book.toJson(),
    'milliseconds': milliseconds,
    'members': members,
  };
  static DiaryEntry fromJson(Map<String, dynamic> json) {
    final ms = json['milliseconds'];
    final id = json['id'];
    final title = json['title'];
    final cover = json['cover'];
    if (id is! String ||
        id.isEmpty ||
        title is! String ||
        title.length > 2000 ||
        ms is! int ||
        ms < 0 ||
        ms > 86400000 ||
        (cover != null && (cover is! String || cover.length > 140000))) {
      throw const FormatException('Invalid reading diary');
    }
    if (cover != null) base64Decode(cover as String);
    final members = Map<String, int>.from(json['members'] as Map? ?? {});
    if (members.values.any((v) => v < 0 || v > ms)) {
      throw const FormatException('Invalid reading diary');
    }
    return DiaryEntry(DiaryBook.fromJson(json), ms, members);
  }
}

class DiaryDay {
  const DiaryDay(this.date, this.entries);
  final String date;
  final List<DiaryEntry> entries;
  Duration get duration =>
      Duration(milliseconds: entries.fold(0, (sum, e) => sum + e.milliseconds));
  Map<String, dynamic> toJson() => {
    'date': date,
    'entries': entries.map((e) => e.toJson()).toList(),
  };
  static DiaryDay fromJson(Map<String, dynamic> json) {
    final date = json['date'];
    if (date is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        diaryDate(DateTime.parse(date)) != date) {
      throw const FormatException('Invalid reading diary date');
    }
    final entries = (json['entries'] as List)
        .map((e) => DiaryEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    if (entries.map((e) => e.book.id).toSet().length != entries.length) {
      throw const FormatException('Duplicate reading diary entry');
    }
    return DiaryDay(date, entries);
  }
}

final readingDiaryProvider = Provider(
  (ref) => ReadingDiary(ref.watch(localStorageProvider)),
);

/// Serialized, local-only daily records. No analytics consent or network involved.
class ReadingDiary extends ChangeNotifier {
  ReadingDiary(this.storage);
  final LocalStorage storage;
  static const prefix = 'reading_diary_v1_';
  Future<void> _queue = Future.value();
  Map<String, DiaryDay>? _cache;
  Future<T> _serialize<T>(Future<T> Function() work) {
    final result = _queue.then((_) => work());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<List<DiaryDay>> load() => _serialize(() async {
    if (_cache == null) {
      final rows = await storage.getStringEntriesByPrefix(prefix);
      final days = rows.values.map(
        (s) =>
            DiaryDay.fromJson(Map<String, dynamic>.from(jsonDecode(s) as Map)),
      );
      _cache = {for (final day in days) day.date: day};
    }
    final days = _cache!.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return days;
  });
  Future<void> add(
    DiaryBook book,
    DateTime start,
    Duration elapsed,
  ) => _serialize(() async {
    if (elapsed.inMilliseconds <= 0) return;
    // A monotonic elapsed duration is authoritative; wall time only assigns dates.
    var cursor = start;
    var remaining = elapsed.inMilliseconds;
    while (remaining > 0) {
      final midnight = DateTime(cursor.year, cursor.month, cursor.day + 1);
      final available = midnight.difference(cursor).inMilliseconds;
      final amount = remaining < available ? remaining : available;
      if (amount <= 0) break;
      final key = '$prefix${diaryDate(cursor)}';
      final raw = await storage.getString(key);
      final entries = raw == null
          ? <DiaryEntry>[]
          : DiaryDay.fromJson(
              Map<String, dynamic>.from(jsonDecode(raw) as Map),
            ).entries;
      final index = entries.indexWhere((e) => e.book.id == book.id);
      final old = index < 0 ? null : entries[index];
      final members = {...?old?.members};
      if (book.memberTitle != null) {
        members.update(
          book.memberTitle!,
          (v) => v + amount,
          ifAbsent: () => amount,
        );
      }
      final entry = DiaryEntry(
        DiaryBook(
          id: book.id,
          title: book.title,
          cover: book.cover ?? old?.book.cover,
        ),
        ((old?.milliseconds ?? 0) + amount).clamp(0, 86400000),
        members,
      );
      if (index < 0) {
        entries.add(entry);
      } else {
        entries[index] = entry;
      }
      final updated = DiaryDay(diaryDate(cursor), entries);
      await storage.setString(key, jsonEncode(updated.toJson()));
      _cache?[updated.date] = updated;
      cursor = midnight;
      remaining -= amount;
    }
    notifyListeners();
  });
  Future<void> flush() => _queue;
  void refresh() {
    _cache = null;
    notifyListeners();
  }

  static List<DiaryDay> validateBackup(Object? raw) {
    if (raw == null) return [];
    if (raw is! List || raw.length > 36600) {
      throw const FormatException('Invalid reading diary backup');
    }
    return raw
        .map((e) => DiaryDay.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Merge maxima rather than sum: restoring the same backup cannot double time.
  static Future<Map<String, String>> mergeBackup(
    LocalStorage storage,
    Object? raw,
  ) async {
    final result = <String, String>{};
    for (final day in validateBackup(raw)) {
      final key = '$prefix${day.date}';
      final current = result[key] ?? await storage.getString(key);
      final entries = current == null
          ? <DiaryEntry>[]
          : DiaryDay.fromJson(
              Map<String, dynamic>.from(jsonDecode(current) as Map),
            ).entries;
      for (final incoming in day.entries) {
        final index = entries.indexWhere((e) => e.book.id == incoming.book.id);
        if (index < 0) {
          entries.add(incoming);
        } else if (incoming.milliseconds > entries[index].milliseconds) {
          entries[index] = incoming;
        }
      }
      result[key] = jsonEncode(DiaryDay(day.date, entries).toJson());
    }
    return result;
  }
}
