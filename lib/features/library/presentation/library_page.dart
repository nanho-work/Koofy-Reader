import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:koofy_reader/app/router.dart';
import 'package:koofy_reader/features/ads/presentation/ad_footer_widget.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/library/presentation/widgets/book_tile.dart';
import 'package:koofy_reader/features/reader/data/reader_repository.dart';

class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(booksProvider);
    final progressAsync = ref.watch(allReadingProgressProvider);
    final recentIdsAsync = ref.watch(recentBookIdsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('쿠피 리더'),
        actions: [
          IconButton(
            onPressed: () => _importTextFile(context, ref),
            icon: const Icon(Icons.upload_file),
            tooltip: '책 파일 가져오기',
          ),
          IconButton(
            onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
            icon: const Icon(Icons.settings),
            tooltip: '설정',
          ),
        ],
      ),
      body: booksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text('서재를 불러오지 못했습니다.\n$error', textAlign: TextAlign.center),
        ),
        data: (books) {
          final progressMap = progressAsync.valueOrNull ?? const {};
          final recentIds = recentIdsAsync.valueOrNull ?? const <String>[];
          final recentIndexById = <String, int>{
            for (int i = 0; i < recentIds.length; i++) recentIds[i]: i,
          };

          final sortedBooks = [...books]
            ..sort((a, b) {
              final aIndex = recentIndexById[a.id] ?? 999999;
              final bIndex = recentIndexById[b.id] ?? 999999;
              if (aIndex != bIndex) {
                return aIndex.compareTo(bIndex);
              }
              return a.title.compareTo(b.title);
            });

          if (books.isEmpty) {
            return const Center(child: Text('표시할 책이 없습니다.'));
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(booksProvider);
              ref.invalidate(allReadingProgressProvider);
              ref.invalidate(recentBookIdsProvider);
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              itemCount: sortedBooks.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _LibraryHeader(bookCount: sortedBooks.length);
                }
                final book = sortedBooks[index - 1];
                final progress = progressMap[book.id];
                final lastReadText = progress == null
                    ? null
                    : DateFormat(
                        'yyyy-MM-dd HH:mm',
                      ).format(progress.updatedAt.toLocal());

                final totalPages = progress?.totalPages ?? 0;
                final currentPage = totalPages == 0
                    ? 0
                    : (progress!.pageIndex + 1).clamp(1, totalPages);
                final percent = ((progress?.positionRatio ?? 0) * 100).round();
                final progressText = totalPages == 0
                    ? '$percent% 읽음'
                    : '$currentPage/$totalPages 페이지 · $percent%';

                return BookTile(
                  book: book,
                  progressRatio: progress?.positionRatio.clamp(0.0, 1.0) ?? 0.0,
                  progressText: progressText,
                  lastReadText: lastReadText,
                  onTap: () => _openReader(context, ref, book),
                );
              },
            ),
          );
        },
      ),
      bottomNavigationBar: const SafeArea(child: AdFooterWidget()),
    );
  }

  void _openReader(BuildContext context, WidgetRef ref, Book book) {
    Navigator.pushNamed(context, AppRoutes.reader, arguments: book).then((_) {
      ref.invalidate(allReadingProgressProvider);
      ref.invalidate(recentBookIdsProvider);
    });
  }

  Future<void> _importTextFile(BuildContext context, WidgetRef ref) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('웹(크롬)에서는 파일 가져오기가 제한됩니다. 안드로이드 기기에서 테스트해 주세요.'),
        ),
      );
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['txt', 'epub'],
      );
      if (result == null) {
        return;
      }
      final path = result.files.single.path;
      if (path == null || path.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('파일 경로를 읽을 수 없습니다.')));
        return;
      }

      final imported = await ref
          .read(bookRepositoryProvider)
          .importBookFile(path);
      if (!context.mounted) return;
      if (imported == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('txt 또는 epub 파일만 가져올 수 있습니다.')),
        );
        return;
      }

      ref.invalidate(booksProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('가져오기 완료: ${imported.title}')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('파일 가져오기 실패: $error')));
    }
  }
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({required this.bookCount});

  final int bookCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '내 서재: $bookCount권\n오프라인에서도 책을 바로 읽을 수 있습니다.',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }
}
