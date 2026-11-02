import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/catalog/data/reader_catalog.dart';
import 'helpers/catalog_fixture.dart';

class PagedCatalog extends ReaderCatalog {
  PagedCatalog(CatalogCache cache) : super(CatalogFixtureBooks(), cache: cache);
  int calls = 0;
  bool fail = false;
  bool failSecond = false;
  Completer<void>? nextPage;
  @override
  Future<CatalogPage> list(
    String kind, {
    String? after,
    String? language,
  }) async {
    calls++;
    if (fail || (failSecond && after != null)) {
      throw const CatalogException('offline');
    }
    if (after != null && nextPage != null) await nextPage!.future;
    return after == null
        ? CatalogPage([catalogFixture(1)], 'next')
        : CatalogPage([catalogFixture(2)], null);
  }
}

void main() {
  test(
    'cold catalog yields the first page before remaining pages and saves only a complete snapshot',
    () async {
      final cache = CatalogCache.memory();
      final catalog = PagedCatalog(cache);
      addTearDown(catalog.close);
      catalog.nextPage = Completer<void>();
      final first = Completer<void>();
      final done = Completer<void>();
      final values = <List<CatalogItem>>[];
      final statuses = <CatalogLoadStatus>[];
      catalog
          .watchItems('book', language: 'ko', status: statuses.add)
          .listen(
            (items) {
              values.add(items);
              if (!first.isCompleted) first.complete();
            },
            onError: done.completeError,
            onDone: done.complete,
          );
      await first.future;
      expect(values.single.length, 1);
      expect(statuses.last.complete, isFalse);
      expect(await cache.read('${catalog.endpoint}|ko|book'), isNull);
      catalog.nextPage!.complete();
      await done.future;
      expect(values.last.length, 2);
      expect(statuses.last.complete, isTrue);
      expect(
        (await cache.read('${catalog.endpoint}|ko|book'))!['items'],
        hasLength(2),
      );
    },
  );
  test(
    'persisted catalog is instant, language-isolated and retained if forced refresh fails',
    () async {
      final dir = await Directory.systemTemp.createTemp('koofy-catalog-cache-');
      addTearDown(() => dir.delete(recursive: true));
      final catalog = PagedCatalog(CatalogCache(() async => dir));
      addTearDown(catalog.close);
      expect(await catalog.completeItems('book', language: 'ko'), hasLength(2));
      expect(catalog.calls, 2);
      final restored = PagedCatalog(CatalogCache(() async => dir))..fail = true;
      addTearDown(restored.close);
      expect(
        await restored.completeItems('book', language: 'ko'),
        hasLength(2),
      );
      expect(restored.calls, 0);
      restored.forceRefresh('book', language: 'ko');
      final statuses = <CatalogLoadStatus>[];
      expect(
        await restored
            .watchItems('book', language: 'ko', status: statuses.add)
            .last,
        hasLength(2),
      );
      expect(statuses.last.failed, isTrue);
      expect(restored.calls, 1);
      await expectLater(
        restored.completeItems('book', language: 'ja'),
        throwsA(isA<CatalogException>()),
      );
    },
  );
  test(
    'failed cold pagination never caches a partial list; retry can still find later titles',
    () async {
      final cache = CatalogCache.memory();
      final catalog = PagedCatalog(cache)..failSecond = true;
      addTearDown(catalog.close);
      await expectLater(
        catalog.completeItems('book', language: 'en'),
        throwsA(isA<CatalogException>()),
      );
      expect(await cache.read('${catalog.endpoint}|en|book'), isNull);
      catalog.failSecond = false;
      expect(
        (await catalog.completeItems('book', language: 'en')).last.id,
        catalogFixture(2).id,
      );
    },
  );
  test(
    'reserved publication expires metadata before the normal cache TTL and corrupt snapshots recover',
    () async {
      final cache = CatalogCache.memory();
      await cache.save(
        'scheduled',
        [],
        nextChange: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      expect(cache.fresh((await cache.read('scheduled'))!), isFalse);
      await cache.save('current', []);
      expect(cache.fresh((await cache.read('current'))!), isTrue);
      final dir = await Directory.systemTemp.createTemp(
        'koofy-catalog-corrupt-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final disk = CatalogCache(() async => dir);
      await disk.save('bad', []);
      final file = (await Directory(
        '${dir.path}/catalog_lists',
      ).list().toList()).whereType<File>().single;
      await file.writeAsString('{broken');
      expect(await CatalogCache(() async => dir).read('bad'), isNull);
    },
  );
}
