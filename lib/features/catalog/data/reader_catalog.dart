import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:koofy_reader/features/library/data/book_repository.dart';
import 'package:koofy_reader/features/library/domain/book.dart';

const readerCatalogEndpoint = String.fromEnvironment(
  'READER_CATALOG_URL',
  defaultValue:
      'https://asia-northeast3-koofy-reader.cloudfunctions.net/readerCatalog',
);
final readerCatalogProvider = Provider<ReaderCatalog>((ref) {
  final catalog = ReaderCatalog(ref.watch(bookRepositoryProvider));
  ref.onDispose(catalog.close);
  return catalog;
});

class CatalogException implements Exception {
  const CatalogException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CatalogAsset {
  CatalogAsset.fromJson(Map<String, dynamic> json)
    : sha = json['sha256'] as String,
      size = json['size'] as int,
      extension = json['extension'] as String,
      weight = json['weight'] as int? {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sha) ||
        size < 1 ||
        size > 20 * 1024 * 1024 ||
        !const ['epub', 'txt', 'webp', 'otf', 'ttf'].contains(extension)) {
      throw const FormatException('올바르지 않은 파일 정보입니다.');
    }
  }
  final String sha, extension;
  final int size;
  final int? weight;
  String get filename => '$sha.$extension';
}

class CatalogItem {
  CatalogItem.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      kind = json['kind'] as String,
      title = json['title'] as String,
      author = json['author'] as String,
      description = json['description'] as String,
      license = json['license'] as String,
      version = json['version'] as int,
      assets = (json['assets'] as Map<String, dynamic>).map(
        (key, value) =>
            MapEntry(key, CatalogAsset.fromJson(value as Map<String, dynamic>)),
      ) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
        version < 1 ||
        !const ['book', 'font'].contains(kind) ||
        title.trim().isEmpty ||
        assets.isEmpty ||
        assets.length > 9) {
      throw const FormatException('올바르지 않은 콘텐츠 정보입니다.');
    }
    for (final entry in assets.entries) {
      final asset = entry.value;
      final valid = kind == 'book'
          ? (entry.key == 'epub' && asset.extension == 'epub') ||
                (entry.key == 'txt' && asset.extension == 'txt') ||
                (entry.key == 'cover' && asset.extension == 'webp')
          : RegExp(r'^font[1-9]00$').hasMatch(entry.key) &&
                const ['otf', 'ttf'].contains(asset.extension) &&
                asset.weight == int.parse(entry.key.substring(4));
      if (!valid) throw const FormatException('지원하지 않는 파일 정보입니다.');
    }
    if (kind == 'book' &&
        (assets.containsKey('epub') == assets.containsKey('txt') ||
            !assets.containsKey('cover'))) {
      throw const FormatException('책 파일은 EPUB 또는 TXT 한 개와 표지가 필요합니다.');
    }
  }
  final String id, kind, title, author, description, license;
  final int version;
  final Map<String, CatalogAsset> assets;
  String get bookId => 'catalog_${id}_$version';
  String get fontId => 'remote_$id';
  int get totalSize => assets.values.fold(0, (sum, asset) => sum + asset.size);
}

class CatalogPage {
  const CatalogPage(this.items, this.nextCursor);
  final List<CatalogItem> items;
  final String? nextCursor;
}

/// Published catalog only. Download files are verified and renamed atomically
/// before the library or native font manifest references them.
class ReaderCatalog {
  ReaderCatalog(
    this.books, {
    Uri? endpoint,
    Future<Directory> Function()? directory,
  }) : endpoint = endpoint ?? Uri.parse(readerCatalogEndpoint),
       _directory = directory ?? getApplicationSupportDirectory;
  final BookRepository books;
  final Uri endpoint;
  final Future<Directory> Function() _directory;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20);
  bool _installing = false;
  void close() => _client.close(force: true);

  Future<Map<String, dynamic>> _json(Map<String, String> query) async {
    try {
      if (endpoint.scheme != 'https' &&
          !(kDebugMode &&
              const [
                'localhost',
                '127.0.0.1',
                '10.0.2.2',
              ].contains(endpoint.host))) {
        throw const CatalogException('안전한 다운로드 서버 주소가 필요합니다.');
      }
      final request = await _client
          .getUrl(endpoint.replace(queryParameters: query))
          .timeout(const Duration(seconds: 20));
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final chunks = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        chunks.addAll(chunk);
        if (chunks.length > 1024 * 1024) {
          throw const CatalogException('서버 응답이 너무 큽니다.');
        }
      }
      Map<String, dynamic>? decoded;
      try {
        decoded = jsonDecode(utf8.decode(chunks)) as Map<String, dynamic>;
      } catch (_) {
        /* e.g. not deployed */
      }
      if (response.statusCode != 200) {
        throw CatalogException(
          decoded?['error'] as String? ??
              '다운로드 서버에 연결하지 못했습니다. 잠시 후 다시 시도해 주세요.',
        );
      }
      if (decoded == null) throw const CatalogException('목록을 읽을 수 없습니다.');
      return decoded;
    } on SocketException {
      throw const CatalogException(
        '인터넷 연결을 확인해 주세요. 내려받은 책과 글꼴은 오프라인에서 사용할 수 있습니다.',
      );
    } on TimeoutException {
      throw const CatalogException('연결 시간이 초과되었습니다. 다시 시도해 주세요.');
    }
  }

  Future<CatalogPage> list(String kind, {String? after}) async {
    final data = await _json({
      'kind': kind,
      if (kind == 'book') 'supportsTxt': '1',
      if (after != null) 'after': after,
    });
    return CatalogPage(
      (data['items'] as List)
          .map((item) => CatalogItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      data['nextCursor'] as String?,
    );
  }

  Future<Directory> _root() async =>
      Directory('${(await _directory()).path}/cloud_reader')
        ..createSync(recursive: true);

  Future<Map<String, dynamic>> _fontManifest(Directory root) async {
    final file = File('${root.path}/fonts/catalog.json');
    if (!await file.exists()) return {'version': 1, 'families': <dynamic>[]};
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (data['version'] != 1 || data['families'] is! List) {
      throw const CatalogException('저장된 글꼴 목록을 읽지 못했습니다.');
    }
    return data;
  }

  Future<bool> isInstalled(CatalogItem item) async {
    if (item.kind == 'book') {
      final matches = (await books.getBooks()).where(
        (book) => book.id == item.bookId,
      );
      return matches.isNotEmpty &&
          await File(matches.first.localPath!).exists();
    }
    final root = await _root();
    final manifest = await _fontManifest(root);
    return (manifest['families'] as List).any(
      (dynamic family) =>
          family['id'] == item.fontId &&
          family['remoteVersion'] == item.version &&
          (family['faces'] as List).every(
            (dynamic face) =>
                File('${root.path}/fonts/${face['file']}').existsSync(),
          ),
    );
  }

  Future<File> _download(
    CatalogItem item,
    String slot,
    Directory directory,
    void Function(int) received,
  ) async {
    final asset = item.assets[slot]!;
    await directory.create(recursive: true);
    final target = File('${directory.path}/${asset.filename}');
    if (await target.exists() &&
        await target.length() == asset.size &&
        (await sha256.bind(target.openRead()).first).toString() == asset.sha) {
      received(asset.size);
      return target;
    }
    final info = await _json({
      'action': 'download',
      'id': item.id,
      'version': '${item.version}',
      'slot': slot,
    });
    if (info['sha256'] != asset.sha || info['size'] != asset.size) {
      throw const CatalogException('파일이 변경되었습니다. 목록을 새로고침해 주세요.');
    }
    final url = Uri.parse(info['url'] as String);
    final allowed =
        url.scheme == 'https' &&
        (url.host == 'storage.googleapis.com' ||
            url.host.endsWith('.storage.googleapis.com'));
    if (!allowed &&
        !(kDebugMode &&
            url.scheme == 'http' &&
            const ['localhost', '127.0.0.1', '10.0.2.2'].contains(url.host))) {
      throw const CatalogException('잘못된 파일 주소입니다.');
    }
    final temporary = File(
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}.part',
    );
    IOSink? sink;
    try {
      final request = await _client
          .getUrl(url)
          .timeout(const Duration(seconds: 20));
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw const CatalogException('파일을 내려받지 못했습니다. 다시 시도해 주세요.');
      }
      sink = temporary.openWrite();
      var count = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        count += chunk.length;
        if (count > asset.size) {
          throw const CatalogException('파일 크기가 일치하지 않습니다.');
        }
        sink.add(chunk);
        received(chunk.length);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (count != asset.size ||
          (await sha256.bind(temporary.openRead()).first).toString() !=
              asset.sha) {
        throw const CatalogException('파일 검증에 실패했습니다. 다시 내려받아 주세요.');
      }
      return await temporary.rename(target.path);
    } finally {
      await sink?.close();
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> install(
    CatalogItem item, {
    void Function(double)? progress,
  }) async {
    if (_installing) throw const CatalogException('진행 중인 다운로드를 기다려 주세요.');
    _installing = true;
    try {
      final root = await _root();
      final folder = Directory(
        '${root.path}/${item.kind == 'book' ? 'books' : 'fonts'}',
      );
      var count = 0;
      final files = <String, File>{};
      for (final slot in item.assets.keys) {
        files[slot] = await _download(item, slot, folder, (bytes) {
          count += bytes;
          progress?.call(count / item.totalSize);
        });
      }
      if (item.kind == 'book') {
        await books.saveDownloadedBook(
          Book.localFile(
            id: item.bookId,
            title: item.title,
            author: item.author,
            description: item.description,
            localPath: (files['epub'] ?? files['txt'])!.path,
            coverPath: files['cover']!.path,
          ),
        );
      } else {
        final manifest = await _fontManifest(root);
        final families = (manifest['families'] as List)
            .where((dynamic family) => family['id'] != item.fontId)
            .toList();
        families.add({
          'id': item.fontId,
          'label': item.title,
          'cssFamily': 'KoofyRemote_${item.id}',
          'remoteVersion': item.version,
          'faces': item.assets.values
              .map(
                (asset) => {
                  'file': asset.filename,
                  'weight': asset.weight,
                  'sha256': asset.sha,
                },
              )
              .toList(),
        });
        final temporary = File('${folder.path}/catalog.json.part');
        final encoded = jsonEncode({'version': 1, 'families': families});
        if (utf8.encode(encoded).length > 1024 * 1024) {
          throw const CatalogException('설치한 글꼴 목록의 저장 한도에 도달했습니다.');
        }
        await temporary.writeAsString(encoded, flush: true);
        await temporary.rename('${folder.path}/catalog.json');
      }
    } on SocketException {
      throw const CatalogException('다운로드가 중단되었습니다. 인터넷 연결을 확인하고 다시 시도해 주세요.');
    } on TimeoutException {
      throw const CatalogException('다운로드 시간이 초과되었습니다. 다시 시도해 주세요.');
    } finally {
      _installing = false;
    }
  }
}
