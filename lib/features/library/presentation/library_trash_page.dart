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
      if (entry['kind'] == 'group') {
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('휴지통')),
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
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                '책의 파일·표지·독서 기록을 보관합니다. 묶음 해제 기록도 복원할 수 있습니다. 자동 삭제하지 않으며, 휴지통의 책은 서재 백업에서 제외됩니다. 앱 삭제 시에는 함께 지워집니다.',
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
                  item.value['kind'] == 'group'
                      ? Icons.library_books_outlined
                      : Icons.menu_book_outlined,
                ),
                title: Text(item.value['title'] as String),
                subtitle: Text(
                  item.value['kind'] == 'group' ? '해제한 묶음' : '서재에서 삭제한 책',
                ),
                trailing: TextButton(
                  onPressed: busy ? null : () => restore(item.key, item.value),
                  child: const Text('복원'),
                ),
              ),
          ],
        );
      },
    ),
  );
}
