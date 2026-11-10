import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../data/reader_catalog.dart';
import 'catalog_cover.dart';

class PromotionCover extends StatelessWidget {
  const PromotionCover({super.key, required this.item, this.label, this.onTap});

  final CatalogItem item;
  final String? label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label ?? item.title,
    button: onTap != null,
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox.expand(child: CatalogCover(item: item)),
      ),
    ),
  );
}

class PromotionCarousel extends StatelessWidget {
  const PromotionCarousel({super.key, required this.cards});
  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = (width * (width < 480 ? .67 : .5)).clamp(200.0, 360.0);
        final slotWidth = math.min(width, height * 2 / 3 + 12);
        if (cards.length < 3) {
          final cardWidth = math.min(slotWidth, width / cards.length);
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final card in cards)
                SizedBox(
                  width: cardWidth,
                  height: math.max(0.0, cardWidth - 12) * 1.5,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: card,
                  ),
                ),
            ],
          );
        }
        final visibleSlots = cards.length < 5 ? 3.0 : 4.4;
        final viewportWidth = math.min(width, slotWidth * visibleSlots);
        final fraction = slotWidth / viewportWidth;
        return Center(
          child: SizedBox(
            width: viewportWidth,
            child: _PromotionPages(
              key: ValueKey((cards.first.key, cards.length, fraction)),
              cards: cards,
              height: height,
              fraction: fraction,
            ),
          ),
        );
      },
    );
  }
}

class _PromotionPages extends StatefulWidget {
  const _PromotionPages({
    super.key,
    required this.cards,
    required this.height,
    required this.fraction,
  });

  final List<Widget> cards;
  final double height;
  final double fraction;

  @override
  State<_PromotionPages> createState() => _PromotionPagesState();
}

class _PromotionPagesState extends State<_PromotionPages>
    with WidgetsBindingObserver {
  static const _interval = Duration(milliseconds: 3500);
  bool get _hasMultiple => widget.cards.length > 1;
  // Start on a multiple of the card count so the first card has a neighbor
  // on both sides and the carousel can keep moving in either direction.
  late int _page = _hasMultiple ? widget.cards.length * 1000 : 0;
  late final _controller = PageController(
    initialPage: _page,
    keepPage: false,
    viewportFraction: widget.fraction,
  );
  final _pointers = <int>{};
  Timer? _timer;
  bool _scrolling = false;
  bool _canAnimate = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tabVisible = TickerMode.of(context);
    final routeVisible = ModalRoute.isCurrentOf(context) ?? true;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _canAnimate = tabVisible && routeVisible && !reduceMotion;
    _restartTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (!_hasMultiple ||
        !_canAnimate ||
        !_foreground ||
        _scrolling ||
        _pointers.isNotEmpty) {
      return;
    }
    _timer = Timer(_interval, () {
      if (_controller.hasClients) _moveTo(_page + 1);
    });
  }

  void _moveTo(int page) {
    if (page == _page || !_controller.hasClients) return;
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _select(int index) {
    final count = widget.cards.length;
    var delta = (index - _page % count) % count;
    if (delta > count ~/ 2) delta -= count;
    final target = _page + delta;
    _moveTo(target < 0 ? target + count : target);
  }

  void _release(PointerEvent event) {
    _pointers.remove(event.pointer);
    _restartTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.cards.length;
    final selected = _page % count;
    final foreground = Theme.of(context).colorScheme.onSurface;
    return Listener(
      onPointerDown: (event) {
        _pointers.add(event.pointer);
        _timer?.cancel();
      },
      onPointerUp: _release,
      onPointerCancel: _release,
      child: Column(
        children: [
          SizedBox(
            height: widget.height,
            child: NotificationListener<ScrollNotification>(
              onNotification: (event) {
                if (event.depth != 0) return false;
                if (event is ScrollStartNotification) {
                  _scrolling = true;
                  _timer?.cancel();
                } else if (event is ScrollEndNotification) {
                  _scrolling = false;
                  _restartTimer();
                }
                return false;
              },
              child: PageView.builder(
                controller: _controller,
                itemCount: _hasMultiple ? null : 1,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (context, page) {
                  final active = page == _page;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        final current = _controller.hasClients
                            ? _controller.page ?? _page.toDouble()
                            : _page.toDouble();
                        final distance = (page - current).abs().clamp(0.0, 2.0);
                        final blur = 2.0 * math.min(distance, 1.0);
                        return Transform.scale(
                          scale: 1 - .18 * distance,
                          child: Opacity(
                            opacity: 1 - .22 * distance,
                            child: ImageFiltered(
                              enabled: blur > 0,
                              imageFilter: ImageFilter.blur(
                                sigmaX: blur,
                                sigmaY: blur,
                              ),
                              child: child,
                            ),
                          ),
                        );
                      },
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        excludeFromSemantics: true,
                        onTap: active ? null : () => _moveTo(page),
                        child: ExcludeSemantics(
                          excluding: !active,
                          child: IgnorePointer(
                            ignoring: !active,
                            child: widget.cards[page % count],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (_hasMultiple)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < count; i++)
                  Semantics(
                    label: '${i + 1} / $count',
                    selected: i == selected,
                    button: true,
                    child: InkWell(
                      onTap: () => _select(i),
                      child: SizedBox(
                        width: 32,
                        height: 40,
                        child: Center(
                          child: Container(
                            width: i == selected ? 16 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: foreground.withValues(
                                alpha: i == selected ? .8 : .2,
                              ),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
