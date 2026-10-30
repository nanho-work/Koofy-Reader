import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:koofy_reader/features/settings/presentation/settings_page.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/features/ads/presentation/ad_overlay_insets.dart';
import 'package:koofy_reader/features/catalog/presentation/catalog_page.dart';
import 'discovery_feed.dart';
import 'package:koofy_reader/features/library/presentation/library_page.dart';

/// Root navigation only. Reader and detail routes cover it instead of inheriting tabs.
class MainTabsPage extends StatefulWidget {
  const MainTabsPage({super.key});
  static const selectionKey = 'main_tab_v1';
  @override
  State<MainTabsPage> createState() => _MainTabsPageState();
}

class _MainTabsPageState extends State<MainTabsPage> {
  int _selected = 0;
  bool _restored = false;
  final _visited = <int>{0};
  Future<void> _writes = Future.value();

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    int value = 0;
    try {
      value =
          (await SharedPreferences.getInstance()).getInt(
            MainTabsPage.selectionKey,
          ) ??
          0;
    } catch (_) {
      /* Start at home if preferences are unavailable. */
    }
    if (!mounted) return;
    setState(() {
      _selected = value >= 0 && value < 4 ? value : 0;
      _visited.add(_selected);
      _restored = true;
    });
  }

  void _select(int value) {
    if (_selected == value) return;
    setState(() {
      _selected = value;
      _visited.add(value);
    });
    // Preserve tap order even if storage is temporarily slow.
    _writes = _writes.then((_) async {
      try {
        await (await SharedPreferences.getInstance()).setInt(
          MainTabsPage.selectionKey,
          value,
        );
      } catch (_) {
        /* Navigation remains usable without persistence. */
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    final adBottom = AdOverlayInsets.bottomOf(context);
    final theme = Theme.of(context);
    final navigationTheme = NavigationBarTheme.of(context);
    final selectedColor = theme.brightness == Brightness.dark
        ? Colors.white
        : Colors.black;
    final labelStyle =
        navigationTheme.labelTextStyle?.resolve({}) ??
        theme.textTheme.labelMedium!;
    final iconSize = navigationTheme.iconTheme?.resolve({})?.size ?? 24;

    // NavigationBar keeps a 32px icon slot and caps label scaling at 1.3.
    // Measure translated labels so the bar fits its content instead of 80px.
    var labelHeight = 0.0;
    for (final label in ['홈', '도서', '서재', '설정']) {
      final painter = TextPainter(
        text: TextSpan(
          text: tr(label),
          style: labelStyle.copyWith(fontWeight: FontWeight.w700),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
      )..layout(maxWidth: (MediaQuery.sizeOf(context).width - 32) / 4);
      if (painter.height > labelHeight) labelHeight = painter.height;
      painter.dispose();
    }
    final navigationHeight =
        ((iconSize > 32 ? iconSize : 32) + 4 + labelHeight + 8)
            .clamp(48.0, double.infinity)
            .toDouble();

    return Scaffold(
      body: !_restored
          ? const SizedBox.expand()
          : IndexedStack(
              index: _selected,
              children: [
                TickerMode(
                  enabled: _selected == 0,
                  child: const _DiscoveryPage(),
                ),
                TickerMode(
                  enabled: _selected == 1,
                  child: _visited.contains(1)
                      ? const _BookstorePage()
                      : const SizedBox.shrink(),
                ),
                TickerMode(
                  enabled: _selected == 2,
                  child: _visited.contains(2)
                      ? const LibraryPage()
                      : const SizedBox.shrink(),
                ),
                TickerMode(
                  enabled: _selected == 3,
                  child: _visited.contains(3)
                      ? const SettingsPage(embedded: true)
                      : const SizedBox.shrink(),
                ),
              ],
            ),
      // The existing global banner reserves its own strip; never cover menu taps.
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(bottom: adBottom),
        child: NavigationBarTheme(
          data: navigationTheme.copyWith(
            indicatorColor: Colors.transparent,
            iconTheme: WidgetStateProperty.resolveWith(
              (states) => IconThemeData(
                size: iconSize,
                color: states.contains(WidgetState.selected)
                    ? selectedColor
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            labelTextStyle: WidgetStateProperty.resolveWith(
              (states) => labelStyle.copyWith(
                fontWeight: states.contains(WidgetState.selected)
                    ? FontWeight.w700
                    : FontWeight.w400,
                color: states.contains(WidgetState.selected)
                    ? selectedColor
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          child: NavigationBar(
            height: navigationHeight,
            labelPadding: const EdgeInsets.only(top: 4),
            selectedIndex: _selected,
            onDestinationSelected: _restored ? _select : null,
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.home_outlined),
                selectedIcon: const Icon(Icons.home),
                label: tr('홈'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.menu_book_outlined),
                selectedIcon: const Icon(Icons.menu_book),
                label: tr('도서'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.library_books_outlined),
                selectedIcon: const Icon(Icons.library_books),
                label: tr('서재'),
              ),
              NavigationDestination(
                icon: const Icon(Icons.settings_outlined),
                selectedIcon: const Icon(Icons.settings),
                label: tr('설정'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscoveryPage extends StatelessWidget {
  const _DiscoveryPage();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        key: const PageStorageKey('home-feed'),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: const DiscoveryFeed(),
          ),
        ),
      ),
    ),
  );
}

class _BookstorePage extends StatefulWidget {
  const _BookstorePage();
  @override
  State<_BookstorePage> createState() => _BookstorePageState();
}

class _BookstorePageState extends State<_BookstorePage> {
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final availableWidth =
          constraints.maxWidth - MediaQuery.paddingOf(context).horizontal;
      final sidebar = availableWidth >= catalogSidebarBreakpoint;
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          centerTitle: false,
          titleSpacing: sidebar ? 0 : null,
          title: Row(
            children: [
              if (sidebar)
                SizedBox(
                  width: catalogSidebarWidth,
                  child: Center(child: Text(tr('도서'))),
                )
              else ...[
                Text(tr('도서')),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: CatalogSearchField(controller: _search, compact: true),
              ),
            ],
          ),
        ),
        body: SafeArea(
          top: false,
          child: ReaderCatalogBrowser(
            booksOnly: true,
            searchController: _search,
          ),
        ),
      );
    },
  );
}
