import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koofy_reader/core/theme/app_appearance.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koofy_reader/features/ads/data/ad_repository.dart';
import 'package:koofy_reader/features/ads/data/rewarded_ad_service.dart';
import 'package:koofy_reader/features/ads/domain/ad_state.dart';
import 'package:koofy_reader/features/settings/presentation/settings_page.dart';

class _Ads extends AdRepository {
  DateTime? until;
  int? hours;
  @override
  Future<AdState> getState() async => AdState(hiddenUntil: until);
  @override
  Future<void> hideBannerForHours(int value) async {
    hours = value;
    until = DateTime.now().add(Duration(hours: value));
  }
}

class _Reward extends RewardedAdService {
  Future<void> Function()? grant;
  int calls = 0;
  bool result = true;
  @override
  Future<bool?> show() async {
    calls++;
    if (result) await grant?.call();
    return result;
  }
}

void main() {
  Future<void> mount(WidgetTester tester, _Ads ads, _Reward reward) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          adRepositoryProvider.overrideWithValue(ads),
          rewardedAdServiceProvider.overrideWith((ref) {
            reward.grant = () async {
              await ads.hideBannerForHours(4);
              ref.invalidate(adStateProvider);
            };
            return reward;
          }),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byType(FilledButton),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'reading background picker saves selection and can follow the device again',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await AppAppearance.instance.initialize();
      await mount(tester, _Ads(), _Reward());
      await tester.drag(find.byType(ListView), const Offset(0, 1000));
      await tester.pumpAndSettle();
      expect(find.text('독서 배경'), findsOneWidget);
      await tester.tap(find.text('독서 배경'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('어둡게'));
      await tester.pumpAndSettle();
      expect(AppAppearance.instance.mode, ThemeMode.dark);
      expect(
        (await SharedPreferences.getInstance()).getString(
          AppAppearance.preferenceKey,
        ),
        'dark',
      );
      await tester.tap(find.text('종이색'));
      await tester.pumpAndSettle();
      expect(AppAppearance.instance.selection, 'sepia');
      await tester.tap(find.text('기기 설정 따르기'));
      await tester.pumpAndSettle();
      expect(AppAppearance.instance.mode, ThemeMode.system);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final size in [const Size(390, 844), const Size(840, 900)]) {
    testWidgets('settings slides over library and dismisses at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [adRepositoryProvider.overrideWithValue(_Ads())],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      settingsPanelRoute(
                        const RouteSettings(name: '/settings'),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(SettingsPage)).width,
        settingsPanelWidth(size.width),
      );
      expect(tester.getRect(find.byType(SettingsPage)).right, size.width);
      await tester.tap(find.text('독서 배경'));
      await tester.pumpAndSettle();
      expect(find.text('종이색'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tapAt(Offset(10, size.height / 2));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsNothing);
      expect(find.text('open'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('one reward grants four hours and disables another viewing', (
    tester,
  ) async {
    final ads = _Ads();
    final reward = _Reward();
    await mount(tester, ads, reward);
    expect(find.byType(FilledButton), findsOneWidget);
    await tester.ensureVisible(find.text('광고 보고 4시간 광고 없이 읽기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('광고 보고 4시간 광고 없이 읽기'));
    await tester.pumpAndSettle();
    expect(ads.hours, 4);
    expect(reward.calls, 1);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(find.byKey(const ValueKey('ad-reward-countdown')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('previous longer reward is preserved and cannot be overwritten', (
    tester,
  ) async {
    final expiry = DateTime.now().add(const Duration(hours: 5));
    final ads = _Ads()..until = expiry;
    final reward = _Reward();
    await mount(tester, ads, reward);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(ads.until, expiry);
    expect(ads.hours, isNull);
    expect(reward.calls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('incomplete reward does not grant hidden time', (tester) async {
    final ads = _Ads();
    final reward = _Reward()..result = false;
    await mount(tester, ads, reward);
    await tester.ensureVisible(find.text('광고 보고 4시간 광고 없이 읽기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('광고 보고 4시간 광고 없이 읽기'));
    await tester.pumpAndSettle();
    expect(ads.hours, isNull);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
