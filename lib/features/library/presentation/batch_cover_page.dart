import 'package:koofy_reader/features/ads/presentation/ad_overlay_insets.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/features/library/application/book_import.dart';
import 'package:koofy_reader/features/library/application/cover_matching.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';

/// The same review and apply flow is used by mixed import, shelf and group pages.
Future<void> showBatchCovers(
  BuildContext context,
  WidgetRef ref, {
  Set<String>? bookIds,
  List<BookImportFile>? images,
}) async {
  if (kIsWeb) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('표지 이미지는 Android · iOS 앱에서 등록해 주세요.')),
    );
    return;
  }
  try {
    if (images == null) {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: coverImageExtensions,
        allowMultiple: true,
        dialogTitle: '책 파일과 이름이 같은 표지 이미지 선택',
      );
      if (picked == null) return;
      images = picked.files.map((f) => BookImportFile(f.name, f.path)).toList();
    }
    if (images.isEmpty || !context.mounted) return;
    final repository = ref.read(bookRepositoryProvider);
    final books = await repository.getBooks();
    final plan = CoverMatchPlan(
      books.where((b) => bookIds == null || bookIds.contains(b.id)).toList(),
      images,
    );
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BatchCoverPage(
          plan: plan,
          repository: repository,
          onChanged: () => ref.invalidate(booksProvider),
        ),
      ),
    );
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('표지 파일을 불러오지 못했습니다. 다시 시도해 주세요.')),
      );
    }
  }
}

class BatchCoverPage extends StatefulWidget {
  const BatchCoverPage({
    super.key,
    required this.plan,
    required this.repository,
    required this.onChanged,
  });
  final CoverMatchPlan plan;
  final BookRepository repository;
  final VoidCallback onChanged;
  @override
  State<BatchCoverPage> createState() => _BatchCoverPageState();
}

class _BatchCoverPageState extends State<BatchCoverPage> {
  final _selected = <String, BookImportFile>{};
  bool _replace = false;
  bool _saving = false;
  String _progress = '';
  @override
  void initState() {
    super.initState();
    for (final match in widget.plan.matches) {
      if (!widget.plan.needsChoice(match)) {
        _selected[match.book.id] = match.images.single;
      }
    }
  }

  Map<String, BookImportFile> get _applicable => {
    for (final match in widget.plan.matches)
      if (_selected.containsKey(match.book.id) &&
          (_replace || match.book.coverPath == null))
        match.book.id: _selected[match.book.id]!,
  };

  Future<void> _apply() async {
    final selected = _applicable;
    if (_saving || selected.isEmpty) return;
    setState(() => _saving = true);
    final result = await applyCoverMatches(
      widget.repository,
      selected,
      replaceExisting: _replace,
      onProgress: (done, total) {
        if (mounted) setState(() => _progress = '$done/$total');
      },
    );
    widget.onChanged();
    if (!mounted) return;
    setState(() => _saving = false);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('표지 등록 결과'),
        content: SingleChildScrollView(
          child: Text(
            '${result.applied}권 적용 · ${result.skipped}권 유지\n'
            '${result.failures.isEmpty ? '' : '\n이미지를 읽거나 저장하지 못했습니다. 20MB 이하 JPG·PNG·WebP인지 확인해 주세요.\n${result.failures.join('\n')}'}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('표지 일괄 등록'),
        automaticallyImplyLeading: !_saving,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    '확장자를 제외한 원래 파일명이 같은 책에 연결합니다. 제목은 비교하지 않습니다.\n중복된 이름은 연결할 항목을 직접 선택해 주세요.',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${widget.plan.matches.length}권 일치 · 이미지 ${widget.plan.unmatchedImages.length}개 미일치',
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('기존 표지도 교체'),
                    subtitle: const Text('끄면 이미 표지가 있는 책은 유지합니다.'),
                    value: _replace,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _replace = v),
                  ),
                  if (widget.plan.matches.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        '이름이 일치하는 책이 없습니다.\n예: 소설_001.txt ↔ 소설_001.jpg\n원래 파일명 정보가 없는 이전 백업의 책은 개별 표지 등록을 이용해 주세요.',
                      ),
                    ),
                  for (final match in widget.plan.matches)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              match.book.title,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(match.book.matchingFileName ?? ''),
                            Text(match.book.author),
                            if (_selected[match.book.id]?.path != null)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Image.file(
                                  File(_selected[match.book.id]!.path!),
                                  height: 120,
                                  cacheWidth: 240,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) =>
                                      const Text('이미지 미리보기를 불러올 수 없습니다.'),
                                ),
                              ),
                            if (widget.plan.needsChoice(match))
                              const Text('중복 이름 · 연결할 이미지를 직접 선택해 주세요.'),
                            if (match.book.coverPath != null && !_replace)
                              const Text('기존 표지 유지'),
                            DropdownButton<int>(
                              isExpanded: true,
                              value: _selected[match.book.id] == null
                                  ? -1
                                  : match.images.indexOf(
                                      _selected[match.book.id]!,
                                    ),
                              items: [
                                const DropdownMenuItem(
                                  value: -1,
                                  child: Text('연결하지 않음'),
                                ),
                                for (var i = 0; i < match.images.length; i++)
                                  DropdownMenuItem(
                                    value: i,
                                    child: Text(
                                      '${i + 1}. ${match.images[i].name}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged:
                                  _saving ||
                                      (match.book.coverPath != null &&
                                          !_replace)
                                  ? null
                                  : (i) => setState(() {
                                      if (i == null || i < 0) {
                                        _selected.remove(match.book.id);
                                      } else {
                                        _selected[match.book.id] =
                                            match.images[i];
                                      }
                                    }),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (widget.plan.unmatchedImages.isNotEmpty)
                    ExpansionTile(
                      title: const Text('연결할 책이 없는 이미지'),
                      children: [
                        for (final image in widget.plan.unmatchedImages)
                          ListTile(title: Text(image.name)),
                      ],
                    ),
                ],
              ),
            ),
            Padding(
              padding: AdOverlayInsets.padding(
                context,
                const EdgeInsets.all(16),
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving || _applicable.isEmpty ? null : _apply,
                  child: Text(
                    _saving
                        ? '표지 저장 중 $_progress'
                        : '${_applicable.length}권에 표지 적용',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
