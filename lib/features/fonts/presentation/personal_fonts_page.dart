import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:koofy_reader/features/fonts/data/personal_fonts.dart';
import 'package:koofy_reader/features/native_reader/data/native_reader_store.dart';

class PersonalFontsPage extends StatefulWidget {
  const PersonalFontsPage({
    super.key,
    required this.store,
    required this.reader,
  });
  final PersonalFontStore store;
  final NativeReaderStore reader;
  @override
  State<PersonalFontsPage> createState() => _PersonalFontsPageState();
}

class _PersonalFontsPageState extends State<PersonalFontsPage> {
  List<Map<String, dynamic>> _fonts = [];
  final _loaded = <String>{};
  String? _selected;
  String? _error;
  bool _busy = true;
  @override
  void initState() {
    super.initState();
    _run(_reload);
  }

  Future<void> _run(Future<void> Function() task) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await task();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is FormatException
              ? e.message
              : e is FileSystemException
              ? '글꼴 파일을 읽거나 저장하지 못했습니다. 파일과 저장 공간을 확인해 주세요.'
              : '글꼴을 불러오지 못했습니다. 다른 TTF·OTF 파일로 다시 시도해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reload() async {
    _fonts = await widget.store.load();
    _selected = (await widget.reader.loadGlobalPreferences()).fontId;
    for (final font in _fonts) {
      final id = font['id'] as String;
      if (_loaded.contains(id)) continue;
      try {
        final loader = FontLoader(id)
          ..addFont(
            widget.store.fileFor(font).readAsBytes().then(ByteData.sublistView),
          );
        await loader.load();
        _loaded.add(id);
      } catch (_) {
        /* Invalid preview retains a readable system font. */
      }
    }
  }

  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ttf', 'otf'],
    );
    if (result == null) return;
    final picked = result.files.single;
    if (picked.size > PersonalFontStore.maxBytes || picked.path == null) {
      throw const FormatException('10MB 이하의 글꼴 파일을 선택해 주세요.');
    }
    final file = File(picked.path!);
    if (await file.length() > PersonalFontStore.maxBytes) {
      throw const FormatException('글꼴 파일이 너무 큽니다.');
    }
    final bytes = await file.readAsBytes();
    PersonalFontStore.validate(bytes);
    final family =
        'personal_${sha256.convert(bytes).toString().substring(0, 32)}';
    if (!_loaded.contains(family)) {
      final preview = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await preview.load();
      _loaded.add(family);
    }
    final id = await widget.store.install(bytes, picked.name);
    await widget.reader.setGlobalFont(id);
    await _reload();
  }

  Future<void> _remove(Map<String, dynamic> font) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('내 글꼴 삭제'),
        content: Text('“${font['label']}”을 삭제할까요? 사용 중인 글꼴이면 기본 글꼴로 돌아갑니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _run(() async {
      if (_selected == font['id']) await widget.reader.setGlobalFont('default');
      await widget.store.remove(font['id'] as String);
      await _reload();
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('내 글꼴'),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('독서로 돌아가기'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '기기에 있는 TTF·OTF 파일을 가져와 사용할 수 있습니다. 추가한 글꼴은 앱 안에 보관되며 모든 책에 적용됩니다.',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : () => _run(_import),
            icon: const Icon(Icons.add),
            label: const Text('내 글꼴 추가'),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_fonts.isEmpty && !_busy)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('아직 추가한 글꼴이 없습니다.'),
            ),
          for (final font in _fonts)
            Card(
              child: ListTile(
                title: Text(
                  font['label'] as String,
                  style: TextStyle(
                    fontFamily: _loaded.contains(font['id'])
                        ? font['id'] as String
                        : null,
                  ),
                ),
                leading: Icon(
                  font['id'] == _selected
                      ? Icons.check_circle
                      : Icons.text_fields,
                ),
                onTap: _busy
                    ? null
                    : () => _run(() async {
                        await widget.reader.setGlobalFont(font['id'] as String);
                        await _reload();
                      }),
                trailing: IconButton(
                  tooltip: '글꼴 삭제',
                  onPressed: _busy ? null : () => _remove(font),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
