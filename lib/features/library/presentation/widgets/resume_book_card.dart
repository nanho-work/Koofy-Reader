import 'package:flutter/material.dart';
import 'package:koofy_reader/core/localization/app_language.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'book_tile.dart';
import 'resume_touch_target.dart';

class ResumeBookCard extends StatelessWidget {
  const ResumeBookCard({super.key, required this.book, required this.onTap});
  final Book book;
  final VoidCallback? onTap;
  static const hintUsedKey = ResumeTouchTarget.hintUsedKey;

  @override
  Widget build(BuildContext context) => ResumeTouchTarget(
    onTap: onTap,
    builder: (context, open, pulse, showHint) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: .5),
        ),
        const SizedBox(height: 8),
        Text(tr('읽던 책'), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 10),
        Semantics(
          button: true,
          enabled: onTap != null,
          label: '${book.title}, ${tr('이어 읽기')}',
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: const ValueKey('continue-reading-button'),
              onTap: open,
              borderRadius: BorderRadius.circular(4),
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: SizedBox(
                        width: 120,
                        height: 180,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            BookCover(book: book),
                            pulse,
                            Positioned.fill(
                              child: Material(
                                type: MaterialType.transparency,
                                child: InkWell(onTap: open),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (showHint && onTap != null)
          Text(
            tr('표지를 누르면 이어 읽어요'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    ),
  );
}
