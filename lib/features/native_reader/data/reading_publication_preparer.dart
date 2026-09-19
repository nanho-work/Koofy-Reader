import 'dart:convert';
import 'dart:io' as io;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:xml/xml.dart';
import 'package:koofy_reader/features/native_reader/data/text_publication_map.dart';

class PreparedReadingPublication {
  const PreparedReadingPublication({
    required this.publicationId,
    required this.contentRevision,
    required this.filePath,
    required this.title,
    this.textMap,
  });

  final String publicationId;
  final String contentRevision;
  final String filePath;
  final String title;
  final TextPublicationMap? textMap;
}

/// A supported-subset error that can be displayed without losing the original.
class ReadingPublicationPreparationException implements Exception {
  const ReadingPublicationPreparationException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => message;
}

/// Makes an immutable, app-owned publication for the native reading engine.
///
/// Book identity survives renderer changes. The revision identifies the exact
/// EPUB bytes, so a locator from another document revision is never reused by
/// accident. Source copies are retained separately, including original TXT bytes.
class ReadingPublicationPreparer {
  ReadingPublicationPreparer({required this.storageDirectory});

  final io.Directory storageDirectory;
  static const int converterVersion = 1;
  static const int maxTextBytes = 20 * 1024 * 1024;
  static const int maxEpubBytes = 40 * 1024 * 1024;

  Future<PreparedReadingPublication> prepare({required Book book}) async {
    final source = await _readSource(book);
    final title = book.title.trim().isEmpty ? '제목 없는 책' : book.title;
    final author = book.author;
    final prepared = await Isolate.run(
      () => _prepareContent(source.bytes, source.extension, title, author),
    );
    final directory = io.Directory(
      '${storageDirectory.path}/${prepared.sourceHash}',
    );
    await directory.create(recursive: true);
    await _writeVerified(
      io.File('${directory.path}/source.${source.extension}'),
      source.bytes,
      prepared.sourceHash,
    );
    final publication = io.File(
      '${directory.path}/${prepared.publicationHash}.epub',
    );
    await _writeVerified(
      publication,
      prepared.publicationBytes,
      prepared.publicationHash,
    );
    // Commit the reference only after both immutable files have been flushed.
    await _atomicWrite(
      _referenceFor(book.id),
      utf8.encode(
        jsonEncode({
          'version': 1,
          'sourceHash': prepared.sourceHash,
          'extension': source.extension,
        }),
      ),
    );
    return PreparedReadingPublication(
      publicationId: book.id,
      contentRevision: 'epub-sha256:${prepared.publicationHash}',
      filePath: publication.absolute.path,
      title: title,
      textMap: source.extension == 'txt'
          ? TextPublicationMap(
              _decodeUnicode(
                source.bytes,
              ).replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
            )
          : null,
    );
  }

  io.File _referenceFor(String bookId) => io.File(
    '${storageDirectory.path}/references/${sha256.convert(utf8.encode(bookId))}.json',
  );

  Future<_SourceContent> _readSource(Book book) async {
    final path = book.isLocalFile ? book.localPath : book.assetPath;
    if (path == null || path.isEmpty) {
      throw const ReadingPublicationPreparationException(
        'missing_source',
        '책의 원본 파일 경로가 없습니다.',
      );
    }
    final lower = path.toLowerCase();
    final extension = lower.endsWith('.epub')
        ? 'epub'
        : lower.endsWith('.txt')
        ? 'txt'
        : null;
    if (extension == null) {
      throw const ReadingPublicationPreparationException(
        'unsupported_format',
        '현재 EPUB과 TXT 파일만 지원합니다.',
      );
    }
    Uint8List bytes;
    if (book.isLocalFile) {
      final source = io.File(path);
      if (!await source.exists()) {
        return _readRetainedSource(book.id);
      }
      _checkSourceSize(await source.length(), extension);
      bytes = await source.readAsBytes();
    } else {
      final data = await rootBundle.load(path);
      bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }
    _checkSourceSize(bytes.length, extension);
    return _SourceContent(bytes, extension);
  }

  Future<_SourceContent> _readRetainedSource(String bookId) async {
    try {
      final raw = jsonDecode(await _referenceFor(bookId).readAsString());
      if (raw is Map && raw['version'] == 1) {
        final hash = raw['sourceHash'];
        final extension = raw['extension'];
        if (hash is String &&
            RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) &&
            (extension == 'txt' || extension == 'epub')) {
          final file = io.File(
            '${storageDirectory.path}/$hash/source.$extension',
          );
          _checkSourceSize(await file.length(), extension as String);
          final bytes = await file.readAsBytes();
          _checkSourceSize(bytes.length, extension);
          if (sha256.convert(bytes).toString() == hash) {
            return _SourceContent(bytes, extension);
          }
        }
      }
    } on io.FileSystemException {
      // Produce the same actionable error for a missing original and copy.
    } on FormatException {
      // A corrupt reference must never be used as an arbitrary file path.
    }
    throw const ReadingPublicationPreparationException(
      'missing_source',
      '원본과 앱에 보관한 파일을 찾을 수 없습니다. 책을 다시 가져와 주세요.',
    );
  }

  static void _checkSourceSize(int length, String extension) {
    if (length <= 0) {
      throw const ReadingPublicationPreparationException('empty', '빈 파일입니다.');
    }
    final max = extension == 'epub' ? maxEpubBytes : maxTextBytes;
    if (length > max) {
      throw ReadingPublicationPreparationException(
        'too_large',
        extension == 'epub'
            ? '현재 EPUB은 40MB 이하 파일을 지원합니다.'
            : '현재 TXT는 20MB 이하 파일을 지원합니다.',
      );
    }
  }

  Future<void> _writeVerified(
    io.File file,
    List<int> bytes,
    String expectedHash,
  ) async {
    if (await file.exists() && await file.length() == bytes.length) {
      final storedHash = await sha256.bind(file.openRead()).first;
      if (storedHash.toString() == expectedHash) return;
    }
    await _atomicWrite(file, bytes);
  }

  Future<void> _atomicWrite(io.File destination, List<int> bytes) async {
    await destination.parent.create(recursive: true);
    final staging = await destination.parent.createTemp('.prepare-');
    try {
      final temp = io.File('${staging.path}/content');
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(destination.path);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }
}

class _SourceContent {
  const _SourceContent(this.bytes, this.extension);
  final Uint8List bytes;
  final String extension;
}

class _PreparedContent {
  const _PreparedContent(
    this.sourceHash,
    this.publicationHash,
    this.publicationBytes,
  );
  final String sourceHash;
  final String publicationHash;
  final Uint8List publicationBytes;
}

_PreparedContent _prepareContent(
  Uint8List bytes,
  String extension,
  String title,
  String author,
) {
  final sourceHash = sha256.convert(bytes).toString();
  final publication = extension == 'txt'
      ? _textToEpub(bytes, sourceHash, title, author)
      : bytes;
  if (extension == 'epub') _validateEpub(bytes);
  return _PreparedContent(
    sourceHash,
    sha256.convert(publication).toString(),
    publication,
  );
}

String _decodeUnicode(List<int> bytes) {
  try {
    if (bytes.length >= 4 &&
        ((bytes[0] == 0xff &&
                bytes[1] == 0xfe &&
                bytes[2] == 0 &&
                bytes[3] == 0) ||
            (bytes[0] == 0 &&
                bytes[1] == 0 &&
                bytes[2] == 0xfe &&
                bytes[3] == 0xff))) {
      throw const FormatException('UTF-32 is not supported');
    }
    if (bytes.length >= 2 &&
        ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
            (bytes[0] == 0xfe && bytes[1] == 0xff))) {
      if (bytes.length.isOdd) throw const FormatException('Truncated UTF-16');
      final littleEndian = bytes[0] == 0xff;
      final units = <int>[];
      for (var i = 2; i < bytes.length; i += 2) {
        units.add(
          littleEndian
              ? bytes[i] | (bytes[i + 1] << 8)
              : (bytes[i] << 8) | bytes[i + 1],
        );
      }
      for (var i = 0; i < units.length; i++) {
        if (units[i] >= 0xd800 && units[i] <= 0xdbff) {
          if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
            throw const FormatException('Invalid UTF-16 surrogate');
          }
        } else if (units[i] >= 0xdc00 && units[i] <= 0xdfff) {
          throw const FormatException('Invalid UTF-16 surrogate');
        }
      }
      return String.fromCharCodes(units);
    }
    final start =
        bytes.length >= 3 &&
            bytes[0] == 0xef &&
            bytes[1] == 0xbb &&
            bytes[2] == 0xbf
        ? 3
        : 0;
    return utf8.decode(bytes.sublist(start), allowMalformed: false);
  } on FormatException {
    throw const ReadingPublicationPreparationException(
      'unsupported_encoding',
      '문자 인코딩을 읽을 수 없습니다. UTF-8 또는 BOM이 있는 UTF-16으로 저장해 주세요. CP949/EUC-KR은 아직 지원하지 않습니다.',
    );
  }
}

void _checkXmlCharacters(String text) {
  for (final rune in text.runes) {
    if (rune == 9 ||
        rune == 10 ||
        rune == 13 ||
        (rune >= 0x20 && rune <= 0xd7ff) ||
        (rune >= 0xe000 && rune <= 0xfffd) ||
        (rune >= 0x10000 && rune <= 0x10ffff)) {
      continue;
    }
    throw const ReadingPublicationPreparationException(
      'invalid_text',
      '본문에 지원하지 않는 제어 문자가 있습니다. 인코딩과 파일 형식을 확인해 주세요.',
    );
  }
}

String _xml(String text) =>
    const HtmlEscape(HtmlEscapeMode.element).convert(text);

Uint8List _textToEpub(
  List<int> bytes,
  String sourceHash,
  String title,
  String author,
) {
  final text = _decodeUnicode(
    bytes,
  ).replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (text.trim().isEmpty) {
    throw const ReadingPublicationPreparationException('empty', '본문이 비어 있습니다.');
  }
  _checkXmlCharacters(text);
  _checkXmlCharacters(title);
  _checkXmlCharacters(author);
  final sections = TextPublicationMap(text).sections;
  final archive = Archive();
  void add(String name, String content, {bool stored = false}) {
    final entry = ArchiveFile.string(name, content)
      ..lastModTime = 946684800
      ..creationTime = 946684800;
    if (stored) entry.compression = CompressionType.none;
    archive.add(entry);
  }

  add('mimetype', 'application/epub+zip', stored: true);
  add(
    'META-INF/container.xml',
    '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="EPUB/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>''',
  );
  add(
    'EPUB/style.css',
    'body { line-height: 1.6; } p { white-space: pre-wrap; margin: 0; } p.blank { min-height: 1em; }',
  );
  var paragraphId = 0;
  final manifest = StringBuffer();
  final spine = StringBuffer();
  final navigation = StringBuffer();
  for (var i = 0; i < sections.length; i++) {
    final name = 'section-${i.toString().padLeft(5, '0')}';
    final body = StringBuffer();
    for (final paragraph in sections[i]) {
      final id = 'p-${(paragraphId++).toString().padLeft(7, '0')}';
      body.writeln(
        paragraph.isEmpty
            ? '<p id="$id" class="blank"><br/></p>'
            : '<p id="$id">${_xml(paragraph)}</p>',
      );
    }
    add(
      'EPUB/$name.xhtml',
      '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="und" lang="und"><head><title>${_xml(title)}</title><link rel="stylesheet" type="text/css" href="style.css"/></head><body><section id="$name">$body</section></body></html>''',
    );
    manifest.writeln(
      '<item id="$name" href="$name.xhtml" media-type="application/xhtml+xml"/>',
    );
    spine.writeln('<itemref idref="$name"/>');
    navigation.writeln(
      '<li><a href="$name.xhtml">${sections.length == 1 ? _xml(title) : '${i + 1}'}</a></li>',
    );
  }
  add(
    'EPUB/nav.xhtml',
    '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="und" lang="und"><head><title>목차</title></head><body><nav epub:type="toc" id="toc"><h1>목차</h1><ol>$navigation</ol></nav></body></html>''',
  );
  add(
    'EPUB/package.opf',
    '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="book-id">urn:sha256:$sourceHash</dc:identifier><dc:title>${_xml(title)}</dc:title><dc:creator>${_xml(author)}</dc:creator><dc:language>und</dc:language><meta property="dcterms:modified">2000-01-01T00:00:00Z</meta><meta property="rendition:layout">reflowable</meta></metadata><manifest><item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/><item id="style" href="style.css" media-type="text/css"/>$manifest</manifest><spine>$spine</spine></package>''',
  );
  return ZipEncoder().encodeBytes(archive, modified: DateTime.utc(2000));
}

void _validateEpub(Uint8List bytes) {
  try {
    final directory = ZipDirectory()..read(InputMemoryStream(bytes));
    if (directory.filePosition < 0 ||
        directory.fileHeaders.isEmpty ||
        directory.fileHeaders.length > 4096 ||
        directory.fileHeaders.length !=
            directory.totalCentralDirectoryEntries ||
        directory.numberOfThisDisk != 0 ||
        directory.diskWithTheStartOfTheCentralDirectory != 0 ||
        directory.centralDirectoryOffset + directory.centralDirectorySize >
            bytes.length) {
      _invalidEpub('정상적인 단일 ZIP 형식의 EPUB이 아닙니다.');
    }
    final entries = <String, ZipFileHeader>{};
    var expanded = 0;
    for (final header in directory.fileHeaders) {
      final path = _archivePath(header.filename);
      if (entries.containsKey(path)) _invalidEpub('EPUB에 중복 파일 경로가 있습니다.');
      final file = header.file;
      if (file == null ||
          file.filename != header.filename ||
          file.flags != header.generalPurposeBitFlag ||
          header.localHeaderOffset < 0 ||
          header.localHeaderOffset >= directory.centralDirectoryOffset) {
        _invalidEpub('EPUB 파일 헤더가 일치하지 않습니다.');
      }
      if ((header.generalPurposeBitFlag & 1) != 0) {
        throw const ReadingPublicationPreparationException(
          'drm',
          '암호화된 EPUB은 아직 지원하지 않습니다.',
        );
      }
      if (header.compressionMethod != 0 && header.compressionMethod != 8) {
        _invalidEpub('지원하지 않는 ZIP 압축 방식입니다.');
      }
      if (file.compressionMethod !=
              (header.compressionMethod == 0
                  ? CompressionType.none
                  : CompressionType.deflate) ||
          file.crc32 != header.crc32 ||
          file.compressedSize != header.compressedSize ||
          file.uncompressedSize != header.uncompressedSize) {
        _invalidEpub('EPUB 파일 헤더가 일치하지 않습니다.');
      }
      if (((header.externalFileAttributes >> 16) & 0xf000) == 0xa000) {
        _invalidEpub('EPUB 내부의 심볼릭 링크는 지원하지 않습니다.');
      }
      expanded += header.uncompressedSize;
      if (header.uncompressedSize < 0 ||
          header.uncompressedSize > 32 * 1024 * 1024 ||
          expanded > 128 * 1024 * 1024 ||
          header.compressedSize > bytes.length) {
        _invalidEpub('EPUB 압축 해제 용량이 지원 범위를 초과합니다.');
      }
      entries[path] = header;
    }
    // Validate actual decompressed size and CRC, not only attacker-controlled
    // header sizes. No archive paths are ever extracted to the filesystem.
    for (final header in entries.values) {
      _readZipEntry(header, retain: false);
    }
    Uint8List read(String path) {
      final header = entries[path];
      if (header == null) _invalidEpub('EPUB 필수 파일이 없습니다: $path');
      if (header.uncompressedSize > 4 * 1024 * 1024) {
        _invalidEpub('EPUB 문서 한 개의 크기가 지원 범위를 초과합니다.');
      }
      return _readZipEntry(header, retain: true);
    }

    XmlDocument xml(String path) =>
        XmlDocument.parse(_decodeUnicode(read(path)));
    if (entries.containsKey('META-INF/license.lcpl') ||
        entries.containsKey('META-INF/rights.xml')) {
      throw const ReadingPublicationPreparationException(
        'drm',
        'DRM 보호 EPUB은 아직 지원하지 않습니다.',
      );
    }
    // Identify DRM before attempting to parse encrypted XHTML. Standard font
    // obfuscation is checked against actual manifest fonts below.
    const fontObfuscation = {
      'http://www.idpf.org/2008/embedding',
      'http://ns.adobe.com/pdf/enc#RC',
    };
    final encryption = entries.containsKey('META-INF/encryption.xml')
        ? xml('META-INF/encryption.xml')
        : null;
    if (encryption != null &&
        _elements(encryption, 'EncryptionMethod').any(
          (method) =>
              !fontObfuscation.contains(method.getAttribute('Algorithm')),
        )) {
      throw const ReadingPublicationPreparationException(
        'drm',
        'DRM 보호 EPUB은 아직 지원하지 않습니다.',
      );
    }
    if (utf8.decode(read('mimetype')) != 'application/epub+zip') {
      _invalidEpub('EPUB mimetype이 올바르지 않습니다.');
    }
    final container = xml('META-INF/container.xml');
    final rootfiles = _elements(container, 'rootfile');
    if (rootfiles.isEmpty) _invalidEpub('EPUB 패키지 경로가 없습니다.');
    final packagePath = _localReference(
      '',
      rootfiles.first.getAttribute('full-path') ?? '',
    );
    final package = xml(packagePath);
    final root = package.rootElement;
    if (root.name.local != 'package' ||
        !const ['2.0', '3.0'].contains(root.getAttribute('version'))) {
      _invalidEpub('현재 EPUB 2 또는 EPUB 3 패키지를 지원합니다.');
    }
    for (final meta in _elements(package, 'meta')) {
      final property = meta.getAttribute('property');
      if ((property == 'rendition:layout' &&
              meta.innerText.trim() == 'pre-paginated') ||
          (meta.getAttribute('name') == 'fixed-layout' &&
              meta.getAttribute('content') == 'true')) {
        throw const ReadingPublicationPreparationException(
          'fixed_layout',
          '고정 레이아웃 EPUB은 아직 지원하지 않습니다.',
        );
      }
    }
    final manifest = <String, XmlElement>{};
    final base = packagePath.contains('/')
        ? packagePath.substring(0, packagePath.lastIndexOf('/') + 1)
        : '';
    final fontPaths = <String>{};
    final checkedDocuments = <String>{};
    for (final item in _elements(package, 'item')) {
      final id = item.getAttribute('id');
      if (id == null || id.isEmpty || manifest.containsKey(id)) {
        _invalidEpub('EPUB manifest ID가 올바르지 않습니다.');
      }
      final path = _localReference(base, item.getAttribute('href') ?? '');
      if (!entries.containsKey(path)) _invalidEpub('EPUB 리소스가 없습니다: $path');
      final properties = (item.getAttribute('properties') ?? '').split(
        RegExp(r'\s+'),
      );
      if (properties.contains('scripted') ||
          properties.contains('remote-resources')) {
        _activeContent();
      }
      final type = item.getAttribute('media-type') ?? '';
      if (type.startsWith('font/') || type.contains('font')) {
        fontPaths.add(path);
      }
      manifest[id] = item;
      if (type == 'application/xhtml+xml' ||
          type == 'image/svg+xml' ||
          path.toLowerCase().endsWith('.html') ||
          path.toLowerCase().endsWith('.xhtml') ||
          path.toLowerCase().endsWith('.svg')) {
        _validateMarkup(xml(path));
        checkedDocuments.add(path);
      } else if (type == 'text/css') {
        _validateCss(_decodeUnicode(read(path)));
        checkedDocuments.add(path);
      }
    }
    // A local link may target a resource omitted from the manifest. Check those
    // documents too rather than letting the native renderer discover active
    // content only after navigation.
    for (final path in entries.keys) {
      if (checkedDocuments.contains(path)) continue;
      final lower = path.toLowerCase();
      if (lower.endsWith('.xhtml') ||
          lower.endsWith('.html') ||
          lower.endsWith('.htm') ||
          lower.endsWith('.svg')) {
        _validateMarkup(xml(path));
      } else if (lower.endsWith('.css')) {
        _validateCss(_decodeUnicode(read(path)));
      }
    }
    final spine = _elements(package, 'itemref').toList();
    if (spine.isEmpty) _invalidEpub('EPUB 읽기 순서가 없습니다.');
    for (final reference in spine) {
      if ((reference.getAttribute('properties') ?? '').contains(
        'rendition:layout-pre-paginated',
      )) {
        throw const ReadingPublicationPreparationException(
          'fixed_layout',
          '고정 레이아웃 EPUB은 아직 지원하지 않습니다.',
        );
      }
      final item = manifest[reference.getAttribute('idref')];
      if (item == null ||
          item.getAttribute('media-type') != 'application/xhtml+xml') {
        _invalidEpub('현재 XHTML 본문으로 구성된 EPUB을 지원합니다.');
      }
    }
    if (encryption != null) {
      final encryptedData = _elements(encryption, 'EncryptedData').toList();
      if (encryptedData.isEmpty) _invalidEpub('EPUB 암호화 정보가 올바르지 않습니다.');
      for (final data in encryptedData) {
        final methods = _elements(data, 'EncryptionMethod');
        final references = _elements(data, 'CipherReference');
        if (methods.length != 1 ||
            references.length != 1 ||
            !fontObfuscation.contains(
              methods.first.getAttribute('Algorithm'),
            ) ||
            !fontPaths.contains(
              _localReference('', references.first.getAttribute('URI') ?? ''),
            )) {
          throw const ReadingPublicationPreparationException(
            'drm',
            'DRM 보호 EPUB은 아직 지원하지 않습니다.',
          );
        }
      }
    }
  } on ReadingPublicationPreparationException {
    rethrow;
  } catch (_) {
    _invalidEpub('EPUB 구조 또는 압축 데이터를 읽을 수 없습니다.');
  }
}

Iterable<XmlElement> _elements(XmlNode node, String name) => node.descendants
    .whereType<XmlElement>()
    .where((element) => element.name.local == name);

String _archivePath(String path) {
  if (path.isEmpty ||
      path.startsWith('/') ||
      path.contains('\\') ||
      path.contains(':') ||
      path.contains('\u0000') ||
      path.split('/').any((part) => part == '.' || part == '..')) {
    _invalidEpub('EPUB에 안전하지 않은 파일 경로가 있습니다.');
  }
  return path;
}

String _localReference(String base, String reference) {
  final uri = Uri.tryParse(reference);
  if (uri == null ||
      reference.isEmpty ||
      uri.hasScheme ||
      uri.hasAuthority ||
      uri.hasQuery ||
      uri.path.startsWith('/')) {
    _activeContent();
  }
  final decoded = Uri.decodeComponent(uri.path);
  if (decoded.contains('\\') ||
      decoded.contains('\u0000') ||
      decoded.contains(':')) {
    _invalidEpub('EPUB 리소스 경로가 올바르지 않습니다.');
  }
  final parts = <String>[];
  for (final part in '$base$decoded'.split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.isEmpty) _invalidEpub('EPUB 리소스가 책 바깥을 참조합니다.');
      parts.removeLast();
    } else {
      parts.add(part);
    }
  }
  if (parts.isEmpty) _invalidEpub('EPUB 리소스 경로가 비어 있습니다.');
  return parts.join('/');
}

void _validateMarkup(XmlDocument document) {
  for (final element in document.descendants.whereType<XmlElement>()) {
    final name = element.name.local.toLowerCase();
    if (const {
      'script',
      'iframe',
      'object',
      'embed',
      'form',
      'base',
      'animate',
      'animatetransform',
      'animatemotion',
      'set',
    }.contains(name)) {
      _activeContent();
    }
    if (name == 'meta' &&
        element.getAttribute('http-equiv')?.toLowerCase() == 'refresh') {
      _activeContent();
    }
    for (final attribute in element.attributes) {
      final key = attribute.name.local.toLowerCase();
      final value = attribute.value
          .replaceAll(RegExp(r'[\u0000-\u0020]'), '')
          .toLowerCase();
      if (key.startsWith('on') ||
          key == 'base' ||
          value.startsWith('javascript:') ||
          value.startsWith('vbscript:')) {
        _activeContent();
      }
      if (const {
            'src',
            'href',
            'srcset',
            'poster',
            'data',
            'action',
          }.contains(key) &&
          (RegExp(r'(^|,)[a-z][a-z0-9+.-]*:').hasMatch(value) ||
              value.startsWith('//') ||
              value.startsWith('/') ||
              value.contains('\\'))) {
        _activeContent();
      }
      if (key == 'style') _validateCss(attribute.value);
    }
    if (name == 'style') _validateCss(element.innerText);
  }
}

void _validateCss(String css) {
  final decoded = css
      .replaceAllMapped(RegExp(r'\\([0-9a-fA-F]{1,6})\s?|\\(.)'), (match) {
        if (match.group(1) != null) {
          final code = int.parse(match.group(1)!, radix: 16);
          return code > 0 && code <= 0x10ffff ? String.fromCharCode(code) : '';
        }
        return match.group(2) ?? '';
      })
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp(r'\s+'), '')
      .toLowerCase();
  if (decoded.contains('http:') ||
      decoded.contains('https:') ||
      decoded.contains('url(//') ||
      decoded.contains('url("//') ||
      decoded.contains("url('//") ||
      decoded.contains('javascript:') ||
      decoded.contains('data:') ||
      decoded.contains('file:') ||
      decoded.contains('ftp:') ||
      decoded.contains('expression(') ||
      decoded.contains('@import')) {
    _activeContent();
  }
}

Uint8List _readZipEntry(ZipFileHeader header, {required bool retain}) {
  final sink = _BoundedZipSink(header.uncompressedSize, retain: retain);
  final compressed = header.file!.getRawContent();
  if (compressed.length != header.compressedSize) {
    _invalidEpub('EPUB 압축 데이터가 잘렸습니다.');
  }
  if (header.compressionMethod == 0) {
    sink.add(compressed);
    sink.close();
  } else {
    final decoder = io.ZLibDecoder(raw: true).startChunkedConversion(sink);
    for (var offset = 0; offset < compressed.length; offset += 1024) {
      decoder.add(
        Uint8List.sublistView(
          compressed,
          offset,
          (offset + 1024).clamp(0, compressed.length),
        ),
      );
    }
    decoder.close();
  }
  if (sink.length != header.uncompressedSize || sink.crc != header.crc32) {
    _invalidEpub('EPUB 파일 크기 또는 무결성 검사가 실패했습니다.');
  }
  return sink.bytes.takeBytes();
}

class _BoundedZipSink implements Sink<List<int>> {
  _BoundedZipSink(this.limit, {required this.retain});
  final int limit;
  final bool retain;
  final BytesBuilder bytes = BytesBuilder(copy: false);
  int length = 0;
  int crc = 0;

  @override
  void add(List<int> data) {
    length += data.length;
    if (length > limit) _invalidEpub('EPUB 압축 해제 용량이 선언된 크기를 초과합니다.');
    crc = getCrc32(data, crc);
    if (retain) bytes.add(data);
  }

  @override
  void close() {}
}

Never _invalidEpub(String message) =>
    throw ReadingPublicationPreparationException('invalid_epub', message);
Never _activeContent() => throw const ReadingPublicationPreparationException(
  'active_content',
  '현재 스크립트나 외부 리소스를 사용하는 EPUB은 지원하지 않습니다.',
);
