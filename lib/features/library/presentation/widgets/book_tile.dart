import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:koofy_reader/features/library/domain/book.dart';

class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.book,
    this.compact = false,
    this.bottomInset = 0,
  });
  final Book book;
  final bool compact;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    if (book.coverPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(book.coverPath!),
              fit: BoxFit.cover,
              cacheWidth: compact ? 360 : 900,
              errorBuilder: (context, error, stack) => _fallback(context),
            ),
            if (compact && bottomInset > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: bottomInset + 12,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0x99000000)],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return _fallback(context);
  }

  Widget _fallback(BuildContext context) {
    const colors = [
      Color(0xFF365347),
      Color(0xFF665742),
      Color(0xFF506176),
      Color(0xFF835747),
      Color(0xFF515B49),
    ];
    final index =
        book.id.codeUnits.fold(0, (sum, unit) => sum + unit) % colors.length;
    return Semantics(
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors[index],
          borderRadius: const BorderRadius.horizontal(
            right: Radius.circular(8),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x16000000),
              blurRadius: 8,
              offset: Offset(3, 4),
            ),
          ],
          border: const Border(
            left: BorderSide(color: Color(0x22FFFFFF), width: 4),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 8 : 16,
            compact ? 10 : 16,
            compact ? 8 : 16,
            (compact ? 10 : 16) + bottomInset,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  book.title,
                  maxLines: compact ? 3 : 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFFFFF5DF),
                    fontSize: compact ? 15 : 20,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ),
              if (!compact)
                const Text(
                  'KOOFY',
                  style: TextStyle(
                    color: Color(0xFFFFF5DF),
                    fontSize: 10,
                    letterSpacing: 2,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class BookTile extends StatelessWidget {
  const BookTile({
    super.key,
    required this.book,
    required this.onTap,
    required this.onMore,
    required this.statusLabel,
  });
  final Book book;
  final VoidCallback? onTap;
  final VoidCallback onMore;
  final String statusLabel;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 140;
      final scaler = MediaQuery.textScalerOf(context);
      final titleStyle = Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(height: 1.35);
      final statusStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
        height: 1.4,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
      final titleHeight = scaler.scale(titleStyle?.fontSize ?? 14) * 1.35 * 2;
      final statusHeight = scaler.scale(statusStyle?.fontSize ?? 12) * 1.4 * 2;
      final title = Text(
        book.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: titleStyle,
      );
      final more = SizedBox(
        width: 44,
        height: 48,
        child: IconButton(
          padding: EdgeInsets.zero,
          tooltip: '${book.title} 더보기',
          onPressed: onMore,
          icon: Icon(
            Icons.more_horiz,
            size: 20,
            color: compact ? const Color(0xFFFFF5DF) : null,
          ),
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Semantics(
                  label: '${book.title}, ${book.author}, $statusLabel',
                  button: true,
                  child: InkWell(
                    onTap: onTap,
                    onLongPress: onMore,
                    child: ExcludeSemantics(
                      child: BookCover(
                        book: book,
                        compact: compact,
                        bottomInset: compact ? 38 : 0,
                      ),
                    ),
                  ),
                ),
                if (compact) Positioned(right: 0, bottom: 0, child: more),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: compact ? titleHeight : math.max(48, titleHeight + 8),
            child: compact
                ? title
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: title,
                        ),
                      ),
                      more,
                    ],
                  ),
          ),
          if (compact) const SizedBox(height: 4),
          SizedBox(
            height: statusHeight,
            child: Text(
              '${book.author} · $statusLabel',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: statusStyle,
            ),
          ),
        ],
      );
    },
  );
}
