import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/features/catalog/data/reader_catalog.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';

class ReaderCatalogPage extends ConsumerStatefulWidget {
  const ReaderCatalogPage({super.key});
  @override
  ConsumerState<ReaderCatalogPage> createState() => _ReaderCatalogPageState();
}

class _ReaderCatalogPageState extends ConsumerState<ReaderCatalogPage> {
  String _kind = 'book';
  List<CatalogItem> _items = [];
  final Set<String> _installed = {};
  String? _cursor, _error, _downloading;
  bool _loading = true;
  double _progress = 0;
  int _request = 0;
  String _key(CatalogItem item) => '${item.id}_${item.version}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = ref.read(readerCatalogProvider);
      final page = await repository.list(_kind, after: more ? _cursor : null);
      final installed = <String>{};
      for (final item in page.items) {
        if (await repository.isInstalled(item)) installed.add(_key(item));
      }
      if (!mounted || request != _request) return;
      setState(() {
        _items = more ? [..._items, ...page.items] : page.items;
        _cursor = page.nextCursor;
        if (!more) _installed.clear();
        _installed.addAll(installed);
      });
    } catch (error) {
      if (mounted && request == _request) {
        setState(() => _error = _message(error));
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  String _message(Object error) =>
      error is CatalogException ? error.message : '목록을 처리하지 못했습니다. 다시 시도해 주세요.';

  Future<void> _download(CatalogItem item) async {
    setState(() {
      _downloading = item.id;
      _progress = 0;
    });
    try {
      await ref
          .read(readerCatalogProvider)
          .install(
            item,
            progress: (value) {
              if (mounted) setState(() => _progress = value.clamp(0, 1));
            },
          );
      ref.invalidate(booksProvider);
      if (!mounted) return;
      setState(() => _installed.add(_key(item)));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            item.kind == 'book'
                ? '내 서재에 책을 추가했습니다.'
                : '글꼴을 내려받았습니다. 책의 보기 설정에서 선택해 주세요.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_message(error))));
      }
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _downloading == null,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('다운로드가 끝날 때까지 잠시 기다려 주세요.')),
        );
      }
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('책 · 글꼴 다운로드')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'book',
                    label: Text('책'),
                    icon: Icon(Icons.menu_book),
                  ),
                  ButtonSegment(
                    value: 'font',
                    label: Text('글꼴'),
                    icon: Icon(Icons.text_fields),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: _downloading != null
                    ? null
                    : (values) {
                        setState(() {
                          _kind = values.first;
                          _items = [];
                          _cursor = null;
                        });
                        _load();
                      },
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  if (_downloading == null) await _load();
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    Text(
                      _kind == 'book'
                          ? '공개된 책을 내 서재에 담아 오프라인에서도 읽어 보세요.'
                          : '내려받은 글꼴은 책의 보기 설정 맨 아래에서 선택할 수 있어요.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Column(
                          children: [
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: _loading ? null : () => _load(),
                              child: const Text('다시 시도'),
                            ),
                          ],
                        ),
                      ),
                    if (!_loading && _error == null && _items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          '아직 공개된 항목이 없습니다.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    for (final item in _items)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${item.author} · ${(item.totalSize / 1024 / 1024).toStringAsFixed(1)} MB',
                              ),
                              if (item.description.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(item.description),
                                ),
                              ExpansionTile(
                                tilePadding: EdgeInsets.zero,
                                title: const Text(
                                  '이용 조건',
                                  style: TextStyle(fontSize: 13),
                                ),
                                children: [
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(item.license),
                                  ),
                                ],
                              ),
                              if (_downloading == item.id) ...[
                                LinearProgressIndicator(value: _progress),
                                const SizedBox(height: 8),
                                Text('다운로드 중 ${(_progress * 100).round()}%'),
                              ] else
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: FilledButton.tonalIcon(
                                    onPressed:
                                        _downloading != null ||
                                            _installed.contains(_key(item))
                                        ? null
                                        : () => _download(item),
                                    icon: Icon(
                                      _installed.contains(_key(item))
                                          ? Icons.check
                                          : Icons.download_outlined,
                                    ),
                                    label: Text(
                                      _installed.contains(_key(item))
                                          ? '다운로드 완료'
                                          : '다운로드',
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (!_loading && _cursor != null)
                      TextButton(
                        onPressed: _downloading != null
                            ? null
                            : () => _load(more: true),
                        child: const Text('더 보기'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
