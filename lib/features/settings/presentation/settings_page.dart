import 'package:koofy_reader/features/ads/presentation/ad_overlay_insets.dart';
import 'package:koofy_reader/features/support/presentation/diagnostics_page.dart';
import 'package:koofy_reader/features/library/presentation/library_trash_page.dart';
import 'dart:async';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/settings/data/reader_cover_settings.dart';
import 'package:unity_levelplay_mediation/unity_levelplay_mediation.dart';
import 'package:koofy_reader/features/ads/config/levelplay_ids.dart';
import 'package:koofy_reader/features/ads/data/levelplay_service.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:koofy_reader/features/ads/data/ad_repository.dart';
import 'package:koofy_reader/features/ads/data/rewarded_ad_service.dart';
import 'package:koofy_reader/features/privacy/presentation/privacy_pages.dart';
import 'package:koofy_reader/features/backup/presentation/backup_page.dart';
import 'package:koofy_reader/features/updates/data/update_service.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  Timer? _ticker;
  bool _busy = false;
  bool _savingCover = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _remaining(DateTime until) {
    final minutes = (until.difference(DateTime.now()).inSeconds / 60)
        .ceil()
        .clamp(1, 1000000);
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return hours == 0
        ? '$rest분 남음'
        : '$hours시간${rest == 0 ? '' : ' $rest분'} 남음';
  }

  @override
  Widget build(BuildContext context) {
    final adState = ref.watch(adStateProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        padding: AdOverlayInsets.padding(context, const EdgeInsets.all(16)),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline),
            title: const Text('앱 버전'),
            subtitle: ref
                .watch(installedPackageProvider)
                .when(
                  data: (info) =>
                      Text('${info.version} (빌드 ${info.buildNumber})'),
                  loading: () => const Text('확인 중…'),
                  error: (_, __) => const Text('버전 정보를 확인할 수 없습니다.'),
                ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.backup_outlined),
            title: const Text('서재 백업·복원'),
            subtitle: const Text('책·표지·묶음·읽던 위치를 파일로 보관'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => const BackupPage())),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_outline),
            title: const Text('휴지통'),
            subtitle: const Text('삭제한 책과 해제한 묶음 복원'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const LibraryTrashPage()),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('개인정보 및 광고'),
            subtitle: const Text('광고 선택 · 개인정보처리방침 · 문의 · 광고 신고'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PrivacySettingsPage(),
              ),
            ),
          ),
          ref
              .watch(readerCoverEnabledProvider)
              .when(
                data: (enabled) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('독서 화면에 표지 표시'),
                  subtitle: const Text(
                    '각 책에 등록한 표지를 첫 장으로 표시합니다. 이어 읽기는 읽던 위치에서 시작하며, EPUB의 기존 표지는 유지합니다.',
                  ),
                  value: enabled,
                  onChanged: _savingCover
                      ? null
                      : (value) async {
                          setState(() => _savingCover = true);
                          try {
                            await ref
                                .read(localStorageProvider)
                                .setInt(readerCoverSettingKey, value ? 1 : 0);
                            ref.invalidate(readerCoverEnabledProvider);
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    '표지 설정을 저장하지 못했습니다. 다시 시도해 주세요.',
                                  ),
                                ),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _savingCover = false);
                          }
                        },
                ),
                loading: () => const ListTile(title: Text('표지 설정을 불러오는 중…')),
                error: (_, __) => ListTile(
                  title: const Text('표지 설정 다시 불러오기'),
                  onTap: () => ref.invalidate(readerCoverEnabledProvider),
                ),
              ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('문제 신고용 진단 정보'),
            subtitle: const Text('앱 버전과 독서 설정 확인·복사'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DiagnosticsPage()),
            ),
          ),
          const Divider(height: 24),
          Text('광고 없이 읽기', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('리워드 광고를 끝까지 시청하면 서재·설정·독서 화면의 배너가 2시간 동안 숨겨집니다.'),
          const SizedBox(height: 16),
          if (LevelPlayIds.testSuite)
            TextButton(
              onPressed: () async {
                if (await LevelPlayService.instance.initialize()) {
                  await LevelPlay.launchTestSuite();
                }
              },
              child: const Text('LevelPlay 광고 연동 테스트'),
            ),
          adState.when(
            loading: () => const Text('광고 상태를 불러오는 중입니다.'),
            error: (_, __) => TextButton(
              onPressed: () => ref.invalidate(adStateProvider),
              child: const Text('광고 상태를 불러오지 못했습니다. 다시 시도'),
            ),
            data: (state) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.isBannerHidden
                      ? '광고 숨김 · ${_remaining(state.hiddenUntil!)}'
                      : '광고를 시청하고 2시간 동안 배너를 숨길 수 있습니다.',
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy || state.isBannerHidden
                      ? null
                      : _runRewardedFlow,
                  child: Text(
                    _busy
                        ? '처리 중…'
                        : state.isBannerHidden
                        ? '광고 숨김 적용 중'
                        : '광고 보고 2시간 광고 없이 읽기',
                  ),
                ),
                if (state.isBannerHidden)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('숨김 시간이 끝나면 다시 시청할 수 있습니다.'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runRewardedFlow() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Check storage again to avoid starting another reward from stale UI.
      final state = await ref.read(adRepositoryProvider).getState();
      if (!mounted) return;
      if (state.isBannerHidden) {
        ref.invalidate(adStateProvider);
        return;
      }
      final result = await ref.read(rewardedAdServiceProvider).show();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result == true
                ? '2시간 동안 배너 광고를 숨깁니다.'
                : result == false
                ? '광고가 닫혔습니다. 시청 보상이 확인되면 자동 적용됩니다.'
                : '지금은 광고를 재생할 수 없습니다. 잠시 후 다시 시도해 주세요. 독서는 계속할 수 있습니다.',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('광고 보상을 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
