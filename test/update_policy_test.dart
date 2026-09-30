import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/updates/domain/update_policy.dart';

Map<String, String> updateValues({
  UpdatePlatform platform = UpdatePlatform.android,
  String latest = '1.10.0',
  String minimum = '1.0.0',
}) => {
  '${platform.name}_update_enabled': 'true',
  '${platform.name}_update_latest_version': latest,
  '${platform.name}_update_minimum_version': minimum,
  '${platform.name}_update_title': '새 버전이 있습니다',
  '${platform.name}_update_message': '선택형 업데이트 안내',
  '${platform.name}_update_required_message': '필수 업데이트 안내',
  '${platform.name}_update_store_url': platform == UpdatePlatform.android
      ? 'https://play.google.com/store/apps/details?id=com.koofylab.koofyreader'
      : 'https://apps.apple.com/kr/app/id6814514729',
};

void main() {
  test('numeric comparison, minimum boundary, newest and future versions', () {
    final values = updateValues(minimum: '1.2.0');
    UpdateNotice? check(String v) =>
        UpdateNotice.evaluate(values, UpdatePlatform.android, v);
    expect(check('1.9.0')!.required, false);
    expect(check('1.2.0')!.required, false);
    expect(check('1.1.9')!.required, true);
    expect(check('1.1.9')!.message, '필수 업데이트 안내');
    expect(check('1.10.0'), isNull);
    expect(check('2.0.0'), isNull);
  });
  test('platform policies never affect the other platform', () {
    final values = {
      ...updateValues(),
      ...updateValues(platform: UpdatePlatform.ios, latest: '1.0.0'),
    };
    expect(UpdateNotice.evaluate(values, UpdatePlatform.ios, '1.0.0'), isNull);
    expect(
      UpdateNotice.evaluate(values, UpdatePlatform.android, '1.0.0'),
      isNotNull,
    );
  });
  test('disabled, malformed and inconsistent config fail open', () {
    for (final replacement in <Map<String, String>>[
      {'android_update_enabled': 'false'},
      {'android_update_enabled': 'yes'},
      {'android_update_latest_version': '1.0'},
      {'android_update_minimum_version': '9.0.0'},
      {'android_update_minimum_version': 'bad'},
      {'android_update_title': ''},
      {'android_update_message': ''},
    ]) {
      expect(
        UpdateNotice.evaluate(
          {...updateValues(), ...replacement},
          UpdatePlatform.android,
          '1.0.0',
        ),
        isNull,
      );
    }
    for (final version in [
      'unknown',
      '1.0.0+7',
      '1.0.0-beta',
      '-1.0.0',
      '1.01.0',
    ]) {
      expect(
        UpdateNotice.evaluate(updateValues(), UpdatePlatform.android, version),
        isNull,
      );
    }
  });
  test('rejects unsafe links, other apps and platform mixups', () {
    for (final url in [
      'http://play.google.com/store/apps/details?id=com.koofylab.koofyreader',
      'https://play.google.com.evil.test/store/apps/details?id=com.koofylab.koofyreader',
      'https://play.google.com/store/apps/details?id=other.app',
      'https://play.google.com/store/apps/details?id=com.koofylab.koofyreader&id=other',
      'https://user@play.google.com/store/apps/details?id=com.koofylab.koofyreader',
      'https://apps.apple.com/kr/app/id6814514729',
    ]) {
      expect(
        UpdateNotice.evaluate(
          {...updateValues(), 'android_update_store_url': url},
          UpdatePlatform.android,
          '1.0.0',
        ),
        isNull,
      );
    }
    expect(
      UpdateNotice.evaluate(
        updateValues(platform: UpdatePlatform.ios, latest: '1.1.0'),
        UpdatePlatform.ios,
        '1.0.0',
      )!.storeUrl.host,
      'apps.apple.com',
    );
  });
}
