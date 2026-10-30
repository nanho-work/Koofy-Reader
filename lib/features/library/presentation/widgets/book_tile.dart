import 'package:koofy_reader/core/localization/app_language.dart';
import 'dart:math' as math;
import 'dart:io';
import 'resume_touch_target.dart';

import 'package:flutter/material.dart';
import 'package:koofy_reader/features/library/domain/book.dart';

class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.book,
    this.compact = false,
    this.bottomInset = 0,
    this.topInset = 0,
  });
  final Book book;
  final bool compact;
  final double bottomInset;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    if (book.coverPath != null || book.coverAssetPath != null) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .10),
              blurRadius: 7,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image(
              image: book.coverPath != null
                  ? ResizeImage(
                      FileImage(File(book.coverPath!)),
                      width: compact ? 360 : 900,
                    )
                  : ResizeImage(
                      AssetImage(book.coverAssetPath!),
                      width: compact ? 360 : 900,
                    ),
              fit: BoxFit.cover,
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = Theme.of(context).colorScheme.onSurface;
    final colors = dark
        ? const [Color(0xFF354238), Color(0xFF444137), Color(0xFF39413A)]
        : const [Color(0xFFE8E3D7), Color(0xFFDFE4D9), Color(0xFFE6DDD4)];
    final index =
        book.id.codeUnits.fold(0, (sum, unit) => sum + unit) % colors.length;
    return Semantics(
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors[index],
          borderRadius: BorderRadius.circular(4),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0C000000),
              blurRadius: 3,
              offset: Offset(1, 2),
            ),
          ],
          border: Border(
            left: BorderSide(
              color: foreground.withValues(alpha: 0.12),
              width: 2,
            ),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 8 : 16,
            (compact ? 10 : 16) + topInset,
            compact ? 8 : 16,
            (compact ? 10 : 16) + bottomInset,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final fontSize = compact ? 15.0 : 20.0;
                    final lineHeight =
                        MediaQuery.textScalerOf(context).scale(fontSize) * 1.35;
                    final lines = math.min(
                      compact ? 3 : 4,
                      (constraints.maxHeight / lineHeight).floor(),
                    );
                    if (lines < 1) return const SizedBox.shrink();
                    return Text(
                      book.title,
                      maxLines: lines,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    );
                  },
                ),
              ),
              if (!compact)
                Text(
                  'KOOFY',
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.75),
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
    this.enableLongPress = true,
    this.badge,
    this.showResumeHint = false,
    this.onResume,
  });
  final Book book;
  final VoidCallback? onTap;
  final VoidCallback onMore;
  final String statusLabel;
  final bool enableLongPress;
  final String? badge;
  final bool showResumeHint;
  final VoidCallback? onResume;

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
          tooltip: tr("{0} 더보기", [book.title]),
          onPressed: onMore,
          icon: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.more_horiz,
              size: 18,
              color: Theme.of(context).colorScheme.onSurface,
            ),
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
                if (badge != null) ...[
                  Positioned.fill(
                    left: 8,
                    bottom: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    left: 4,
                    top: 4,
                    right: 4,
                    bottom: 4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.1),
                        ),
                      ),
                    ),
                  ),
                ],
                Positioned.fill(
                  top: badge == null ? 0 : 8,
                  right: badge == null ? 0 : 8,
                  child: Semantics(
                    label: [
                      book.title,
                      statusLabel,
                      if (badge != null) badge!,
                    ].where((label) => label.trim().isNotEmpty).join(', '),
                    button: true,
                    child: showResumeHint
                        ? ResumeTouchTarget(
                            key: ValueKey('resume-hint-${book.id}'),
                            onTap: onTap,
                            builder: (context, open, pulse, _) => InkWell(
                              onTap: open,
                              onLongPress: enableLongPress ? onMore : null,
                              child: ExcludeSemantics(
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    BookCover(
                                      book: book,
                                      compact: compact,
                                      bottomInset: 0,
                                      topInset: badge == null
                                          ? 48
                                          : math.max(48, scaler.scale(11) + 12),
                                    ),
                                    pulse,
                                  ],
                                ),
                              ),
                            ),
                          )
                        : InkWell(
                            onTap: onTap,
                            onLongPress: enableLongPress ? onMore : null,
                            child: ExcludeSemantics(
                              child: BookCover(
                                book: book,
                                compact: compact,
                                bottomInset: 0,
                                topInset: badge == null
                                    ? 48
                                    : math.max(48, scaler.scale(11) + 12),
                              ),
                            ),
                          ),
                  ),
                ),
                if (badge != null)
                  Positioned(
                    left: 6,
                    top: 8,
                    right: 8,
                    child: Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: compact ? 3 : 6,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xDD243D32),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  badge!,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        more,
                      ],
                    ),
                  ),
                if (onResume != null)
                  Positioned(
                    left: 4,
                    right: badge == null ? 4 : 12,
                    bottom: 4,
                    child: TextButton(
                      key: ValueKey('resume-group-${book.id}'),
                      onPressed: onResume,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.surface.withValues(alpha: .94),
                        foregroundColor: Theme.of(
                          context,
                        ).colorScheme.onSurface,
                      ),
                      child: Text(
                        tr('이어 읽기'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                if (badge == null)
                  Positioned(right: badge == null ? 0 : 8, top: 0, child: more),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: compact ? titleHeight : math.max(48, titleHeight + 8),
            child: title,
          ),
          if (compact) const SizedBox(height: 4),
          SizedBox(
            height: statusHeight,
            child: Text(
              statusLabel,
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
