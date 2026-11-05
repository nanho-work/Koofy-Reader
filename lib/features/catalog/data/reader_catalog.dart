import 'package:koofy_reader/features/library/data/book_group_repository.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/features/analytics/data/reader_analytics.dart';
import 'dart:async';
import 'catalog_cache.dart';
export 'catalog_cache.dart' show CatalogCache;
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
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

class CatalogLoadStatus {
  const CatalogLoadStatus({
    this.refreshing = false,
    this.complete = false,
    this.failed = false,
  });
  final bool refreshing, complete, failed;
}

final catalogLoadStatusProvider =
    StateProvider.family<CatalogLoadStatus, String>(
      (ref, kind) => const CatalogLoadStatus(),
    );

// Show disk metadata immediately, then progressively fill a cold catalog. Search
// still spans all pages; UI explicitly labels the period before it is complete.
final catalogItemsProvider = FutureProvider.family<List<CatalogItem>, String>((
  ref,
  kind,
) async {
  final language = ref.watch(appContentLanguageProvider);
  var active = true;
  Timer? refreshTimer;
  ref.onDispose(() {
    active = false;
    refreshTimer?.cancel();
  });
  final repository = ref.watch(readerCatalogProvider);
  void schedule(Duration delay) {
    refreshTimer = Timer(delay, () {
      if (!active) return;
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        schedule(CatalogCache.lifetime);
        return;
      }
      ref.invalidateSelf();
    });
  }

  var last = <CatalogItem>[];
  await for (final items in repository.watchItems(
    kind,
    language: language,
    status: (value) {
      if (active) {
        ref.read(catalogLoadStatusProvider(kind).notifier).state = value;
      }
    },
  )) {
    last = items;
    if (active) ref.state = AsyncData(items);
  }
  final delay = await repository.refreshDelay(kind, language: language);
  if (active) schedule(delay);
  return last;
});

// Repair old downloaded monthly groups without replacing personal cover choices.
final monthlyGroupCoverSyncProvider = FutureProvider<void>((ref) async {
  final groups = await ref.watch(bookGroupsProvider.future);
  final covers = ref.read(groupCoverStoreProvider);
  final pending = <String, String>{};
  for (final group in groups) {
    if (group.id.startsWith('group_monthly_') &&
        !await covers.hasSelection(group.id)) {
      pending[group.id.substring('group_monthly_'.length)] = group.id;
    }
  }
  if (pending.isEmpty) return;
  final catalog = ref.read(readerCatalogProvider);
  var changed = false;
  try {
    for (final language in ['ko', 'en', 'ja']) {
      String? cursor;
      final visited = <String>{};
      do {
        final page = await catalog.list(
          'series',
          after: cursor,
          language: language,
        );
        for (final issue in page.items) {
          final groupId = pending[issue.id];
          if (groupId == null || issue.issueMonth.isEmpty) continue;
          try {
            final file = await catalog.coverFile(issue);
            if (file == null) continue;
            await covers.setImage(groupId, file.path, onlyIfAbsent: true);
            pending.remove(issue.id);
            changed = true;
          } catch (error) {
            debugPrint('Monthly cover deferred: $error');
          }
        }
        cursor = page.nextCursor;
        if (cursor != null && !visited.add(cursor)) break;
      } while (cursor != null && pending.isNotEmpty);
      if (pending.isEmpty) break;
    }
  } finally {
    if (changed) ref.invalidate(bookGroupsProvider);
  }
});

String catalogItemKey(CatalogItem item) =>
    '${item.kind}_${item.id}_${item.version}';
final catalogInstalledProvider = FutureProvider.family<Set<String>, String>((
  ref,
  kind,
) async {
  final repository = ref.watch(readerCatalogProvider);
  // Local deletion must immediately make a downloaded book available again.
  if (kind == 'book' || kind == 'monthly' || kind.startsWith('series:')) {
    ref.watch(booksProvider);
  }
  final value = ref.watch(catalogItemsProvider(kind));
  final items =
      value.valueOrNull ?? await ref.watch(catalogItemsProvider(kind).future);
  return repository.installedKeys(items ?? const []);
});

class CatalogDownloadState {
  const CatalogDownloadState({
    this.itemKey,
    this.progress = 0,
    this.title = '',
    this.queued = 0,
  });
  final String title;
  final int queued;
  final String? itemKey;
  final double progress;
  bool get busy => itemKey != null;
}

final catalogDownloadProvider =
    NotifierProvider<CatalogDownloadController, CatalogDownloadState>(
      CatalogDownloadController.new,
    );

class CatalogDownloadController extends Notifier<CatalogDownloadState> {
  @override
  CatalogDownloadState build() => const CatalogDownloadState();
  Future<void> _tail = Future.value();
  final _jobs = <String, Future<void>>{};
  void cancel() => ref.read(readerCatalogProvider).cancelInstall();
  Future<void> download(CatalogItem item) {
    final key = catalogItemKey(item);
    if (_jobs.containsKey(key)) return _jobs[key]!;
    final job = _tail
        .catchError((Object _) {})
        .then((_) => _performDownload(item));
    _jobs[key] = job;
    if (state.busy) {
      state = CatalogDownloadState(
        itemKey: state.itemKey,
        title: state.title,
        progress: state.progress,
        queued: _jobs.length - 1,
      );
    }
    _tail = job.then<void>(
      (_) {
        _jobs.remove(key);
      },
      onError: (Object _, StackTrace __) {
        _jobs.remove(key);
      },
    );
    return job;
  }

  Future<void> _performDownload(CatalogItem item) async {
    if (item.upcoming) throw const CatalogException('아직 공개되지 않은 회차입니다.');

    final key = catalogItemKey(item);
    state = CatalogDownloadState(
      itemKey: key,
      title: item.title,
      queued: (_jobs.length - 1).clamp(0, 999),
    );
    ReaderAnalytics.instance.download(
      kind: item.kind,
      id: item.id,
      result: 'start',
    );
    try {
      await ref
          .read(readerCatalogProvider)
          .install(
            item,
            progress: (value) {
              state = CatalogDownloadState(
                itemKey: key,
                title: item.title,
                queued: (_jobs.length - 1).clamp(0, 999),
                progress: value.clamp(0, 1),
              );
            },
          );
      if (item.seriesId != null && item.issueMonth.isNotEmpty) {
        // Grouping failure must not roll back a successfully verified download.
        try {
          final episodes = [
            ...await ref
                .read(readerCatalogProvider)
                .completeItems('series:${item.seriesId}'),
          ]..sort((a, b) => a.episodeNumber!.compareTo(b.episodeNumber!));
          await ref
              .read(bookGroupRepositoryProvider)
              .addMonthlyEpisode(
                item.seriesId!,
                item.seriesTitle.isEmpty ? item.issueMonth : item.seriesTitle,
                item.bookId,
                episodes.map((episode) => episode.bookId).toList(),
              );
          ref.invalidate(bookGroupsProvider);
        } catch (error) {
          debugPrint('Monthly grouping deferred: $error');
        }
      }
      ReaderAnalytics.instance.download(
        kind: item.kind,
        id: item.id,
        result: 'success',
      );
      ref.invalidate(booksProvider);
      ref.invalidate(catalogInstalledProvider(item.kind));
      if (item.seriesId != null) {
        ref.invalidate(catalogInstalledProvider('series:${item.seriesId}'));
      }
    } catch (_) {
      ReaderAnalytics.instance.download(
        kind: item.kind,
        id: item.id,
        result: 'failed',
      );
      rethrow;
    } finally {
      state = const CatalogDownloadState();
    }
  }
}

// Only visible font rows request preview bytes. These are independent of the
// font installation manifest and cached on disk by verified content hash.
final catalogFontPreviewProvider = FutureProvider.autoDispose
    .family<Uint8List?, CatalogItem>((ref, item) {
      return ref.watch(readerCatalogProvider).fontPreview(item);
    });

final catalogCoverProvider = FutureProvider.autoDispose
    .family<Uint8List?, CatalogItem>((ref, item) {
      return ref.watch(readerCatalogProvider).coverPreview(item);
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
        !const [
          'epub',
          'txt',
          'webp',
          'otf',
          'ttf',
          'png',
        ].contains(extension)) {
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
    : json = Map<String, dynamic>.unmodifiable(json),
      id = json['id'] as String,
      kind = json['kind'] as String,
      title = json['title'] as String,
      author = json['author'] as String,
      description = json['description'] as String,
      license = json['license'] as String,
      category = json['category'] as String? ?? '기타',
      source = json['source'] as String? ?? '',
      seriesTitle = json['seriesTitle'] as String? ?? '',
      issueMonth = json['issueMonth'] as String? ?? '',
      releaseDate = json['releaseDate'] as String? ?? '',
      publishedAt = json['publishedAt'] as String? ?? '',
      compilationId = json['compilationId'] as String? ?? '',
      seriesId = json['seriesId'] as String?,
      episodeNumber = json['episodeNumber'] as int?,
      episodeTitle = json['episodeTitle'] as String?,
      seriesStatus = json['seriesStatus'] as String? ?? 'ongoing',
      episodeCount = json['episodeCount'] as int? ?? 0,
      preview = json['preview'] is Map<String, dynamic>
          ? CatalogAsset.fromJson(json['preview'] as Map<String, dynamic>)
          : null,
      upcoming = json['upcoming'] == true,
      releaseAt = json['releaseAt'] as String? ?? '',
      version = json['version'] as int,
      assets = (json['assets'] as Map<String, dynamic>).map(
        (key, value) =>
            MapEntry(key, CatalogAsset.fromJson(value as Map<String, dynamic>)),
      ) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
        version < 1 ||
        !const ['book', 'font', 'series'].contains(kind) ||
        title.trim().isEmpty ||
        assets.isEmpty ||
        assets.length > 9) {
      throw const FormatException('올바르지 않은 콘텐츠 정보입니다.');
    }
    if ((seriesId != null &&
            (kind != 'book' ||
                !RegExp(r'^[a-f0-9]{32}$').hasMatch(seriesId!) ||
                episodeNumber == null ||
                episodeNumber! < 0 ||
                episodeTitle == null ||
                episodeTitle!.trim().isEmpty)) ||
        (seriesId == null && episodeNumber != null) ||
        episodeCount < 0 ||
        !const ['ongoing', 'completed'].contains(seriesStatus)) {
      throw const FormatException('올바르지 않은 회차 정보입니다.');
    }
    if (preview != null &&
        (kind != 'font' ||
            preview!.extension != 'png' ||
            preview!.size > 128 * 1024)) {
      throw const FormatException('올바르지 않은 미리보기 정보입니다.');
    }
    for (final entry in assets.entries) {
      final asset = entry.value;
      final valid = kind == 'series'
          ? entry.key == 'cover' && asset.extension == 'webp'
          : kind == 'book'
          ? (entry.key == 'epub' && asset.extension == 'epub') ||
                (entry.key == 'txt' && asset.extension == 'txt') ||
                (entry.key == 'cover' && asset.extension == 'webp')
          : RegExp(r'^font[1-9]00$').hasMatch(entry.key) &&
                const ['otf', 'ttf'].contains(asset.extension) &&
                asset.weight == int.parse(entry.key.substring(4));
      if (!valid) throw const FormatException('지원하지 않는 파일 정보입니다.');
    }
    if (kind == 'book' &&
        !upcoming &&
        (assets.containsKey('epub') == assets.containsKey('txt') ||
            !assets.containsKey('cover'))) {
      throw const FormatException('책 파일은 EPUB 또는 TXT 한 개와 표지가 필요합니다.');
    }
  }
  final Map<String, dynamic> json;
  final String id, kind, title, author, description, license, category, source;
  final bool upcoming;
  final String releaseAt;
  final int version;
  final Map<String, CatalogAsset> assets;
  final CatalogAsset? preview;
  final String issueMonth, releaseDate, compilationId, seriesTitle, publishedAt;
  final String? seriesId, episodeTitle;
  final int? episodeNumber;
  final int episodeCount;
  final String seriesStatus;
  String get seriesStatusLabel => seriesStatus == 'completed' ? '완결' : '연재 중';
  String get displayTitle =>
      seriesId == null ? title : '$episodeNumber화 · $episodeTitle';
  String get bookId => 'catalog_${id}_$version';
  String get fontId => 'remote_$id';
  int get totalSize => assets.values.fold(0, (sum, asset) => sum + asset.size);
}

class CatalogPage {
  const CatalogPage(this.items, this.nextCursor, {this.nextChange});
  final DateTime? nextChange;
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
    CatalogCache? cache,
  }) : _cacheOverride = cache,
       endpoint = endpoint ?? Uri.parse(readerCatalogEndpoint),
       _directory = directory ?? getApplicationSupportDirectory;
  final BookRepository books;
  final Uri endpoint;
  final Future<Directory> Function() _directory;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20);
  bool _installing = false;
  bool _cancelInstall = false;
  String? _installKey;
  HttpClientRequest? _installRequest;
  void cancelInstall() {
    _cancelInstall = true;
    _installRequest?.abort(const CatalogException('다운로드를 취소했습니다.'));
  }

  void _checkCancelled(CatalogItem item) {
    if (_installing && _installKey == catalogItemKey(item) && _cancelInstall) {
      throw const CatalogException('다운로드를 취소했습니다.');
    }
  }

  final CatalogCache? _cacheOverride;
  late final _cache = _cacheOverride ?? CatalogCache(_directory);
  final _forced = <String>{};
  final _requests = <String, Future<Map<String, dynamic>>>{};
  final _covers = <String, Future<Uint8List?>>{};
  final _coverSizes = <String, int>{};
  int _coverBytes = 0;
  void _forgetCover(String key) {
    _covers.remove(key);
    _coverBytes -= _coverSizes.remove(key) ?? 0;
  }

  final _downloads = <String, Future<File>>{};
  String _listKey(String kind, String language) => '$endpoint|$language|$kind';
  Future<Duration> refreshDelay(
    String kind, {
    required String language,
  }) async => _cache.refreshDelay(await _cache.read(_listKey(kind, language)));
  void forceRefresh(String kind, {String? language}) =>
      _forced.add(_listKey(kind, language ?? AppLanguage.instance.code));

  Stream<List<CatalogItem>> watchItems(
    String kind, {
    required String language,
    required void Function(CatalogLoadStatus) status,
  }) async* {
    final key = _listKey(kind, language);
    final force = _forced.remove(key);
    final saved = await _cache.read(key);
    List<CatalogItem>? previous;
    try {
      if (saved != null) {
        previous = (saved['items'] as List)
            .map(
              (item) =>
                  CatalogItem.fromJson(Map<String, dynamic>.from(item as Map)),
            )
            .toList();
      }
    } catch (_) {
      /* A corrupt snapshot must fall back to the server. */
    }
    if (previous != null) {
      status(
        CatalogLoadStatus(
          complete: true,
          refreshing: force || !_cache.fresh(saved!),
        ),
      );
      yield previous;
      if (!force && _cache.fresh(saved!)) return;
    } else {
      status(const CatalogLoadStatus(refreshing: true));
    }
    final items = <String, CatalogItem>{}, visited = <String>{};
    String? cursor;
    DateTime? nextChange;
    try {
      do {
        final page = await list(kind, after: cursor, language: language);
        for (final item in page.items) {
          items[item.id] = item;
        }
        if (page.nextChange != null &&
            (nextChange == null || page.nextChange!.isBefore(nextChange))) {
          nextChange = page.nextChange;
        }
        cursor = page.nextCursor;
        if (cursor != null && !visited.add(cursor)) {
          throw const CatalogException('목록을 끝까지 읽지 못했습니다. 다시 시도해 주세요.');
        }
        // Preserve a complete saved search index during refresh; cold starts can
        // already browse the first page while subsequent pages arrive.
        if (previous == null && cursor != null) yield _sorted(items.values);
      } while (cursor != null);
      final result = _sorted(items.values);
      try {
        await _cache.save(
          key,
          result.map((item) => item.json).toList(),
          nextChange: nextChange,
        );
      } catch (_) {
        /* Disk cache failure must not discard a successful response. */
      }
      status(const CatalogLoadStatus(complete: true));
      yield result;
    } catch (_) {
      status(CatalogLoadStatus(complete: previous != null, failed: true));
      if (previous == null) rethrow;
    }
  }

  Future<CatalogItem?> sourceForBook(Book book) async {
    final identity = RegExp(
      r'^catalog_([a-f0-9]{32})_[1-9][0-9]*$',
    ).firstMatch(book.id)?.group(1);
    if (identity == null) return null;
    var json =
        book.catalogMetadata ??
        await _cache.findBook(book.id, endpoint.toString());
    if (json == null) {
      final response = await _json({'action': 'info', 'id': identity});
      json = Map<String, dynamic>.from(response['item'] as Map);
      final source = CatalogItem.fromJson(json);
      if (source.id != identity || source.kind != 'book') {
        throw const CatalogException('올바르지 않은 콘텐츠 정보입니다.');
      }
      try {
        await _cache.save('$endpoint|source:$identity', [json]);
      } catch (_) {
        /* Metadata caching is optional. */
      }
    }
    final source = CatalogItem.fromJson(json);
    return source.id == identity && source.kind == 'book' ? source : null;
  }

  Future<List<CatalogItem>> completeItems(String kind, {String? language}) =>
      watchItems(
        kind,
        language: language ?? AppLanguage.instance.code,
        status: (_) {},
      ).last;

  List<CatalogItem> _sorted(Iterable<CatalogItem> items) =>
      items.toList()..sort((a, b) {
        final order = a.title.toLowerCase().compareTo(b.title.toLowerCase());
        return order != 0 ? order : a.id.compareTo(b.id);
      });

  Future<Set<String>> installedKeys(List<CatalogItem> items) async {
    if (books is! LocalBookRepository) {
      final installed = <String>{};
      for (final item in items) {
        if (item.kind != 'series' && await isInstalled(item)) {
          installed.add(catalogItemKey(item));
        }
      }
      return installed;
    }
    final local = {for (final book in await books.getBooks()) book.id: book};
    final installed = <String>{};
    Map<String, dynamic>? fonts;
    Directory? fontRoot;
    for (final item in items) {
      if (item.upcoming) continue;
      if (item.kind == 'book') {
        final path = local[item.bookId]?.localPath;
        if (path != null && await File(path).exists()) {
          installed.add(catalogItemKey(item));
        }
      } else if (item.kind == 'font') {
        fontRoot ??= await _root();
        fonts ??= await _fontManifest(fontRoot);
        if ((fonts['families'] as List).any(
          (dynamic family) =>
              family['id'] == item.fontId &&
              family['remoteVersion'] == item.version &&
              (family['faces'] as List).every(
                (dynamic face) => File(
                  '${fontRoot!.path}/fonts/${face['file']}',
                ).existsSync(),
              ),
        )) {
          installed.add(catalogItemKey(item));
        }
      }
    }
    return installed;
  }

  void close() => _client.close(force: true);

  Future<Map<String, dynamic>> _json(Map<String, String> query) {
    final key = jsonEncode(query);
    return _requests.putIfAbsent(
      key,
      () => _fetchJson(query).whenComplete(() {
        _requests.remove(key);
      }),
    );
  }

  Future<Map<String, dynamic>> _fetchJson(Map<String, String> query) async {
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

  Future<CatalogPage> list(
    String kind, {
    String? after,
    String? language,
  }) async {
    final seriesId = kind.startsWith('series:') ? kind.substring(7) : null;
    final data = await _json({
      'kind': seriesId != null || kind == 'monthly' ? 'book' : kind,
      'supportsPrologue': '1',
      if (kind == 'monthly') 'action': 'monthly',
      if (kind == 'book' || seriesId != null) 'supportsTxt': '1',
      if (kind == 'book') 'supportsSeries': '1',
      if (kind != 'font') 'language': language ?? AppLanguage.instance.code,
      if (seriesId != null) 'seriesId': seriesId,
      if (seriesId != null) 'supportsUpcoming': '1',
      if (after != null) 'after': after,
    });
    return CatalogPage(
      (data['items'] as List)
          .map((item) => CatalogItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      data['nextCursor'] as String?,
      nextChange: DateTime.tryParse(data['nextChangeAt'] as String? ?? ''),
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
    if (item.upcoming) return false;
    if (item.kind == 'series') return false;
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
    void Function(int) received, {
    CatalogAsset? previewAsset,
  }) {
    final key =
        '${directory.path}/${(previewAsset ?? item.assets[slot]!).filename}';
    return _downloads.putIfAbsent(
      key,
      () =>
          _downloadFile(
            item,
            slot,
            directory,
            received,
            previewAsset: previewAsset,
          ).whenComplete(() {
            _downloads.remove(key);
          }),
    );
  }

  Future<File> _downloadFile(
    CatalogItem item,
    String slot,
    Directory directory,
    void Function(int) received, {
    CatalogAsset? previewAsset,
  }) async {
    final asset = previewAsset ?? item.assets[slot]!;
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
      _checkCancelled(item);
      if (_installKey == catalogItemKey(item)) _installRequest = request;
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
        _checkCancelled(item);
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

  Future<Uint8List?> fontPreview(CatalogItem item) async {
    final preview = item.preview;
    if (item.kind != 'font' || preview == null) return null;
    final root = await _root();
    final file = await _download(
      item,
      'preview',
      Directory('${root.path}/previews'),
      (_) {},
      previewAsset: preview,
    );
    return file.readAsBytes();
  }

  Future<File?> coverFile(CatalogItem item) async {
    if (!item.assets.containsKey('cover')) return null;
    final root = await _root();
    return _download(item, 'cover', Directory('${root.path}/previews'), (_) {});
  }

  Future<Uint8List?> coverPreview(CatalogItem item) {
    final asset = item.assets['cover'];
    if (asset == null) return Future.value(null);
    if (_covers.length >= 32 && !_covers.containsKey(asset.filename)) {
      _forgetCover(_covers.keys.first);
    }
    return _covers.putIfAbsent(asset.filename, () async {
      try {
        final file = await coverFile(item);
        final bytes = await file?.readAsBytes();
        if (bytes != null && _covers.containsKey(asset.filename)) {
          _coverBytes += bytes.length - (_coverSizes[asset.filename] ?? 0);
          _coverSizes[asset.filename] = bytes.length;
          while (_coverBytes > 8 * 1024 * 1024 && _covers.isNotEmpty) {
            _forgetCover(_covers.keys.first);
          }
        }
        return bytes;
      } catch (_) {
        _forgetCover(asset.filename);
        rethrow;
      }
    });
  }

  Future<void> install(
    CatalogItem item, {
    void Function(double)? progress,
  }) async {
    if (item.upcoming) throw const CatalogException('아직 공개되지 않은 회차입니다.');
    if (item.kind == 'series') {
      throw const CatalogException('작품 안에서 내려받을 회차를 선택해 주세요.');
    }
    if (_installing) throw const CatalogException('진행 중인 다운로드를 기다려 주세요.');
    _installing = true;
    _cancelInstall = false;
    _installKey = catalogItemKey(item);
    try {
      final root = await _root();
      final folder = Directory(
        '${root.path}/${item.kind == 'book' ? 'books' : 'fonts'}',
      );
      var count = 0;
      final files = <String, File>{};
      for (final slot in item.assets.keys) {
        _checkCancelled(item);
        files[slot] = await _download(item, slot, folder, (bytes) {
          count += bytes;
          progress?.call(count / item.totalSize);
        });
      }
      _checkCancelled(item);
      if (item.kind == 'book') {
        await books.saveDownloadedBook(
          Book.localFile(
            id: item.bookId,
            catalogMetadata: item.json,
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
      _installKey = null;
      _installRequest = null;
    }
  }
}
