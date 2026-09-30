import 'package:koofy_reader/features/library/application/book_import.dart';
import 'package:flutter/material.dart';
import 'package:koofy_reader/features/library/application/legacy_text_import.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/native_reader/data/reading_publication_preparer.dart';

Future<Book?> importWithTextPreview(
  BuildContext context,
  BookRepository repository,
  String path,
) async {
  try {
    return await repository.importBookFile(path);
  } on ReadingPublicationPreparationException catch (error) {
    if (error.code != 'unsupported_encoding' ||
        !path.toLowerCase().endsWith('.txt') ||
        repository is! LocalBookRepository) {
      rethrow;
    }
    final text = await LegacyTextImport.preview(path);
    if (!context.mounted) return null;
    final accept = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('한글 텍스트 확인'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(path.split(RegExp(r'[/\\]')).last),
                const SizedBox(height: 12),
                const Text(
                  'CP949/EUC-KR 방식으로 읽었습니다. 아래 한글이 정상인지 확인해 주세요. 가져오면 앱 안의 사본만 UTF-8로 저장하며 원본 파일은 바꾸지 않습니다.',
                ),
                const Divider(),
                Text(String.fromCharCodes(text.runes.take(1400))),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('이 파일 건너뛰기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('확인 후 가져오기'),
          ),
        ],
      ),
    );
    if (accept != true || !context.mounted) throw BookImportSkipped();
    return repository.importNormalizedText(path, text);
  }
}
