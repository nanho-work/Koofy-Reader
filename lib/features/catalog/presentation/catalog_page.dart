import 'book_catalog_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/features/catalog/data/reader_catalog.dart';
import 'package:koofy_reader/features/catalog/presentation/font_catalog_row.dart';

const catalogBookCategories = ['시', '소설', '에세이', '기타'];

class ReaderCatalogPage extends StatelessWidget {
  const ReaderCatalogPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('도서·글꼴 다운로드')),
    body: const SafeArea(child: ReaderCatalogBrowser()),
  );
}

/// The same catalog is used in the wide library sidebar and the phone route.
/// Both tabs retain their own query, category and scroll position.
class ReaderCatalogBrowser extends ConsumerStatefulWidget {
  const ReaderCatalogBrowser({super.key});
  @override
  ConsumerState<ReaderCatalogBrowser> createState() =>
      _ReaderCatalogBrowserState();
}

class _ReaderCatalogBrowserState extends ConsumerState<ReaderCatalogBrowser> {
  int _tab = 0;
  bool _fontsVisited = false;
  @override
  Widget build(BuildContext context) {
    final busy = ref.watch(
      catalogDownloadProvider.select((value) => value.busy),
    );
    return PopScope(
      canPop: !busy,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('다운로드가 끝날 때까지 잠시 기다려 주세요.')),
          );
        }
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('도서')),
                      ButtonSegment(value: 1, label: Text('글꼴')),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (values) => setState(() {
                      _tab = values.first;
                      if (_tab == 1) _fontsVisited = true;
                    }),
                  ),
                ),
                IconButton(
                  tooltip: '다운로드 목록 새로고침',
                  onPressed: busy
                      ? null
                      : () {
                          final kind = _tab == 0 ? 'book' : 'font';
                          ref.invalidate(catalogItemsProvider(kind));
                          ref.invalidate(catalogInstalledProvider(kind));
                        },
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                const _CatalogList(kind: 'book'),
                if (_fontsVisited)
                  const _CatalogList(kind: 'font')
                else
                  const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CatalogList extends ConsumerStatefulWidget {
  const _CatalogList({required this.kind});
  final String kind;
  @override
  ConsumerState<_CatalogList> createState() => _CatalogListState();
}

class _CatalogListState extends ConsumerState<_CatalogList> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String? _category;
  bool get _books => widget.kind == 'book';
  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _message(Object error) =>
      error is CatalogException ? error.message : '목록을 처리하지 못했습니다. 다시 시도해 주세요.';

  void _changed() {
    setState(() {});
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _refresh() async {
    if (ref.read(catalogDownloadProvider).busy) return;
    ref.invalidate(catalogItemsProvider(widget.kind));
    ref.invalidate(catalogInstalledProvider(widget.kind));
    try {
      await ref.read(catalogItemsProvider(widget.kind).future);
    } catch (_) {
      /* Render retry below. */
    }
  }

  Future<void> _download(CatalogItem item) async {
    try {
      await ref.read(catalogDownloadProvider.notifier).download(item);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _books ? '내 서재에 책을 추가했습니다.' : '글꼴을 내려받았습니다. 책의 독서 설정에서 선택해 주세요.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_message(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogItemsProvider(widget.kind));
    final installed = ref.watch(catalogInstalledProvider(widget.kind));
    final download = ref.watch(catalogDownloadProvider);
    final query = _search.text.trim().toLowerCase();
    final items = (catalog.valueOrNull ?? const <CatalogItem>[])
        .where(
          (item) =>
              (_category == null || item.category == _category) &&
              (_books ? '${item.title} ${item.author}' : item.title)
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
    final categories = <String>{
      ...catalogBookCategories,
      ...?catalog.valueOrNull?.map((item) => item.category),
    };
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          // This header scrolls when text scaling or a short foldable pane leaves
          // too little room, while normal layouts keep the search above the list.
          Flexible(
            flex: 0,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight * .55,
              ),
              child: SingleChildScrollView(
                primary: false,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: ValueKey('catalog-search-${widget.kind}'),
                      controller: _search,
                      onChanged: (_) => _changed(),
                      decoration: InputDecoration(
                        hintText: _books ? '제목·작가로 검색' : '글꼴 이름으로 검색',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: '검색어 지우기',
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _search.clear();
                                  _changed();
                                },
                              ),
                      ),
                    ),
                    if (_books)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final category in <String?>[
                              null,
                              ...categories,
                            ])
                              Padding(
                                padding: const EdgeInsets.only(
                                  right: 6,
                                  top: 8,
                                ),
                                child: ChoiceChip(
                                  label: Text(category ?? '전체'),
                                  selected: _category == category,
                                  onSelected: (_) {
                                    _category = category;
                                    _changed();
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        catalog.isLoading
                            ? '전체 목록 불러오는 중…'
                            : '${items.length}개 · 가나다순',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.builder(
                key: PageStorageKey('catalog-list-${widget.kind}'),
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: 1 + items.length,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Column(
                      children: [
                        if (catalog.isLoading)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: LinearProgressIndicator(),
                          ),
                        if (catalog.hasError || installed.hasError)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Column(
                              children: [
                                Text(
                                  catalog.hasError
                                      ? _message(catalog.error!)
                                      : '다운로드 상태를 확인하지 못했습니다.',
                                ),
                                TextButton(
                                  onPressed: download.busy ? null : _refresh,
                                  child: const Text('다시 시도'),
                                ),
                              ],
                            ),
                          ),
                        if (!catalog.isLoading &&
                            !catalog.hasError &&
                            items.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              query.isNotEmpty || _category != null
                                  ? '검색 조건에 맞는 ${_books ? '도서가' : '글꼴이'} 없습니다.'
                                  : '아직 공개된 ${_books ? '도서가' : '글꼴이'} 없습니다.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    );
                  }
                  final item = items[index - 1];
                  final key = catalogItemKey(item);
                  final downloaded =
                      installed.valueOrNull?.contains(key) ?? false;
                  if (!_books) {
                    return FontCatalogRow(
                      key: ValueKey(key),
                      item: item,
                      installed: downloaded,
                      progress: download.itemKey == key
                          ? download.progress
                          : null,
                      onDownload:
                          download.busy ||
                              !installed.hasValue ||
                              installed.isLoading ||
                              installed.hasError ||
                              downloaded
                          ? null
                          : () => _download(item),
                    );
                  }
                  return BookCatalogRow(
                    key: ValueKey(key),
                    item: item,
                    installed: downloaded,
                    progress: download.itemKey == key
                        ? download.progress
                        : null,
                    onDownload:
                        download.busy ||
                            !installed.hasValue ||
                            installed.isLoading ||
                            installed.hasError ||
                            downloaded
                        ? null
                        : () => _download(item),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
