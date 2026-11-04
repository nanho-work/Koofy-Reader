import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koofy_reader/features/catalog/data/reader_catalog.dart';
import 'helpers/catalog_fixture.dart';

class ControlledCatalog extends FakeReaderCatalog {
  ControlledCatalog() : super([]);
  final started = <String>[];
  Completer<void>? active;
  @override
  Future<void> install(
    CatalogItem item, {
    void Function(double)? progress,
  }) async {
    started.add(item.id);
    active = Completer<void>();
    progress?.call(.4);
    await active!.future;
    installed.add(catalogItemKey(item));
  }

  @override
  void cancelInstall() =>
      active!.completeError(const CatalogException('다운로드를 취소했습니다.'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  test(
    'queued downloads deduplicate, run one at a time, and continue after cancellation',
    () async {
      final repository = ControlledCatalog();
      final container = ProviderContainer(
        overrides: [readerCatalogProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final controller = container.read(catalogDownloadProvider.notifier);
      final a = catalogFixture(1), b = catalogFixture(2);
      final first = controller.download(a);
      expect(identical(controller.download(a), first), isTrue);
      await Future<void>.delayed(Duration.zero);
      final second = controller.download(b);
      expect(repository.started, [a.id]);
      expect(container.read(catalogDownloadProvider).queued, 1);
      final cancelled = expectLater(first, throwsA(isA<CatalogException>()));
      controller.cancel();
      await cancelled;
      await Future<void>.delayed(Duration.zero);
      expect(repository.started, [a.id, b.id]);
      expect(
        container.read(catalogDownloadProvider).itemKey,
        catalogItemKey(b),
      );
      repository.active!.complete();
      await second;
      expect(repository.installed, {catalogItemKey(b)});
      expect(container.read(catalogDownloadProvider).busy, isFalse);
      // Failed/cancelled jobs are removable and can be explicitly retried.
      final retry = controller.download(a);
      await Future<void>.delayed(Duration.zero);
      repository.active!.complete();
      await retry;
      expect(repository.installed, {catalogItemKey(a), catalogItemKey(b)});
    },
  );
}
