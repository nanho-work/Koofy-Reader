import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:koofy_reader/core/localization/app_language.dart';

import 'book_shelf_layout.dart';

String episodeShelfTitle(String fallback, Object? number, Object? title) =>
    number is int && title is String && title.isNotEmpty
    ? tr('{0}화 · {1}', [number, title])
    : fallback;

String episodeReleaseLabel(DateTime? date) => date == null
    ? tr('공개')
    : tr('{0} 공개', [
        DateFormat.Md(
          AppLanguage.instance.code,
        ).add_Hm().format(date.toLocal()),
      ]);

SliverGridDelegate episodeShelfGridDelegate(int columns) =>
    SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      crossAxisSpacing: bookShelfSpacing,
      mainAxisSpacing: bookShelfSpacing,
      childAspectRatio: 2 / 3,
    );

class EpisodeCoverCaption extends StatelessWidget {
  const EpisodeCoverCaption({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6)),
    child: ColoredBox(
      color: Colors.black.withValues(alpha: 0.30),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                height: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(
                subtitle!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  height: 1.2,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
