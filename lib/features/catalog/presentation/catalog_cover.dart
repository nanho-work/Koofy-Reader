import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/reader_catalog.dart';

class CatalogCover extends ConsumerWidget {
  const CatalogCover({super.key, required this.item, this.width = 56});
  final CatalogItem item;
  final double width;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(catalogCoverProvider(item)).valueOrNull;
    final fallback = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.auto_stories_outlined)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: width,
        height: width * 1.5,
        child: bytes == null
            ? fallback
            : Image.memory(
                bytes,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}
