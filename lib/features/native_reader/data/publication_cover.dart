part of 'reading_publication_preparer.dart';

/// A presentation-only resource. Never participates in the body revision hash.
const readerCoverHref = '__koofy_reader_cover_v1__/cover.xhtml';

bool isReaderCoverLocator(String? locator) {
  if (locator == null) return false;
  try {
    final value = jsonDecode(locator);
    return value is Map &&
        value['href'] is String &&
        (Uri.parse(value['href'] as String).path == readerCoverHref ||
            (value['locations'] is Map &&
                value['locations']['koofyCover'] == 1));
  } on FormatException {
    return false;
  }
}

Future<Uint8List?> _readDisplayCover(String? path) async {
  if (path == null || path.isEmpty) return null;
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    final file = io.File(path);
    final length = await file.length();
    if (length == 0 || length > 20 * 1024 * 1024) return null;
    buffer = await ui.ImmutableBuffer.fromUint8List(await file.readAsBytes());
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width <= 0 ||
        descriptor.height <= 0 ||
        descriptor.width * descriptor.height > 80 * 1000 * 1000) {
      return null;
    }
    final longest = descriptor.width > descriptor.height
        ? descriptor.width
        : descriptor.height;
    final scale = longest > 1200 ? 1200 / longest : 1.0;
    codec = await descriptor.instantiateCodec(
      targetWidth: (descriptor.width * scale).round().clamp(1, 1200),
      targetHeight: (descriptor.height * scale).round().clamp(1, 1200),
    );
    image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } catch (_) {
    // A missing/deleted/corrupt optional cover must never prevent reading.
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

({Uint8List bytes, bool added, String? firstBodyHref}) _withDisplayCover(
  Uint8List original,
  Uint8List cover,
) {
  final archive = ZipDecoder().decodeBytes(original);
  final files = {for (final f in archive.files) f.name: f};
  final container = XmlDocument.parse(
    _decodeUnicode(files['META-INF/container.xml']!.content),
  );
  final opfPath = _localReference(
    '',
    _elements(container, 'rootfile').first.getAttribute('full-path')!,
  );
  final base = opfPath.contains('/')
      ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
      : '';
  final opf = XmlDocument.parse(_decodeUnicode(files[opfPath]!.content));
  final manifest = _elements(opf, 'manifest').first;
  final spine = _elements(opf, 'spine').first;
  final items = {
    for (final item in _elements(manifest, 'item'))
      item.getAttribute('id'): item,
  };
  final spineItems = _elements(spine, 'itemref')
      .map((ref) => items[ref.getAttribute('idref')])
      .whereType<XmlElement>()
      .toList();
  if (spineItems.isEmpty ||
      files.keys.any((p) => p.startsWith('__koofy_reader_cover_v1__/'))) {
    return (bytes: original, added: false, firstBodyHref: null);
  }
  // EPUB2 guide and EPUB3 semantic cover pages are authoritative. Keep the
  // publisher's cover instead of displaying the same cover twice. An image-only
  // first reading resource also counts, even in poorly tagged EPUBs.
  final declared = _elements(opf, 'reference')
      .where(
        (e) =>
            e.getAttribute('type')?.split(' ').contains('cover') == true &&
            (e.getAttribute('href')?.isNotEmpty ?? false),
      )
      .map((e) => _localReference(base, e.getAttribute('href') ?? ''))
      .toSet();
  for (var i = 0; i < spineItems.length; i++) {
    final item = spineItems[i];
    final path = _localReference(base, item.getAttribute('href')!);
    if (declared.contains(path)) {
      return (bytes: original, added: false, firstBodyHref: null);
    }
    final file = files[path];
    if (file == null ||
        !(item.getAttribute('media-type') ?? '').contains('html')) {
      continue;
    }
    final doc = XmlDocument.parse(_decodeUnicode(file.content));
    final body = _elements(doc, 'body').firstOrNull;
    if (body == null) continue;
    final coverSemantic = doc.descendants.whereType<XmlElement>().any(
      (e) => e.attributes.any(
        (a) =>
            (a.name.local == 'type' &&
                a.value.split(RegExp(r'\s+')).contains('cover')) ||
            (a.name.local == 'role' && a.value == 'doc-cover'),
      ),
    );
    final images = body.descendants.whereType<XmlElement>().where(
      (e) => const ['img', 'image'].contains(e.name.local),
    );
    final visibleText = body.descendants
        .whereType<XmlText>()
        .where(
          (t) => !t.ancestors.whereType<XmlElement>().any(
            (e) => const [
              'style',
              'script',
              'title',
              'desc',
            ].contains(e.name.local),
          ),
        )
        .map((t) => t.value)
        .join()
        .trim();
    if (coverSemantic || (i == 0 && images.isNotEmpty && visibleText.isEmpty)) {
      return (bytes: original, added: false, firstBodyHref: null);
    }
  }
  String id(String name) {
    var result = name;
    while (items.containsKey(result)) {
      result += '_';
    }
    return result;
  }

  final pageId = id('koofy-reader-display-cover');
  final imageId = id('koofy-reader-display-cover-image');
  final rootRelative =
      '${'../' * base.split('/').where((p) => p.isNotEmpty).length}$readerCoverHref';
  final nsPrefix = manifest.name.prefix;
  XmlElement element(String name, Map<String, String> attributes) => XmlElement(
    XmlName(name, nsPrefix),
    attributes.entries
        .map((e) => XmlAttribute(XmlName(e.key), e.value))
        .toList(),
  );
  manifest.children.add(
    element('item', {
      'id': pageId,
      'href': rootRelative,
      'media-type': 'application/xhtml+xml',
    }),
  );
  manifest.children.add(
    element('item', {
      'id': imageId,
      'href': rootRelative.replaceAll('cover.xhtml', 'image.png'),
      'media-type': 'image/png',
    }),
  );
  final firstPath = _localReference(
    base,
    spineItems.first.getAttribute('href')!,
  );
  final firstDocument = XmlDocument.parse(
    _decodeUnicode(files[firstPath]!.content),
  );
  final firstBody = _elements(firstDocument, 'body').first;
  firstBody.setAttribute('data-koofy-cover', 'true');
  final imageRelative =
      '${'../' * (firstPath.split('/').length - 1)}${readerCoverHref.replaceAll('cover.xhtml', 'image.png')}';
  // A generated CSS box occupies exactly one column in the first body resource.
  // No body child/text nodes are inserted: saved selectors, CFIs and TTS remain valid.
  _elements(firstDocument, 'head').first.children.add(
    XmlElement(XmlName('style'), [], [
      XmlText("""
body[data-koofy-cover]::before {
  content: '' !important; display: block !important;
  width: 100% !important; height: calc(100vh - 2px) !important;
  min-height: 0 !important; max-height: none !important;
  margin: 0 !important; padding: 0 !important;
  background: url('$imageRelative') center / contain no-repeat !important;
  -webkit-column-break-inside: avoid !important; break-inside: avoid !important;
  -webkit-column-break-after: always !important; break-after: column !important;
}
"""),
    ]),
  );
  final replaced = <String, Uint8List>{
    opfPath: Uint8List.fromList(utf8.encode(opf.toXmlString())),
    firstPath: Uint8List.fromList(utf8.encode(firstDocument.toXmlString())),
  };
  // Include an explicit cover entry so readers can return through the contents.
  for (final item in items.values) {
    if (!(item.getAttribute('properties') ?? '').split(' ').contains('nav')) {
      continue;
    }
    final path = _localReference(base, item.getAttribute('href')!);
    final nav = XmlDocument.parse(_decodeUnicode(files[path]!.content));
    final toc = _elements(nav, 'nav')
        .where(
          (e) => e.attributes.any(
            (a) => a.name.local == 'type' && a.value.split(' ').contains('toc'),
          ),
        )
        .firstOrNull;
    final list = toc == null ? null : _elements(toc, 'ol').firstOrNull;
    if (list != null) {
      final depth = path.split('/').length - 1;
      final link = XmlElement(
        XmlName('a', list.name.prefix),
        [XmlAttribute(XmlName('href'), '${'../' * depth}$firstPath')],
        [XmlText('표지')],
      );
      list.children.insert(
        0,
        XmlElement(XmlName('li', list.name.prefix), [], [link]),
      );
      replaced[path] = Uint8List.fromList(utf8.encode(nav.toXmlString()));
    }
  }
  // EPUB2 readers obtain their contents from NCX rather than an EPUB3 nav.
  for (final item in items.values) {
    if (item.getAttribute('media-type') != 'application/x-dtbncx+xml') {
      continue;
    }
    final path = _localReference(base, item.getAttribute('href')!);
    final file = files[path];
    if (file == null) continue;
    final ncx = XmlDocument.parse(_decodeUnicode(file.content));
    final map = _elements(ncx, 'navMap').firstOrNull;
    if (map == null) continue;
    var pointId = 'koofy-display-cover';
    final ids = ncx.descendants
        .whereType<XmlElement>()
        .map((e) => e.getAttribute('id'))
        .toSet();
    while (ids.contains(pointId)) {
      pointId += '_';
    }
    XmlElement node(
      String name, {
      Map<String, String> attributes = const {},
      List<XmlNode> children = const [],
    }) => XmlElement(
      XmlName(name, map.name.prefix),
      attributes.entries
          .map((e) => XmlAttribute(XmlName(e.key), e.value))
          .toList(),
      children,
    );
    for (final point in _elements(ncx, 'navPoint')) {
      final order = int.tryParse(point.getAttribute('playOrder') ?? '');
      if (order != null) point.setAttribute('playOrder', '${order + 1}');
    }
    map.children.insert(
      0,
      node(
        'navPoint',
        attributes: {'id': pointId, 'playOrder': '1'},
        children: [
          node(
            'navLabel',
            children: [
              node('text', children: [XmlText('표지')]),
            ],
          ),
          node(
            'content',
            attributes: {
              'src': '${'../' * (path.split('/').length - 1)}$firstPath',
            },
          ),
        ],
      ),
    );
    replaced[path] = Uint8List.fromList(utf8.encode(ncx.toXmlString()));
  }
  final output = Archive();
  void add(String path, List<int> bytes, {bool stored = false}) {
    final entry = ArchiveFile(path, bytes.length, bytes)
      ..lastModTime = 946684800
      ..creationTime = 946684800;
    if (stored) entry.compression = CompressionType.none;
    output.add(entry);
  }

  add('mimetype', utf8.encode('application/epub+zip'), stored: true);
  for (final file in archive.files) {
    if (file.name == 'mimetype') continue;
    add(file.name, replaced[file.name] ?? file.content);
  }
  add(readerCoverHref, utf8.encode(_displayCoverHtml));
  add(readerCoverHref.replaceAll('cover.xhtml', 'image.png'), cover);
  return (
    bytes: ZipEncoder().encodeBytes(output, modified: DateTime.utc(2000)),
    added: true,
    firstBodyHref: firstPath,
  );
}

const _displayCoverHtml = '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" id="koofy-display-cover" lang="ko"><head><title>표지</title><style>
/* One isolated viewport in both page and scroll modes. No body text nodes. */
html#koofy-display-cover { --USER__colCount: 1 !important; --RS__colCount: 1 !important; --RS__colWidth: 100vw !important; column-count: 1 !important; column-width: 100vw !important; column-gap: 0 !important; width: 100vw !important; height: 100% !important; margin: 0 !important; padding: 0 !important; }
html#koofy-display-cover body { width: 100% !important; height: calc(100vh - 2px) !important; min-height: 0 !important; margin: 0 !important; padding: 0 !important; max-width: none !important; }
html#koofy-display-cover img { display: block !important; width: 100% !important; height: 100% !important; max-width: 100% !important; max-height: 100% !important; object-fit: contain !important; margin: 0 !important; padding: 12px !important; box-sizing: border-box !important; }
</style></head><body epub:type="cover" role="doc-cover"><img src="image.png" alt=""/></body></html>''';
