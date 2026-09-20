import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:path_provider/path_provider.dart';

/// Personal covers are separate from book metadata and downloaded originals.
class BookCoverStore {
  BookCoverStore(this._storage, {Future<Directory> Function()? directory})
    : _directory = directory ?? _defaultDirectory;

  final LocalStorage _storage;
  final Future<Directory> Function() _directory;
  static const _prefix = 'library_cover_';
  static const maxBytes = 20 * 1024 * 1024;
  static final _fileName = RegExp(r'^[a-f0-9]{32}\.png$');

  static Future<Directory> _defaultDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/book_covers');
  }

  String _key(String id) => '$_prefix${base64Url.encode(utf8.encode(id))}';

  Future<List<Book>> apply(List<Book> books) async {
    final entries = await _storage.getStringEntriesByPrefix(_prefix);
    if (entries.isEmpty) return books;
    final directory = await _directory();
    return books.map((book) {
      final name = entries[_key(book.id)];
      if (name == null) return book;
      // Empty overrides explicitly restore the generated title cover.
      if (name.isEmpty) return book.withCoverPath(null);
      if (!_fileName.hasMatch(name)) return book;
      return book.withCoverPath('${directory.path}/$name');
    }).toList();
  }

  Future<void> setImage(String bookId, String sourcePath) async {
    final source = File(sourcePath);
    final size = await source.length();
    if (size == 0 || size > maxBytes) {
      throw const FormatException('20MB 이하의 이미지 파일을 선택해 주세요.');
    }

    final buffer = await ui.ImmutableBuffer.fromUint8List(
      await source.readAsBytes(),
    );
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    late final List<int> png;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final scale = math.min(
        1.0,
        1200 / math.max(descriptor.width, descriptor.height),
      );
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * scale).round()),
        targetHeight: math.max(1, (descriptor.height * scale).round()),
      );
      image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw const FormatException('이미지를 읽을 수 없습니다.');
      png = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }

    final directory = await _directory();
    await directory.create(recursive: true);
    final random = math.Random.secure();
    final name =
        '${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}.png';
    final file = File('${directory.path}/$name');
    final previous = await _storage.getString(_key(bookId));
    try {
      await file.writeAsBytes(png, flush: true);
      // Commit the reference only after the complete image is saved. A unique
      // filename also prevents Flutter's image cache showing the previous cover.
      await _storage.setString(_key(bookId), name);
    } catch (_) {
      await _deleteOwnedFile(directory, name);
      rethrow;
    }
    await _deleteOwnedFile(directory, previous);
  }

  Future<void> reset(String bookId) async {
    final previous = await _storage.getString(_key(bookId));
    await _storage.setString(_key(bookId), '');
    if (previous != null && _fileName.hasMatch(previous)) {
      await _deleteOwnedFile(await _directory(), previous);
    }
  }

  Future<void> _deleteOwnedFile(Directory directory, String? name) async {
    if (name == null || !_fileName.hasMatch(name)) return;
    try {
      await File('${directory.path}/$name').delete();
    } on FileSystemException {
      // Cleanup failure must not undo a successfully saved cover preference.
    }
  }
}
