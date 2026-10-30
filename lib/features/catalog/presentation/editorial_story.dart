import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/reader_catalog.dart';

/// Reuses the catalog cover cache; art and text remain separately accessible.
class EditorialStory extends ConsumerWidget {
  const EditorialStory({
    super.key,
    required this.item,
    this.onTap,
    this.overlayTitle = false,
    this.overlayActions,
    this.eyebrow,
  });
  final String? eyebrow;
  final bool overlayTitle;
  final Widget? overlayActions;
  final CatalogItem item;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(catalogCoverProvider(item)).valueOrNull;
    if (overlayTitle) {
      return Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(),
          child: LayoutBuilder(
            builder: (context, constraints) => InkWell(
              onTap: onTap,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: constraints.maxWidth,
                  height:
                      (constraints.maxWidth *
                              (constraints.maxWidth < 480 ? .67 : .5))
                          .clamp(200, 360),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (bytes != null)
                        Image.memory(
                          bytes,
                          fit: BoxFit.cover,
                          excludeFromSemantics: true,
                          errorBuilder: (_, _, _) => const Center(
                            child: Icon(Icons.auto_stories_outlined),
                          ),
                        )
                      else
                        ColoredBox(
                          color: Theme.of(context).colorScheme.surfaceContainer,
                          child: const Icon(
                            Icons.auto_stories_outlined,
                            size: 48,
                          ),
                        ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xA6000000),
                              Colors.transparent,
                              Color(0x99000000),
                            ],
                            stops: [0, .4, 1],
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.topLeft,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (eyebrow != null) ...[
                                Text(
                                  eyebrow!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                              Text(
                                item.episodeTitle ?? item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (overlayActions != null)
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: TextButtonTheme(
                              data: TextButtonThemeData(
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  disabledForegroundColor: Colors.white54,
                                ),
                              ),
                              child: overlayActions!,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
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
