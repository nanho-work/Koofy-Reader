/// Store versions, not build numbers: 1.10.0 must be newer than 1.9.0.
class StoreVersion implements Comparable<StoreVersion> {
  StoreVersion._(this.parts);
  final List<int> parts;
  static StoreVersion? parse(String value) {
    if (!RegExp(
      r'^(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})$',
    ).hasMatch(value)) {
      return null;
    }
    return StoreVersion._(value.split('.').map(int.parse).toList());
  }

  @override
  int compareTo(StoreVersion other) {
    for (var i = 0; i < 3; i++) {
      final difference = parts[i].compareTo(other.parts[i]);
      if (difference != 0) return difference;
    }
    return 0;
  }
}

enum UpdatePlatform { android, ios }

class UpdateNotice {
  const UpdateNotice({
    required this.latestVersion,
    required this.required,
    required this.title,
    required this.message,
    required this.storeUrl,
  });
  final String latestVersion, title, message;
  final bool required;
  final Uri storeUrl;

  static UpdateNotice? evaluate(
    Map<String, String> values,
    UpdatePlatform platform,
    String installedVersion,
  ) {
    final prefix = '${platform.name}_update_';
    String value(String key) => values['$prefix$key']?.trim() ?? '';
    if (value('enabled') != 'true') return null;
    final installed = StoreVersion.parse(installedVersion);
    final latest = StoreVersion.parse(value('latest_version'));
    final minimum = StoreVersion.parse(value('minimum_version'));
    if (installed == null ||
        latest == null ||
        minimum == null ||
        minimum.compareTo(latest) > 0 ||
        installed.compareTo(latest) >= 0) {
      return null;
    }
    final url = Uri.tryParse(value('store_url'));
    if (url == null || !_validStoreUrl(url, platform)) return null;
    final required = installed.compareTo(minimum) < 0;
    final title = value('title');
    final message = value(required ? 'required_message' : 'message');
    // Invalid remote values must never trap readers behind an empty notice.
    if (title.isEmpty ||
        title.length > 100 ||
        message.isEmpty ||
        message.length > 2000) {
      return null;
    }
    return UpdateNotice(
      latestVersion: value('latest_version'),
      required: required,
      title: title,
      message: message,
      storeUrl: url,
    );
  }

  static bool _validStoreUrl(Uri url, UpdatePlatform platform) {
    if (url.scheme != 'https' ||
        url.userInfo.isNotEmpty ||
        url.hasPort ||
        url.hasFragment) {
      return false;
    }
    return switch (platform) {
      UpdatePlatform.android =>
        url.host == 'play.google.com' &&
            url.path == '/store/apps/details' &&
            url.queryParametersAll.length == 1 &&
            url.queryParametersAll['id']?.length == 1 &&
            url.queryParameters['id'] == 'com.koofylab.koofyreader',
      UpdatePlatform.ios =>
        url.host == 'apps.apple.com' &&
            (url.path == '/app/id6814514729' ||
                url.path == '/kr/app/id6814514729') &&
            !url.hasQuery,
    };
  }
}
