import 'package:flutter/material.dart';
import 'package:koofy_reader/features/library/domain/book.dart';

class BookTile extends StatelessWidget {
  const BookTile({
    super.key,
    required this.book,
    required this.progressRatio,
    required this.onTap,
  });

  final Book book;
  final double progressRatio;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final percent = (progressRatio * 100).round();

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.all(16),
        title: Text(book.title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${book.author} · $percent% 읽음'),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: progressRatio.clamp(0.0, 1.0)),
              const SizedBox(height: 8),
              Text(book.description),
            ],
          ),
        ),
      ),
    );
  }
}
