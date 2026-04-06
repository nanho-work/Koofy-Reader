import 'package:flutter/material.dart';

class ReaderView extends StatelessWidget {
  const ReaderView({
    super.key,
    required this.scrollController,
    required this.content,
  });

  final ScrollController scrollController;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: scrollController,
      child: SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: SelectableText(
          content,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(height: 1.75, fontSize: 17),
        ),
      ),
    );
  }
}
