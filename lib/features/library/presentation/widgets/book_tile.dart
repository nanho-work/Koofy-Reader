import 'package:flutter/material.dart';
import 'package:koofy_reader/features/library/domain/book.dart';

class BookTile extends StatelessWidget {
  const BookTile({
    super.key,
    required this.book,
    required this.onTap,
    this.onLongPress,
    this.showDeleteButton = false,
    this.onDeleteTap,
  });

  final Book book;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool showDeleteButton;
  final VoidCallback? onDeleteTap;

  @override
  Widget build(BuildContext context) {
    final gradient = _coverGradient(book.title);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              onLongPress: onLongPress,
              child: Ink(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradient,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0x22000000)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 12,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final compact =
                            constraints.maxWidth < 96 ||
                            constraints.maxHeight < 120;
                        return Padding(
                          padding: EdgeInsets.fromLTRB(
                            compact ? 8 : 12,
                            compact ? 8 : 10,
                            compact ? 8 : 12,
                            compact ? 8 : 12,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Spacer(),
                              Text(
                                book.title,
                                maxLines: compact ? 2 : 3,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    (compact
                                            ? Theme.of(
                                                context,
                                              ).textTheme.labelLarge
                                            : Theme.of(
                                                context,
                                              ).textTheme.titleMedium)
                                        ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          height: 1.2,
                                        ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    if (showDeleteButton && onDeleteTap != null)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Material(
                          color: const Color(0xCC1F1F1F),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: onDeleteTap,
                            child: const SizedBox(
                              width: 24,
                              height: 24,
                              child: Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          height: 12,
          margin: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFDAB98B), Color(0xFFBE9666)],
            ),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }

  List<Color> _coverGradient(String seed) {
    final base = seed.codeUnits.fold<int>(0, (acc, c) => (acc + c) % 360);
    final h = base.toDouble();
    final a = HSVColor.fromAHSV(1, h, 0.62, 0.62).toColor();
    final b = HSVColor.fromAHSV(1, (h + 24) % 360, 0.68, 0.42).toColor();
    return [a, b];
  }
}

class AddBookTile extends StatelessWidget {
  const AddBookTile({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Ink(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF6E5A47), Color(0xFF4D3E31)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0x33000000)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 12,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_circle_outline,
                        color: Colors.white,
                        size: 34,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          height: 12,
          margin: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFDAB98B), Color(0xFFBE9666)],
            ),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }
}
