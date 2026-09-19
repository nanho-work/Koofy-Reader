import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/native_reader/application/native_reader_services.dart';
import 'package:koofy_reader/features/native_reader/data/reading_publication_preparer.dart';
import 'package:koofy_reader/features/native_reader/migration/legacy_reader_archive.dart';
import 'package:koofy_reader/features/native_reader/presentation/native_reader_launch_page.dart';

/// Archived offsets and bookmarks remain reachable after the renderer is removed.
/// Only a verified TXT mapping enables a direct jump. EPUB flattening offsets
/// cannot be presented as real EPUB locations; show their original context.
class LegacyRecordsPage extends ConsumerStatefulWidget {
  const LegacyRecordsPage({super.key, required this.book});
  final Book book;
  @override
  ConsumerState<LegacyRecordsPage> createState() => _LegacyRecordsPageState();
}

class _LegacyRecordsPageState extends ConsumerState<LegacyRecordsPage> {
  late final Future<(LegacyBookRecord?, PreparedReadingPublication?, String?)>
  _data = _load();

  Future<(LegacyBookRecord?, PreparedReadingPublication?, String?)>
  _load() async {
    final services = await ref.read(nativeReaderServicesProvider.future);
    final record = await ref
        .read(legacyReaderArchiveProvider)
        .loadBook(widget.book.id, support: services.supportDirectory);
    try {
      return (record, await services.preparer.prepare(book: widget.book), null);
    } catch (error) {
      // Even an unsupported/missing publication must not hide archived notes.
      return (record, null, error.toString());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('이전 기록과 북마크')),
    body: FutureBuilder(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('기록을 읽지 못했습니다.\n${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final (record, publication, error) = snapshot.data!;
        if (record == null) {
          return const Center(child: Text('이 책에는 이전 기록이 없습니다.'));
        }
        Widget location(String title, int? offset) {
          final map = publication?.textMap;
          final locator =
              offset != null && map != null && record.cachedText == map.text
              ? map.locatorAt(offset)
              : null;
          return ListTile(
            title: Text(title),
            subtitle: Text(record.excerpt(offset)),
            trailing: locator == null
                ? const Icon(Icons.info_outline)
                : const Icon(Icons.chevron_right),
            onTap: locator == null
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => NativeReaderLaunchPage(
                        book: widget.book,
                        initialLocatorJson: locator,
                        initialContentRevision: publication!.contentRevision,
                      ),
                    ),
                  ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.book.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            const Text(
              '이전 기록 원본은 그대로 보존되어 있습니다. 확인된 본문 위치는 눌러서 열 수 있습니다. 위치를 변환할 수 없는 기록은 아래 문장과 원본 기록을 참고해 목차에서 찾아 주세요.',
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(error),
              ),
            if (record.hasProgress) location('이전에 읽던 위치', record.offset),
            for (var i = 0; i < record.bookmarks.length; i++)
              location('북마크 ${i + 1}', record.bookmarks[i]),
            if (record.bookmarks.isEmpty)
              const ListTile(title: Text('저장된 이전 북마크가 없습니다.')),
            ExpansionTile(
              title: const Text('보존된 원본 기록 보기'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    '읽기 위치\n${record.rawProgress ?? "없음"}\n\n북마크\n${record.rawBookmarks ?? "없음"}',
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NativeReaderLaunchPage(book: widget.book),
                ),
              ),
              child: const Text('책 열기'),
            ),
          ],
        );
      },
    ),
  );
}
