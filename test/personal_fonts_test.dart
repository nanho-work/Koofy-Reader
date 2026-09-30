import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/fonts/data/personal_fonts.dart';
import 'package:koofy_reader/features/native_reader/data/native_reader_store.dart';
import 'package:drift/native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PersonalFontStore fonts;
  late Uint8List bytes;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('personal-font-test');
    fonts = PersonalFontStore(directory);
    bytes = await File('assets/fonts/Maplestory OTF Light.otf').readAsBytes();
  });
  tearDown(() async => directory.delete(recursive: true));
  test(
    'duplicate content has one identity and owned copy survives source loss',
    () async {
      final id = await fonts.install(bytes, '내 글꼴.otf');
      expect(await fonts.install(bytes, '다른 이름.otf'), id);
      final rows = await fonts.load();
      expect(rows, hasLength(1));
      expect(rows.single['label'], '내 글꼴');
      expect(await fonts.fileFor(rows.single).readAsBytes(), bytes);
      await fonts.remove(id);
      expect(await fonts.load(), isEmpty);
    },
  );
  test(
    'invalid signature, table bounds and oversized fonts do not commit',
    () async {
      final broken = Uint8List.fromList(bytes);
      ByteData.sublistView(broken).setUint32(20, bytes.length + 10);
      for (final input in [
        Uint8List(20),
        broken,
        Uint8List(PersonalFontStore.maxBytes + 1),
      ]) {
        await expectLater(
          fonts.install(input, 'broken.otf'),
          throwsFormatException,
        );
      }
      expect(await fonts.load(), isEmpty);
    },
  );
  test(
    'global personal font survives next book and can return to default',
    () async {
      final reader = NativeReaderStore(NativeDatabase.memory());
      addTearDown(reader.close);
      final id = await fonts.install(bytes, 'sample.otf');
      await reader.setGlobalFont(id);
      expect((await reader.loadGlobalPreferences()).fontId, id);
      await reader.setGlobalFont('default');
      expect((await reader.loadGlobalPreferences()).fontId, 'default');
    },
  );
}
