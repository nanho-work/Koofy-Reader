import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/app/router.dart';
import 'package:koofy_reader/core/constants/app_constants.dart';
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

    return Scaffold(
      backgroundColor: const Color(0xFFF4EFE6),
      appBar: AppBar(
        title: const Text('쿠피 리더'),
        backgroundColor: const Color(0xFFF4EFE6),
        surfaceTintColor: Colors.transparent,
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
          final sortedBooks = [...books]
            ..sort((a, b) {
              final titleCompare = a.title.compareTo(b.title);
              if (titleCompare != 0) {
                return titleCompare;
              }
              return a.author.compareTo(b.author);
            });

          return LayoutBuilder(
            builder: (context, constraints) {
              final gridCount = _resolveGridCount(constraints.maxWidth);
              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(booksProvider);
                  ref.invalidate(allReadingProgressProvider);
                  ref.invalidate(recentBookIdsProvider);
                },
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      sliver: SliverToBoxAdapter(
                        child: _LibraryHeader(bookCount: sortedBooks.length),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      sliver: SliverGrid.builder(
                        itemCount: sortedBooks.length + 1,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: gridCount,
                          mainAxisSpacing:
                              AppConstants.libraryGridMainAxisSpacing,
                          crossAxisSpacing:
                              AppConstants.libraryGridCrossAxisSpacing,
                          childAspectRatio:
                              AppConstants.libraryGridChildAspectRatio,
                        ),
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return AddBookTile(
                              onTap: () => _importTextFile(context, ref),
                            );
                          }

                          final book = sortedBooks[index - 1];
                          return BookTile(
                            book: book,
                            onTap: () => _openReader(context, ref, book),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      bottomNavigationBar: const SafeArea(child: AdFooterWidget()),
    );
  }

  int _resolveGridCount(double width) {
    final breakpoints = AppConstants.libraryGridWidthBreakpoints;
    final counts = AppConstants.libraryGridCounts;
    final length = breakpoints.length < counts.length
        ? breakpoints.length
        : counts.length;
    for (var i = 0; i < length; i++) {
      if (width >= breakpoints[i]) {
        return counts[i];
      }
    }
    return AppConstants.libraryGridDefaultCount;
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE8D7BE), Color(0xFFD9BE98)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x33A06E3B)),
      ),
      child: Text(
        '표지 책장 · $bookCount권\n책 표지를 눌러 바로 이어읽기',
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: const Color(0xFF3B2B1F),
          height: 1.3,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
