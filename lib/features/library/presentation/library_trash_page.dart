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
  Future<void> restore(String id, Map<String, dynamic> entry) async {
    setState(() => busy = true);
    try {
      if (entry['deleting'] == true) throw StateError('삭제 중인 항목입니다.');
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
        setState(() => entries = store.load());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('복원했습니다. 다른 묶음에 배치한 책의 현재 소속은 유지합니다.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('복원하지 못했습니다. 기록은 보존했습니다. 다시 시도해 주세요.')),
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
        title: Text(all ? '휴지통 비우기' : '영구 삭제'),
        content: Text(
          '${ids.length}개 항목의 앱 내 파일·표지·독서 기록을 영구 삭제할까요?\n복원할 수 없습니다. 다른 책과 공유하는 파일과 앱 밖에 보관한 원본은 유지됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('영구 삭제'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => busy = true);
    var message = '영구 삭제했습니다.';
    try {
      final service = await ref.read(libraryTrashServiceProvider.future);
      await service.empty(ids);
    } catch (_) {
      message = '일부 항목의 삭제를 완료하지 못했습니다. 남은 항목에서 다시 시도해 주세요.';
    }
    ref.invalidate(booksProvider);
    ref.invalidate(bookGroupsProvider);
    ref.invalidate(nativeLibraryPositionsProvider);
    ref.invalidate(legacyReadingProgressProvider);
    ref.invalidate(libraryCompletionProvider);
    if (mounted) {
      setState(() {
        busy = false;
        entries = store.load();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('휴지통'),
      actions: [
        FutureBuilder<Map<String, Map<String, dynamic>>>(
          future: entries,
          builder: (context, snapshot) => TextButton(
            onPressed: busy || !snapshot.hasData || snapshot.data!.isEmpty
                ? null
                : () => purge(snapshot.data!.keys.toSet(), all: true),
            child: const Text('휴지통 비우기'),
          ),
        ),
      ],
    ),
    body: FutureBuilder<Map<String, Map<String, dynamic>>>(
      future: entries,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(() => entries = store.load()),
              child: const Text('휴지통 다시 불러오기'),
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
            EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
          ),
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                '복원하거나 영구 삭제할 수 있습니다. 휴지통을 비우면 앱에 보관한 파일 용량을 확보합니다. 기본 제공 책의 앱 내장 원본은 삭제되지 않습니다. 휴지통의 책은 서재 백업에서 제외됩니다.',
              ),
            ),
            if (items.isNotEmpty)
              FutureBuilder<int>(
                future: ref
                    .read(libraryTrashServiceProvider.future)
                    .then(
                      (service) => service.bytes(snapshot.data!.keys.toSet()),
                    ),
                builder: (context, size) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Text(
                    size.hasData
                        ? '삭제로 확보 가능한 파일 용량: ${(size.data! / 1024 / 1024).toStringAsFixed(1)} MB'
                        : size.hasError
                        ? '파일 용량을 확인하지 못했습니다.'
                        : '파일 용량 확인 중…',
                  ),
                ),
              ),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('휴지통이 비어 있습니다.'),
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
                          ? '삭제 미완료 · 다시 시도해 주세요.'
                          : item.value['kind'] == 'bundle'
                          ? '${(item.value['books'] as List).length}권 · ${item.value['keepShelf'] == true ? '책장 비우기' : '묶음책 삭제'}'
                          : item.value['kind'] == 'group'
                          ? '해제한 묶음'
                          : '서재에서 삭제한 책',
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: busy || item.value['deleting'] == true
                              ? null
                              : () => restore(item.key, item.value),
                          child: const Text('복원'),
                        ),
                        TextButton(
                          onPressed: busy ? null : () => purge({item.key}),
                          child: Text(
                            item.value['deleting'] == true ? '삭제 재시도' : '영구 삭제',
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
  );
}
