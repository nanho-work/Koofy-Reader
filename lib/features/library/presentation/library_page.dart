import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/app/router.dart';
import 'package:koofy_reader/core/constants/app_constants.dart';
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
                            onLongPress: () =>
                                _confirmRemoveBook(context, ref, book),
                            showDeleteButton: true,
                            onDeleteTap: () =>
                                _confirmRemoveBook(context, ref, book),
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

  Future<void> _confirmRemoveBook(
    BuildContext context,
    WidgetRef ref,
    Book book,
  ) async {
    final actionLabel = book.isLocalFile ? '삭제' : '숨김';
    final actionVerb = book.isLocalFile ? '삭제할까요?' : '숨길까요?';
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('책 제거'),
          content: Text('서재에서 "${book.title}" 을(를) $actionVerb'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(actionLabel),
            ),
          ],
        );
      },
    );
    if (shouldDelete != true) {
      return;
    }
    final removed = await ref
        .read(bookRepositoryProvider)
        .removeBookFromLibrary(book.id);
    if (!context.mounted) {
      return;
    }
    if (!removed) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('제거할 책을 찾지 못했습니다.')));
      return;
    }
    ref.invalidate(booksProvider);
    ref.invalidate(allReadingProgressProvider);
    ref.invalidate(recentBookIdsProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          book.isLocalFile ? '삭제 완료: ${book.title}' : '숨김 완료: ${book.title}',
        ),
      ),
    );
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
