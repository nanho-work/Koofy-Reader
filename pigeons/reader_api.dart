import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'packages/koofy_reader_bridge/lib/src/reader_api.g.dart',
    kotlinOut:
        'packages/koofy_reader_bridge/android/src/main/kotlin/com/koofy/reader/bridge/ReaderApi.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.koofy.reader.bridge'),
    swiftOut: 'packages/koofy_reader_bridge/ios/Classes/ReaderApi.g.swift',
    dartPackageName: 'koofy_reader_bridge',
  ),
)
class ReaderPreferences {
  ReaderPreferences({
    required this.fontScale,
    required this.columnCount,
    required this.scroll,
    required this.theme,
    this.pageTurnStyle,
    this.fontId,
    this.lineHeight,
    this.paragraphSpacing,
    this.pageMargins,
  });
  double fontScale;
  int columnCount;
  bool scroll;
  String theme;

  /// Null is the legacy default, equivalent to 'instant'.
  String? pageTurnStyle;

  /// Null or 'default' preserves the publication's original font selection.
  String? fontId;

  /// Null preserves publisher defaults. Units: line multiple, rem, margin scale.
  double? lineHeight;
  double? paragraphSpacing;
  double? pageMargins;
}

class ReaderLaunchRequest {
  ReaderLaunchRequest({
    required this.protocolVersion,
    required this.sessionId,
    required this.sessionGeneration,
    required this.publicationId,
    required this.contentRevision,
    required this.filePath,
    required this.title,
    this.initialLocatorJson,
    required this.preferences,
    this.bannerAdUnitId,
    this.adHiddenUntilEpochMs,
    this.nextBookTitle,
    this.bookmarksJson,
  });
  int protocolVersion;
  String sessionId;
  int sessionGeneration;
  String publicationId;
  String contentRevision;
  String filePath;
  String title;
  String? initialLocatorJson;
  ReaderPreferences preferences;

  /// LevelPlay viewer ad unit and the shared reward expiry.
  String? bannerAdUnitId;
  int? adHiddenUntilEpochMs;

  /// Optional next member in the user's saved group order.
  String? nextBookTitle;
  String? bookmarksJson;
}

class ReaderEvent {
  ReaderEvent({
    required this.protocolVersion,
    required this.sessionId,
    required this.sessionGeneration,
    required this.publicationId,
    required this.contentRevision,
    required this.sequence,
    required this.kind,
    this.locatorJson,
    this.preferences,
    this.errorCode,
    this.message,
    this.bookmarksJson,
  });
  int protocolVersion;
  String sessionId;
  int sessionGeneration;
  String publicationId;
  String contentRevision;
  int sequence;
  String kind;
  String? locatorJson;
  ReaderPreferences? preferences;
  String? errorCode;
  String? message;
  String? bookmarksJson;
}

@HostApi()
abstract class ReaderHostApi {
  @async
  void updateAdHiddenUntil(int? epochMs);
  @async
  void openReader(ReaderLaunchRequest request);
  @async
  void closeReader(String sessionId);
  @async
  void goTo(String sessionId, String locatorJson);
  @async
  void applyPreferences(String sessionId, ReaderPreferences preferences);
  @async
  List<ReaderEvent> pendingCheckpoints();
  @async
  void acknowledgeCheckpoint(String sessionId, int sequence);
}

@FlutterApi()
abstract class ReaderFlutterApi {
  void onEvent(ReaderEvent event);
}
