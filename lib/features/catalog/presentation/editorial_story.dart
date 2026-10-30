import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/reader_catalog.dart';

/// Reuses the catalog cover cache; art and text remain separately accessible.
class EditorialStory extends ConsumerWidget {
  const EditorialStory({super.key, required this.item, this.onTap});
  final CatalogItem item;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(catalogCoverProvider(item)).valueOrNull;
    final artwork = AspectRatio(
      aspectRatio: 3 / 2,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: bytes == null
            ? ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainer,
                child: const Icon(Icons.auto_stories_outlined, size: 48),
              )
            : Image.memory(
                bytes,
                fit: BoxFit.contain,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) =>
                    const Center(child: Icon(Icons.auto_stories_outlined)),
              ),
      ),
    );
    final caption = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.episodeTitle ?? item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (item.description.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(item.description, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ],
    );
    return InkWell(
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 600 &&
              MediaQuery.textScalerOf(context).scale(14) < 21) {
            return Row(
              children: [
                Expanded(flex: 3, child: artwork),
                const SizedBox(width: 28),
                Expanded(flex: 2, child: caption),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [artwork, const SizedBox(height: 16), caption],
          );
        },
      ),
    );
  }
}
