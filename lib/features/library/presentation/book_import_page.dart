import 'package:koofy_reader/core/widgets/reader_alert.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/features/library/application/book_import_controller.dart';
import 'package:koofy_reader/features/library/data/book_group_repository.dart';
import 'text_import_preview.dart';

class BookImportPage extends ConsumerStatefulWidget {
  const BookImportPage({super.key});
  @override
  ConsumerState<BookImportPage> createState() => _BookImportPageState();
}

class _BookImportPageState extends ConsumerState<BookImportPage> {
  late final TextEditingController _title;
  @override
  void initState() {
    super.initState();
    final job = ref.read(bookImportControllerProvider);
    _title = TextEditingController(text: job.groupTitle);
    Future.microtask(() async {
      await job.ready;
      if (!mounted) return;
      _title.text = job.groupTitle;
      if (job.files.isEmpty) await job.pick();
    });
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _newFiles() async {
    final job = ref.read(bookImportControllerProvider);
    if (job.files.isNotEmpty) {
      final discard = await showReaderDialog<bool>(
        context: context,
        builder: (context) => ReaderAlertDialog(
          title: Text(tr('새 파일 선택')),
          content: Text(tr('현재 가져오기 목록을 비울까요? 이미 서재에 등록된 책은 유지됩니다.')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('취소')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('목록 비우기')),
            ),
          ],
        ),
      );
      if (discard != true) return;
      await job.reset();
      _title.clear();
    }
    await job.pick();
  }

  @override
  Widget build(BuildContext context) {
    final job = ref.watch(bookImportControllerProvider);
    final groups = ref.watch(bookGroupsProvider).valueOrNull ?? [];
    final reviewing = job.stage == ImportStage.review;
    final title = switch (job.stage) {
      ImportStage.selecting => tr('파일 정보를 확인하는 중…'),
      ImportStage.receiving => tr('선택한 파일을 기기로 가져오는 중…'),
      ImportStage.registering => tr('책을 서재에 등록하는 중…'),
      ImportStage.covers => tr('표지 이미지를 연결하는 중…'),
      ImportStage.grouping => tr('묶음책을 정리하는 중…'),
      ImportStage.finished => tr('가져오기 결과'),
      _ => tr('책 가져오기'),
    };
    return Scaffold(
      appBar: AppBar(title: Text(tr('책 가져오기'))),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (job.interrupted)
                    Text(
                      tr('이전 가져오기 기록이 있습니다. 완료한 책은 유지하고 남은 작업을 이어서 할 수 있습니다.'),
                    ),
                  if (job.files.isNotEmpty)
                    Text(
                      tr('책 {0}권 · 표지 이미지 {1}개', [
                        job.books.length,
                        job.files.where((f) => f.image).length,
                      ]),
                    ),
                  if (job.busy) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(
                      value:
                          job.stage == ImportStage.registering &&
                              job.books.isNotEmpty
                          ? job.completed / job.books.length
                          : null,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr('서재 등록 {0}/{1}권 완료', [
                        job.completed,
                        job.books.length,
                      ]),
                    ),
                    if (job.current.isNotEmpty)
                      Text(
                        job.current,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (job.bytes > 0)
                      Text(
                        tr('{0} MB 가져옴', [
                          (job.bytes / 1024 / 1024).toStringAsFixed(1),
                        ]),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      tr(
                        '다른 화면으로 이동해도 계속 처리합니다. 앱을 종료하면 다음에 남은 작업을 다시 시도할 수 있습니다.',
                      ),
                    ),
                  ],
                  if (job.message.isNotEmpty) Text(tr(job.message)),
                  if (job.stage == ImportStage.finished) ...[
                    Text(
                      tr('서재 등록 {0}/{1}권 완료', [
                        job.completed,
                        job.books.length,
                      ]),
                    ),
                    Text(tr('실패한 파일 {0}개', [job.failures])),
                    if (job.applyCovers &&
                        job.files.any((f) => f.image && !f.done))
                      Text(tr('연결되지 않은 표지가 있습니다. 파일명 중복과 기존 표지를 확인해 주세요.')),
                  ],
                ],
              ),
            ),
            Expanded(
              child: reviewing
                  ? ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(tr('같은 파일명의 표지 자동 연결')),
                          subtitle: Text(
                            tr('기존 표지는 유지합니다. 이름이 중복된 표지는 자동으로 연결하지 않습니다.'),
                          ),
                          value: job.applyCovers,
                          onChanged: (value) {
                            job.applyCovers = value;
                            job.optionsChanged();
                          },
                        ),
                        if (job.books.length >= 2) ...[
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue:
                                job.group.isEmpty ||
                                    job.group == 'new' ||
                                    groups.any((g) => g.id == job.group)
                                ? job.group
                                : '',
                            decoration: InputDecoration(labelText: tr('등록 방식')),
                            items: [
                              DropdownMenuItem(
                                value: '',
                                child: Text(tr('각각 보관')),
                              ),
                              DropdownMenuItem(
                                value: 'new',
                                child: Text(tr('새 묶음 만들기')),
                              ),
                              for (final group in groups)
                                DropdownMenuItem(
                                  value: group.id,
                                  child: Text(
                                    group.title,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (value) {
                              job.group = value ?? '';
                              job.optionsChanged();
                            },
                          ),
                          if (job.group == 'new')
                            TextField(
                              controller: _title,
                              maxLength: 100,
                              decoration: InputDecoration(
                                labelText: tr('묶음 이름'),
                              ),
                              onChanged: (value) {
                                job.groupTitle = value;
                                job.optionsChanged();
                              },
                            ),
                        ],
                        const SizedBox(height: 16),
                        Text(tr('파일명으로 표지를 연결합니다. 원본 파일은 변경하지 않습니다.')),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: job.files.length,
                      itemBuilder: (_, i) {
                        final file = job.files[i];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            file.error
                                ? Icons.error_outline
                                : file.done
                                ? Icons.check_circle_outline
                                : file.image
                                ? Icons.image_outlined
                                : Icons.menu_book_outlined,
                          ),
                          title: Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: file.error
                              ? Text(tr('파일 접근 권한과 인터넷 연결을 확인하고 다시 시도해 주세요.'))
                              : null,
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  if (job.busy && job.stage != ImportStage.selecting)
                    OutlinedButton(
                      onPressed: job.stopRequested
                          ? null
                          : () => unawaited(job.stop()),
                      child: Text(
                        tr(job.stopRequested ? '중단하는 중…' : '가져오기 중단'),
                      ),
                    ),
                  if (!job.busy) ...[
                    OutlinedButton(
                      onPressed: _newFiles,
                      child: Text(tr('새 파일 선택')),
                    ),
                    if (job.files.isNotEmpty)
                      FilledButton(
                        onPressed:
                            job.group == 'new' && job.groupTitle.trim().isEmpty
                            ? null
                            : () => unawaited(
                                job.run(
                                  importFile: (path) => importWithTextPreview(
                                    context,
                                    job.repository,
                                    path,
                                  ),
                                ),
                              ),
                        child: Text(
                          tr(
                            job.stage == ImportStage.finished
                                ? '남은 작업 다시 시도'
                                : '가져오기 시작',
                          ),
                        ),
                      ),
                  ],
                  if (job.stage == ImportStage.finished)
                    TextButton(
                      onPressed: () async {
                        await job.reset();
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: Text(tr('완료')),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
