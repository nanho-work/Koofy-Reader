import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/library/data/book_group_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FailingGroupStorage extends SharedPrefsLocalStorage {
  bool fail = false;
  @override
  Future<void> setString(String key, String value) async {
    if (fail) throw StateError('disk full');
    return super.setString(key, value);
  }
}

void main() {
  late SharedPrefsLocalStorage storage;
  late BookGroupRepository repository;
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'reader_position_b1': 'original locator',
      'library_cover_b1': 'original.png',
    });
    storage = SharedPrefsLocalStorage();
    repository = BookGroupRepository(storage);
  });
  test(
    'create, reorder and restart preserve original book IDs and reading data',
    () async {
      await repository.create('분할 소설', ['b1', 'b2', 'b3']);
      final group = (await repository.load()).single;
      await repository.reorder(group.id, ['b3', 'b1', 'b2']);
      final restored = (await BookGroupRepository(storage).load()).single;
      expect(restored.bookIds, ['b3', 'b1', 'b2']);
      expect(restored.title, '분할 소설');
      expect(await storage.getString('reader_position_b1'), 'original locator');
      expect(await storage.getString('library_cover_b1'), 'original.png');
    },
  );
  test(
    'take out and dissolve can be undone with membership and order intact',
    () async {
      await repository.create('소설', ['b1', 'b2', 'b3']);
      final group = (await repository.load()).single;
      final removal = await repository.takeOut(group.id, 'b2');
      expect((await repository.load()).single.bookIds, ['b1', 'b3']);
      expect(await repository.undo(removal), isTrue);
      expect((await repository.load()).single.bookIds, group.bookIds);
      final dissolve = await repository.dissolve(group.id);
      expect(await repository.load(), isEmpty);
      expect(await repository.undo(dissolve), isTrue);
      expect((await repository.load()).single.bookIds, group.bookIds);
    },
  );
  test(
    'undo refuses to overwrite newer changes, and duplicates are rejected',
    () async {
      final creation = await repository.create('소설', ['b1', 'b2']);
      final id = (await repository.load()).single.id;
      await repository.add(id, ['b3']);
      expect(await repository.undo(creation), isFalse);
      await expectLater(
        repository.create('중복', ['b2', 'b4']),
        throwsStateError,
      );
      await expectLater(repository.add(id, ['b3']), throwsStateError);
      await expectLater(
        repository.reorder(id, ['b1', 'b1', 'b3']),
        throwsStateError,
      );
      expect((await repository.load()).single.bookIds, ['b1', 'b2', 'b3']);
    },
  );
  test(
    'concurrent membership edits are serialized without losing books',
    () async {
      await repository.create('소설', ['b1', 'b2']);
      final id = (await repository.load()).single.id;
      await Future.wait([
        repository.add(id, ['b3']),
        repository.add(id, ['b4']),
      ]);
      expect((await repository.load()).single.bookIds, [
        'b1',
        'b2',
        'b3',
        'b4',
      ]);
    },
  );
  test(
    'empty group remains usable and removed books do not break reorder',
    () async {
      await repository.create('소설', ['b1', 'b2', 'deleted']);
      final id = (await repository.load()).single.id;
      await repository.reorder(id, ['b2', 'b1'], availableIds: {'b1', 'b2'});
      await repository.takeOut(id, 'b1');
      await repository.takeOut(id, 'b2');
      expect((await repository.load()).single.bookIds, isEmpty);
      await repository.add(id, ['b3']);
      expect((await repository.load()).single.bookIds, ['b3']);
    },
  );
  test(
    'failed save and corrupt metadata never replace existing data',
    () async {
      final failing = FailingGroupStorage();
      final repo = BookGroupRepository(failing);
      await repo.create('소설', ['b1', 'b2']);
      final original = await failing.getString(BookGroupRepository.storageKey);
      failing.fail = true;
      await expectLater(
        repo.dissolve((await repo.load()).single.id),
        throwsStateError,
      );
      expect(await failing.getString(BookGroupRepository.storageKey), original);
      failing.fail = false;
      await failing.setString(BookGroupRepository.storageKey, 'broken json');
      await expectLater(
        repo.create('새 묶음', ['b3', 'b4']),
        throwsFormatException,
      );
      expect(
        await failing.getString(BookGroupRepository.storageKey),
        'broken json',
      );
    },
  );
}
