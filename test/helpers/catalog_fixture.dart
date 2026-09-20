import 'dart:async';
import 'package:koofy_reader/features/catalog/data/reader_catalog.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/domain/book.dart';

CatalogItem catalogFixture(
  int index, {
  String kind = 'book',
  String? title,
  String author = '쿠피 작가',
  String category = '시',
}) {
  Map<String, dynamic> asset(String extension) => {
    'sha256': 'a' * 64,
    'size': 1024,
    'extension': extension,
    if (kind == 'font') 'weight': 400,
  };
  return CatalogItem.fromJson({
    'id': index.toRadixString(16).padLeft(32, '0'),
    'kind': kind,
    'title': title ?? '도서 ${index.toString().padLeft(3, '0')}',
    'author': author,
    'category': category,
    'source': '쿠피 창작 자료실',
    'description': '조용한 하루에 어울리는 문장들.',
    'license': '테스트용 배포 허가',
    'version': 1,
    'assets': kind == 'book'
        ? {'txt': asset('txt'), 'cover': asset('webp')}
        : {'font400': asset('otf')},
  });
}

class CatalogFixtureBooks implements BookRepository {
  @override
  Future<List<Book>> getBooks() async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeReaderCatalog extends ReaderCatalog {
  FakeReaderCatalog(this.items) : super(CatalogFixtureBooks());
  final List<CatalogItem> items;
  final calls = <String>[];
  final installed = <String>{};
  bool fail = false;
  Completer<void>? downloadGate;
  @override
  Future<CatalogPage> list(String kind, {String? after}) async {
    calls.add('$kind:$after');
    if (fail) throw const CatalogException('연결 실패');
    final filtered = items.where((item) => item.kind == kind).toList();
    final start = int.parse(after ?? '0');
    return CatalogPage(
      filtered.skip(start).take(40).toList(),
      start + 40 < filtered.length ? '${start + 40}' : null,
    );
  }

  @override
  Future<bool> isInstalled(CatalogItem item) async =>
      installed.contains(catalogItemKey(item));
  @override
  Future<void> install(
    CatalogItem item, {
    void Function(double)? progress,
  }) async {
    progress?.call(.5);
    if (downloadGate != null) await downloadGate!.future;
    installed.add(catalogItemKey(item));
  }
}
