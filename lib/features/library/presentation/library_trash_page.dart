import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/features/library/data/library_trash_service.dart';
import 'package:koofy_reader/features/library/data/library_reading_repository.dart';
import 'package:koofy_reader/features/native_reader/migration/legacy_reader_archive.dart';
import 'package:koofy_reader/features/ads/presentation/ad_overlay_insets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/library/data/library_trash_store.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/data/book_group_repository.dart';
import 'package:koofy_reader/features/library/domain/book_group.dart';

class LibraryTrashPage extends ConsumerStatefulWidget {
  const LibraryTrashPage({super.key});
  @override
  ConsumerState<LibraryTrashPage> createState() => _LibraryTrashPageState();
}

class _LibraryTrashPageState extends ConsumerState<LibraryTrashPage> {
  late final store = LibraryTrashStore(ref.read(localStorageProvider));
  late Future<Map<String, Map<String, dynamic>>> entries = store.load();
  bool busy = false;
  bool _deleting = false;
  Future<int>? _size;

  void _reload() {
    setState(() {
      entries = store.load();
      _size = null;
    });
  }

  Future<void> restore(String id, Map<String, dynamic> entry) async {
    setState(() => busy = true);
    try {
      if (entry['deleting'] == true) throw StateError(tr("삭제 중인 항목입니다."));
      if (entry['kind'] == 'bundle') {
        await ref.read(bookGroupRepositoryProvider).restoreBundle(id);
      } else if (entry['kind'] == 'group') {
        final books = await ref.read(bookRepositoryProvider).getBooks();
        await ref
            .read(bookGroupRepositoryProvider)
            .restoreGroup(
              BookGroup.fromJson(
                Map<String, dynamic>.from(entry['group'] as Map),
              ),
              books.map((b) => b.id).toSet(),
            );
      } else {
        await store.restoreBook(id);
      }
      ref.invalidate(booksProvider);
      ref.invalidate(bookGroupsProvider);
      if (mounted) {
        _reload();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr("복원했습니다. 다른 묶음에 배치한 책의 현재 소속은 유지합니다."))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr("복원하지 못했습니다. 기록은 보존했습니다. 다시 시도해 주세요."))),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> purge(Set<String> ids, {bool all = false}) async {
    if (busy || ids.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(all ? tr("휴지통 비우기") : tr("영구 삭제")),
        content: Text(
          tr(
            "{0}개 항목의 앱 내 파일·표지·독서 기록을 영구 삭제할까요?\n복원할 수 없습니다. 다른 책과 공유하는 파일과 앱 밖에 보관한 원본은 유지됩니다.",
            [ids.length],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr("취소")),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr("영구 삭제")),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() {
      busy = true;
      _deleting = true;
    });
    var message = tr("영구 삭제했습니다.");
    try {
      final service = await container.read(libraryTrashServiceProvider.future);
      await service.empty(ids);
    } catch (_) {
      message = tr("일부 항목의 삭제를 완료하지 못했습니다. 남은 항목에서 다시 시도해 주세요.");
    }
    container.invalidate(booksProvider);
    container.invalidate(bookGroupsProvider);
    container.invalidate(nativeLibraryPositionsProvider);
    container.invalidate(legacyReadingProgressProvider);
    container.invalidate(libraryCompletionProvider);
    if (mounted) {
      setState(() {
        busy = false;
        _deleting = false;
        entries = store.load();
        _size = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(libraryTrashProgressProvider);
    final working = busy || progress != null;
    ref.listen(libraryTrashProgressProvider, (previous, next) {
      if (previous != null && next == null && mounted) _reload();
    });
    return Scaffold(
      appBar: AppBar(
        title: Text(tr("휴지통")),
        actions: [
          FutureBuilder<Map<String, Map<String, dynamic>>>(
            future: entries,
            builder: (context, snapshot) => TextButton(
              onPressed: working || !snapshot.hasData || snapshot.data!.isEmpty
                  ? null
                  : () => purge(snapshot.data!.keys.toSet(), all: true),
              child: Text(tr("휴지통 비우기")),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_deleting || progress != null)
            _TrashProgressPanel(progress: progress),
          Expanded(
            child: FutureBuilder<Map<String, Map<String, dynamic>>>(
              future: entries,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: TextButton(
                      onPressed: _reload,
                      child: Text(tr("휴지통 다시 불러오기")),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snapshot.data!.entries.toList()
                  ..sort(
                    (a, b) => (b.value['deletedAt'] as String).compareTo(
                      a.value['deletedAt'] as String,
                    ),
                  );
                return ListView(
                  padding: AdOverlayInsets.padding(
                    context,
                    EdgeInsets.only(
                      bottom: MediaQuery.paddingOf(context).bottom,
                    ),
                  ),
                  children: [
                    Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        tr(
                          "복원하거나 영구 삭제할 수 있습니다. 휴지통을 비우면 앱에 보관한 파일 용량을 확보합니다. 기본 제공 책의 앱 내장 원본은 삭제되지 않습니다. 휴지통의 책은 서재 백업에서 제외됩니다.",
                        ),
                      ),
                    ),
                    if (items.isNotEmpty && !working)
                      FutureBuilder<int>(
                        future: _size ??= ref
                            .read(libraryTrashServiceProvider.future)
                            .then(
                              (service) =>
                                  service.bytes(snapshot.data!.keys.toSet()),
                            ),
                        builder: (context, size) => Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                          child: Text(
                            size.hasData
                                ? tr("삭제로 확보 가능한 파일 용량: {0} MB", [
                                    (size.data! / 1024 / 1024).toStringAsFixed(
                                      1,
                                    ),
                                  ])
                                : size.hasError
                                ? tr("파일 용량을 확인하지 못했습니다.")
                                : tr("파일 용량 확인 중…"),
                          ),
                        ),
                      ),
                    if (items.isEmpty)
                      Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(tr("휴지통이 비어 있습니다.")),
                      ),
                    for (final item in items)
                      ListTile(
                        leading: Icon(
                          item.value['kind'] != 'book'
                              ? Icons.library_books_outlined
                              : Icons.menu_book_outlined,
                        ),
                        title: Text(item.value['title'] as String),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.value['deleting'] == true
                                  ? tr("삭제 미완료 · 다시 시도해 주세요.")
                                  : item.value['kind'] == 'bundle'
                                  ? tr("{0}권 · {1}", [
                                      (item.value['books'] as List).length,
                                      item.value['keepShelf'] == true
                                          ? tr('책장 비우기')
                                          : tr('묶음책 삭제'),
                                    ])
                                  : item.value['kind'] == 'group'
                                  ? tr("해제한 묶음")
                                  : tr("서재에서 삭제한 책"),
                            ),
                            Wrap(
                              spacing: 8,
                              children: [
                                TextButton(
                                  onPressed:
                                      working || item.value['deleting'] == true
                                      ? null
                                      : () => restore(item.key, item.value),
                                  child: Text(tr("복원")),
                                ),
                                TextButton(
                                  onPressed: working
                                      ? null
                                      : () => purge({item.key}),
                                  child: Text(
                                    item.value['deleting'] == true
                                        ? tr("삭제 재시도")
                                        : tr("영구 삭제"),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TrashProgressPanel extends StatelessWidget {
  const _TrashProgressPanel({this.progress});
  final TrashDeleteProgress? progress;

  @override
  Widget build(BuildContext context) {
    final value = progress;
    final String detail;
    final double? fraction;
    if (value == null || value.stage == TrashDeleteStage.preparing) {
      detail = tr("삭제할 파일을 확인하는 중…");
      fraction = null;
    } else if (value.stage == TrashDeleteStage.files) {
      detail = tr("파일 정리 {0}/{1}", [value.completedFiles, value.totalFiles]);
      fraction = value.totalFiles == 0
          ? null
          : value.completedFiles / value.totalFiles;
    } else {
      detail = tr("독서 기록과 서재를 정리하는 중…");
      fraction = null;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tr("영구 삭제 중…"), style: Theme.of(context).textTheme.titleSmall),
          if (value != null) ...[
            const SizedBox(height: 4),
            Text(
              tr("{0}/{1}개 항목 완료", [
                value.completedEntries,
                value.totalEntries,
              ]),
            ),
            if (value.title.isNotEmpty)
              Text(
                value.currentEntries > 1
                    ? tr("{0} 외 {1}개 항목", [
                        value.title,
                        value.currentEntries - 1,
                      ])
                    : value.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
          const SizedBox(height: 8),
          LinearProgressIndicator(value: fraction),
          const SizedBox(height: 8),
          Text(detail),
          const SizedBox(height: 4),
          Text(tr("삭제가 끝날 때까지 앱을 종료하지 마세요. 중단된 항목은 다시 삭제할 수 있습니다.")),
        ],
      ),
    );
  }
}
