import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/backup/data/library_backup.dart';
import 'package:koofy_reader/features/library/data/book_cover_store.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/data/book_group_repository.dart';
import 'package:koofy_reader/features/library/data/library_reading_repository.dart';
import 'package:koofy_reader/features/native_reader/application/native_reader_services.dart';

class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});
  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool _busy = false;
  String? _status;
  void _progress(String message) {
    if (mounted) setState(() => _status = message);
  }

  Future<void> _run(bool restore) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '준비 중…';
    });
    try {
      final native = await ref.read(nativeReaderServicesProvider.future);
      if (native.coordinator.activeSessionId != null) {
        throw StateError('읽고 있는 책을 닫은 뒤 이용해 주세요.');
      }
      await native.coordinator.recoverCheckpoints();
      final storage = ref.read(localStorageProvider);
      final service = LibraryBackupService(
        storage: storage,
        books: ref.read(bookRepositoryProvider),
        groups: ref.read(bookGroupRepositoryProvider),
        covers: BookCoverStore(storage),
        reader: native.coordinator.store,
        preparer: native.preparer,
        directory: Directory(
          '${native.supportDirectory!.path}/library_backups',
        ),
      );
      if (restore) {
        final selection = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['zip'],
          dialogTitle: '쿠피리더 백업 선택',
        );
        if (selection == null || !mounted) return;
        final path = selection.files.single.path;
        if (path == null) {
          throw const FormatException('백업 파일을 기기에 내려받은 뒤 선택해 주세요.');
        }
        _progress('백업 파일 확인 중…');
        final backup = await LibraryBackupService.read(File(path));
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('백업 복원'),
            content: Text(
              '${backup.bookCount}권이 포함된 백업입니다.\n\n현재 서재에 없는 책·묶음·독서 기록을 추가합니다. '
              '같은 책의 현재 기록과 설정은 유지합니다. 처음 사용하는 기기에는 백업의 보기 설정을 적용합니다.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('복원'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        _progress('책과 독서 기록 복원 중…');
        final count = await service.restore(backup);
        ref.invalidate(booksProvider);
        ref.invalidate(bookGroupsProvider);
        ref.invalidate(nativeLibraryPositionsProvider);
        ref.invalidate(libraryCompletionProvider);
        _progress('복원 완료 · $count권 추가\n기존 책과 독서 기록은 유지했습니다.');
      } else {
        final bytes = await service.export(progress: _progress);
        if (!mounted) return;
        _progress('저장할 위치를 선택해 주세요.');
        final date = DateTime.now().toIso8601String().replaceAll(':', '-');
        final path = await FilePicker.platform.saveFile(
          dialogTitle: '서재 백업 저장',
          fileName: 'KoofyReader-$date.koofy.zip',
          type: FileType.custom,
          allowedExtensions: ['zip'],
          bytes: bytes,
        );
        _progress(path == null ? '백업 저장을 취소했습니다.' : '백업 파일을 저장했습니다.');
      }
    } catch (error) {
      _progress(
        error is FormatException
            ? error.message
            : '작업을 완료하지 못했습니다. 파일과 저장 공간을 확인해 주세요.\n$error',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('서재 백업·복원')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('책 파일, 표지, 묶음과 순서, 읽던 위치, 완독 표시, 보기 설정을 파일 하나로 저장합니다.'),
          const SizedBox(height: 12),
          const Text(
            '파일 앱에서 다른 기기로 옮겨 복원할 수 있습니다. 자동 동기화는 하지 않습니다. '
            '다운로드한 글꼴은 새 기기에서 다시 내려받아 주세요. 광고 숨김 시간과 광고 동의는 백업하지 않습니다.',
          ),
          const SizedBox(height: 12),
          const Text(
            '한 번에 원본 기준 100MB까지 지원합니다. 백업에는 책 본문이 포함되므로 본인이 관리하는 위치에 보관해 주세요.',
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : () => _run(false),
            icon: const Icon(Icons.save_alt),
            label: const Text('백업 파일 저장'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _run(true),
            icon: const Icon(Icons.restore),
            label: const Text('백업 파일 불러오기'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: LinearProgressIndicator(),
            ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_status!, semanticsLabel: _status),
            ),
        ],
      ),
    ),
  );
}
