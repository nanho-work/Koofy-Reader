import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/app/router.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/data/library_reading_repository.dart';
import '../data/reader_catalog.dart';

Future<void> openCatalogBook(
  BuildContext context,
  WidgetRef ref,
  CatalogItem item,
) async {
  try {
    if (!ref.read(nativeReaderAvailableProvider)) {
      throw const CatalogException('독서 화면은 Android와 iOS 앱에서 사용할 수 있습니다.');
    }
    final repository = ref.read(readerCatalogProvider);
    if (!await repository.isInstalled(item)) {
      if (!context.mounted) return;
      await ref.read(catalogDownloadProvider.notifier).download(item);
    }
    if (!context.mounted) return;
    final books = await ref.read(booksProvider.future);
    if (!context.mounted) return;
    final book = books.where((book) => book.id == item.bookId).firstOrNull;
    if (book == null) throw const CatalogException('다운로드하지 못했습니다. 다시 시도해 주세요.');
    await Navigator.pushNamed(context, AppRoutes.nativeReader, arguments: book);
    if (context.mounted) ref.invalidate(nativeLibraryPositionsProvider);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is CatalogException
                ? tr(error.message)
                : tr('다운로드하지 못했습니다. 다시 시도해 주세요.'),
          ),
        ),
      );
    }
  }
}
