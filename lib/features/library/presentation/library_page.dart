import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('쿠피 리더'),
        actions: [
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
          if (books.isEmpty) {
            return const Center(child: Text('표시할 책이 없습니다.'));
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(booksProvider);
              ref.invalidate(allReadingProgressProvider);
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              itemCount: books.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _LibraryHeader(bookCount: books.length);
                }
                final book = books[index - 1];
                return BookTile(
                  book: book,
                  progressRatio:
                      progressMap[book.id]?.positionRatio.clamp(0.0, 1.0) ??
                      0.0,
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
    });
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
