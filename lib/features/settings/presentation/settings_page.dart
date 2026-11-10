import 'dart:io';

import 'package:koofy_reader/core/widgets/reader_alert.dart';
import 'package:koofy_reader/features/notifications/notification_widgets.dart';
import 'package:koofy_reader/core/theme/app_background.dart';
import 'package:koofy_reader/core/widgets/selection_menu.dart';
import 'package:koofy_reader/core/widgets/setting_value_title.dart';
import 'package:koofy_reader/features/catalog/presentation/catalog_page.dart'
    show catalogSidebarWidth, usesReaderSidebar, ReaderCatalogBrowser;
import 'package:koofy_reader/core/theme/reader_palette.dart';
import 'package:koofy_reader/features/reviews/data/reader_review_service.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/features/ads/presentation/ad_overlay_insets.dart';
import 'package:koofy_reader/features/support/presentation/diagnostics_page.dart';
import 'package:koofy_reader/features/library/presentation/library_trash_page.dart';
import 'package:koofy_reader/features/ads/presentation/reward_ad_button.dart';
import 'package:koofy_reader/core/theme/app_appearance.dart';
import 'package:koofy_reader/core/storage/local_storage.dart';
import 'package:koofy_reader/features/settings/data/reader_cover_settings.dart';
import 'package:koofy_reader/features/fonts/data/personal_fonts.dart';
import 'package:koofy_reader/features/fonts/presentation/personal_fonts_page.dart';
import 'package:koofy_reader/features/native_reader/application/native_reader_services.dart';
import 'cover_preview_option.dart';
import 'settings_choice_option.dart';
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

Route<void> settingsPanelRoute(RouteSettings settings) =>
    PageRouteBuilder<void>(
      settings: settings,
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      barrierLabel: tr('닫기'),
      transitionDuration: const Duration(milliseconds: 240),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, _, __) => DisplayFeatureSubScreen(
        anchorPoint: Offset(MediaQuery.sizeOf(context).width, 0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = settingsPanelWidth(constraints.maxWidth);
            return Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: width,
                child: Material(
                  elevation: 16,
                  child: const AppBackground(
                    child: SafeArea(child: SettingsPage()),
                  ),
                ),
              ),
            );
          },
        ),
      ),
      transitionsBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
    );

double settingsPanelWidth(double width) {
  final base = width >= 700 ? width / 2 : width;
  return (base * 2 / 3).clamp(width < 240 ? width : 240, width).toDouble();
}

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

enum _SettingsSection {
  reading('독서 설정'),
  data('데이터 관리'),
  privacy('알림·개인정보'),
  app('앱 정보');

  const _SettingsSection(this.label);
  final String label;
}

enum _ExpandableSetting { language, background, cover, fonts, reward }

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _busy = false;
  bool _savingCover = false;
  bool _openingFontManager = false;
  var _section = _SettingsSection.reading;

  final _expandableTiles = {
    for (final setting in _ExpandableSetting.values)
      setting: ExpansibleController(),
  };

  void _onTileChanged(_ExpandableSetting setting, bool expanded) {
    if (!expanded) return;
    for (final entry in _expandableTiles.entries) {
      if (entry.key != setting && entry.value.isExpanded) {
        entry.value.collapse();
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _expandableTiles.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _themeLabel(String mode) => switch (mode) {
    'light' => '밝게',
    'sepia' => '종이색',
    'dark' => '어둡게',
    _ => '기기 설정',
  };

  @override
  Widget build(BuildContext context) {
    final adState = ref.watch(adStateProvider);
    final languageTile = _languageTile();
    final themeTile = ListenableBuilder(
      listenable: AppAppearance.instance,
      builder: (context, _) {
        final selected = AppAppearance.instance.selection;
        return ExpansionTile(
          controller: _expandableTiles[_ExpandableSetting.background],
          onExpansionChanged: (expanded) =>
              _onTileChanged(_ExpandableSetting.background, expanded),
          tilePadding: EdgeInsets.zero,
          shape: const Border(),
          leading: const Icon(Icons.brightness_6_outlined),
          title: SettingValueTitle(
            title: tr('독서 배경'),
            value: tr(_themeLabel(selected)),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 440 ? 4 : 2;
                  const gap = 8.0;
                  final width =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final (mode, palette) in [
                        ('system', ReaderPalette.light),
                        ('light', ReaderPalette.light),
                        ('sepia', ReaderPalette.sepia),
                        ('dark', ReaderPalette.dark),
                      ])
                        SizedBox(
                          width: width,
                          child: SettingsChoiceOption(
                            label: tr(_themeLabel(mode)),
                            selected: selected == mode,
                            onTap: selected == mode
                                ? null
                                : () => _saveTheme(mode),
                            preview: _BackgroundSwatch(
                              palette: palette,
                              system: mode == 'system',
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
    final coverTile = ref
        .watch(readerCoverEnabledProvider)
        .when(
          data: (enabled) => ExpansionTile(
            controller: _expandableTiles[_ExpandableSetting.cover],
            onExpansionChanged: (expanded) =>
                _onTileChanged(_ExpandableSetting.cover, expanded),
            tilePadding: EdgeInsets.zero,
            shape: const Border(),
            leading: const Icon(Icons.collections_bookmark_outlined),
            title: SettingValueTitle(
              title: tr('독서 화면에 표지 표시'),
              singleLine: true,
              value: tr(enabled ? '켜짐' : '꺼짐'),
            ),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final showCover in [true, false]) ...[
                    if (!showCover) const SizedBox(width: 10),
                    Expanded(
                      child: CoverPreviewOption(
                        label: tr(showCover ? '표지 표시' : '표지 건너뛰기'),
                        showCover: showCover,
                        selected: enabled == showCover,
                        onTap: _savingCover || enabled == showCover
                            ? null
                            : () => _saveCover(showCover),
                      ),
                    ),
                  ],
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  tr('서재에 등록한 표지에 적용돼요.'),
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          loading: () => ListTile(title: Text(tr("표지 설정을 불러오는 중…"))),
          error: (_, __) => ListTile(
            title: Text(tr("표지 설정 다시 불러오기")),
            onTap: () => ref.invalidate(readerCoverEnabledProvider),
          ),
        );
    final backupTile = ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.backup_outlined),
      title: Text(tr("서재 백업·복원")),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const BackupPage())),
    );
    final trashTile = ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.delete_outline),
      title: Text(tr("휴지통")),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const LibraryTrashPage())),
    );
    final privacyTile = ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.privacy_tip_outlined),
      title: Text(tr("개인정보 및 광고")),
      subtitle: Text(tr("광고 선택 · 개인정보처리방침 · 문의 · 광고 신고")),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const PrivacySettingsPage()),
      ),
    );
    final versionTile = ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.info_outline),
      title: Text(tr("앱 버전")),
      subtitle: ref
          .watch(installedPackageProvider)
          .when(
            data: (info) =>
                Text(tr("{0} (빌드 {1})", [info.version, info.buildNumber])),
            loading: () => Text(tr("확인 중…")),
            error: (_, __) => Text(tr("버전 정보를 확인할 수 없습니다.")),
          ),
    );
    final diagnosticsTile = ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.bug_report_outlined),
      title: Text(tr("문제 신고용 진단 정보")),
      subtitle: Text(tr("앱 버전과 독서 설정 확인·복사")),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const DiagnosticsPage())),
    );
    final reviewTile = ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.star_outline_rounded),
      title: Text(tr("평가 남기기")),
      subtitle: Text(tr("스토어에서 사용 경험을 들려주세요")),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final opened = await ReaderReviewService.instance.openStore();
        if (!opened && context.mounted) {
          ReaderAlerts.of(context).show(
            ReaderNotice(content: Text(tr("스토어를 열지 못했습니다. 잠시 후 다시 시도해 주세요."))),
          );
        }
      },
    );
    final rewardDetails = <Widget>[
      Text(tr("리워드 광고를 끝까지 시청하면 독서 화면의 배너가 4시간 동안 숨겨집니다.")),
      const SizedBox(height: 16),
      if (LevelPlayIds.testSuite)
        TextButton(
          onPressed: () async {
            if (await LevelPlayService.instance.initialize()) {
              await LevelPlay.launchTestSuite();
            }
          },
          child: Text(tr("LevelPlay 광고 연동 테스트")),
        ),
      adState.when(
        loading: () => Text(tr("광고 상태를 불러오는 중입니다.")),
        error: (_, __) => TextButton(
          onPressed: () => ref.invalidate(adStateProvider),
          child: Text(tr("광고 상태를 불러오지 못했습니다. 다시 시도")),
        ),
        data: (state) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              state.isBannerHidden
                  ? tr("광고 숨김 적용 중")
                  : tr("광고를 시청하고 4시간 동안 배너를 숨길 수 있습니다."),
            ),
            const SizedBox(height: 12),
            RewardAdButton(
              hiddenUntil: state.hiddenUntil,
              busy: _busy,
              onPressed: _runRewardedFlow,
            ),
            if (state.isBannerHidden)
              Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(tr("숨김 시간이 끝나면 다시 시청할 수 있습니다.")),
              ),
          ],
        ),
      ),
    ];
    final fontTile = ExpansionTile(
      controller: _expandableTiles[_ExpandableSetting.fonts],
      onExpansionChanged: (expanded) =>
          _onTileChanged(_ExpandableSetting.fonts, expanded),
      tilePadding: EdgeInsets.zero,
      shape: const Border(),
      leading: const Icon(Icons.font_download_outlined),
      title: Text(tr('글꼴추가')),
      children: [
        ListTile(
          leading: const Icon(Icons.add),
          title: Text(tr('내 글꼴 추가·관리')),
          trailing: const Icon(Icons.chevron_right),
          onTap: _openFontManager,
        ),
        const Divider(height: 1),
        SizedBox(
          height: (MediaQuery.sizeOf(context).height * .5).clamp(240.0, 440.0),
          child: const ReaderCatalogBrowser(fontsOnly: true),
        ),
      ],
    );
    final notificationTile = ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.notifications_none),
      title: Text(tr('새 글 알림')),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const NotificationSettingsPage(),
        ),
      ),
    );
    final rewardTile = ExpansionTile(
      controller: _expandableTiles[_ExpandableSetting.reward],
      onExpansionChanged: (expanded) =>
          _onTileChanged(_ExpandableSetting.reward, expanded),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      shape: const Border(),
      leading: const Icon(Icons.visibility_off_outlined),
      title: Text(tr('광고 없이 읽기')),
      children: rewardDetails,
    );
    final sectionTiles = {
      _SettingsSection.reading: [languageTile, themeTile, coverTile, fontTile],
      _SettingsSection.data: [backupTile, trashTile],
      _SettingsSection.privacy: [notificationTile, privacyTile, rewardTile],
      _SettingsSection.app: [versionTile, diagnosticsTile, reviewTile],
    };
    Widget sectionLabel(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        tr(text),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
    Widget sectionCard(_SettingsSection section) => Material(
      color: const Color(0xFFC0D7C1).withValues(alpha: .30),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: ListTileTheme(
          horizontalTitleGap: 8,
          minLeadingWidth: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, tile) in sectionTiles[section]!.indexed) ...[
                if (index > 0) const Divider(height: 1),
                tile,
              ],
            ],
          ),
        ),
      ),
    );
    return DisplayFeatureSubScreen(
      anchorPoint: Offset.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide =
              widget.embedded && usesReaderSidebar(constraints.maxWidth);
          Widget categoryButton(_SettingsSection section) =>
              SelectionMenuButton(
                key: ValueKey('settings-category-${section.index}'),
                label: tr(section.label),
                selected: _section == section,
                onPressed: () => setState(() => _section = section),
              );
          final content = ListView(
            key: ValueKey(
              wide ? 'settings-section-${_section.index}' : 'settings-list',
            ),
            padding: AdOverlayInsets.padding(context, const EdgeInsets.all(16)),
            children: wide
                ? [sectionCard(_section)]
                : [
                    for (final section in _SettingsSection.values) ...[
                      sectionLabel(section.label),
                      sectionCard(section),
                    ],
                  ],
          );
          return Scaffold(
            appBar: widget.embedded
                ? null
                : AppBar(
                    automaticallyImplyLeading: false,
                    actions: [
                      IconButton(
                        tooltip: tr('닫기'),
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.maybePop(context),
                      ),
                    ],
                  ),
            body: SafeArea(
              top: widget.embedded,
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: catalogSidebarWidth,
                          child: ListView(
                            key: const ValueKey('settings-sidebar'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 8,
                            ),
                            children: [
                              for (final section in _SettingsSection.values)
                                categoryButton(section),
                            ],
                          ),
                        ),
                        Expanded(child: content),
                      ],
                    )
                  : content,
            ),
          );
        },
      ),
    );
  }

  Future<void> _saveCover(bool enabled) async {
    setState(() => _savingCover = true);
    try {
      await ref
          .read(localStorageProvider)
          .setInt(readerCoverSettingKey, enabled ? 1 : 0);
      if (mounted) ref.invalidate(readerCoverEnabledProvider);
    } catch (_) {
      if (mounted) {
        ReaderAlerts.of(context).show(
          ReaderNotice(content: Text(tr('표지 설정을 저장하지 못했습니다. 다시 시도해 주세요.'))),
        );
      }
    } finally {
      if (mounted) setState(() => _savingCover = false);
    }
  }

  Future<void> _saveTheme(String mode) async {
    try {
      await AppAppearance.instance.selectBackground(mode);
    } catch (_) {
      if (mounted) {
        ReaderAlerts.of(
          context,
        ).show(ReaderNotice(content: Text(tr('테마를 저장하지 못했습니다. 다시 시도해 주세요.'))));
      }
    }
  }

  Widget _languageTile() => ListenableBuilder(
    listenable: AppLanguage.instance,
    builder: (context, _) {
      final language = AppLanguage.instance;
      final selected = language.selection ?? 'system';
      final options = {
        'system': tr('기기 설정'),
        'ko': '한국어',
        'en': 'English',
        'ja': '日本語',
      };
      return ExpansionTile(
        controller: _expandableTiles[_ExpandableSetting.language],
        onExpansionChanged: (expanded) =>
            _onTileChanged(_ExpandableSetting.language, expanded),
        tilePadding: EdgeInsets.zero,
        shape: const Border(),
        leading: const Icon(Icons.language),
        title: SettingValueTitle(
          title: tr('언어'),
          value: language.selection == null
              ? '${options['system']} · ${options[language.code]}'
              : options[selected]!,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              children: [
                for (final codes in [
                  ['system', 'ko'],
                  ['en', 'ja'],
                ])
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        for (final code in codes)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: SettingsChoiceOption(
                                label: options[code]!,
                                selected: selected == code,
                                onTap: selected == code
                                    ? null
                                    : () => _saveLanguage(
                                        code == 'system' ? null : code,
                                      ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );

  Future<void> _saveLanguage(String? code) async {
    try {
      await AppLanguage.instance.select(code);
    } catch (_) {
      if (mounted) {
        ReaderAlerts.of(
          context,
        ).show(ReaderNotice(content: Text(tr('언어를 저장하지 못했습니다. 다시 시도해 주세요.'))));
      }
    }
  }

  Future<void> _openFontManager() async {
    if (_openingFontManager) return;
    _openingFontManager = true;
    try {
      final services = await ref.read(nativeReaderServicesProvider.future);
      if (!mounted) return;
      final support = services.supportDirectory;
      if (support == null) throw StateError(tr('글꼴 저장소를 찾지 못했습니다.'));
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => PersonalFontsPage(
            store: PersonalFontStore(
              Directory('${support.path}/personal_fonts'),
            ),
            reader: services.coordinator.store,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ReaderAlerts.of(context).show(
          ReaderNotice(
            content: Text(
              tr('글꼴 관리 화면을 열지 못했습니다.\n{0}', [localizedError(error)]),
            ),
          ),
        );
      }
    } finally {
      _openingFontManager = false;
    }
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
      ReaderAlerts.of(context).show(
        ReaderNotice(
          content: Text(
            result == true
                ? tr("4시간 동안 배너 광고를 숨깁니다.")
                : result == false
                ? tr("광고가 닫혔습니다. 시청 보상이 확인되면 자동 적용됩니다.")
                : tr("지금은 광고를 재생할 수 없습니다. 잠시 후 다시 시도해 주세요. 독서는 계속할 수 있습니다."),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ReaderAlerts.of(context).show(
          ReaderNotice(
            content: Text(tr("광고 보상을 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.")),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _BackgroundSwatch extends StatelessWidget {
  const _BackgroundSwatch({required this.palette, required this.system});

  final ReaderPalette palette;
  final bool system;

  @override
  Widget build(BuildContext context) => Container(
    width: 52,
    height: 46,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    child: Row(
      children: [
        Expanded(child: ColoredBox(color: palette.background)),
        if (system) ...[
          Expanded(child: ColoredBox(color: ReaderPalette.sepia.background)),
          Expanded(child: ColoredBox(color: ReaderPalette.dark.background)),
        ],
      ],
    ),
  );
}
