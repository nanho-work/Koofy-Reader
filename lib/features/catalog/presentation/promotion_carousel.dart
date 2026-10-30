import 'package:flutter/material.dart';

/// Manual paging keeps headlines stable while the reader is reading them.
class PromotionCarousel extends StatefulWidget {
  const PromotionCarousel({super.key, required this.cards});
  final List<Widget> cards;

  @override
  State<PromotionCarousel> createState() => _PromotionCarouselState();
}

class _PromotionCarouselState extends State<PromotionCarousel> {
  PageController? _controller;
  int _page = 0;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cards.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (_controller == null || _page >= widget.cards.length) {
              _controller?.dispose();
              _page = _page.clamp(0, widget.cards.length - 1);
              _controller = PageController(initialPage: _page);
            }
            final width = constraints.maxWidth;
            final height = (width * (width < 480 ? .67 : .5)).clamp(
              200.0,
              360.0,
            );
            return Column(
              children: [
                SizedBox(
                  height: height,
                  child: PageView.builder(
                    controller: _controller,
                    padEnds: false,
                    itemCount: widget.cards.length,
                    onPageChanged: (page) => setState(() => _page = page),
                    itemBuilder: (context, index) => widget.cards[index],
                  ),
                ),
                if (widget.cards.length > 1)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < widget.cards.length; i++)
                        Semantics(
                          label: '${i + 1} / ${widget.cards.length}',
                          selected: i == _page,
                          button: true,
                          child: InkWell(
                            onTap: () => _controller!.animateToPage(
                              i,
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut,
                            ),
                            child: SizedBox(
                              width: 32,
                              height: 40,
                              child: Center(
                                child: Container(
                                  width: i == _page ? 16 : 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(
                                          alpha: i == _page ? .8 : .2,
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
            );
          },
        ),
      ),
    );
  }
}
