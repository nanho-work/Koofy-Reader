import 'package:flutter/material.dart';
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
              await ads.hideBannerForHours(2);
              ref.invalidate(adStateProvider);
            };
            return reward;
          }),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('one reward grants two hours and disables another viewing', (
    tester,
  ) async {
    final ads = _Ads();
    final reward = _Reward();
    await mount(tester, ads, reward);
    expect(find.byType(FilledButton), findsOneWidget);
    await tester.tap(find.text('광고 보고 2시간 광고 없이 읽기'));
    await tester.pumpAndSettle();
    expect(ads.hours, 2);
    expect(reward.calls, 1);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(find.textContaining('광고 숨김 ·'), findsOneWidget);
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
    await tester.tap(find.text('광고 보고 2시간 광고 없이 읽기'));
    await tester.pumpAndSettle();
    expect(ads.hours, isNull);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
