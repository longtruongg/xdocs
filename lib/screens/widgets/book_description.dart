import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xdocs/models/book.dart';

import '../book_list_screen.dart';
import '../chapter_reader_screen.dart';

class BookDescription extends ConsumerWidget {
  final Book book;

  const BookDescription({super.key, required this.book});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lastChapter = ref
        .watch(lastChapterProvider(book.id))
        .maybeWhen(data: (val) => (val != null && val > 0) ? '$val' : '-', orElse: () => '-');
    final author = book.author.trim();
    final intro = book.intro.trim();
    final metaStyle = theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant);
    final rows = <({String label, String value})>[
      (label: 'Tên truyện', value: book.title),
      (label: 'Tác giả', value: author.isEmpty ? '—' : author),
      (label: 'Danh sách chương', value: '${book.totalChapters}'),
      (label: 'Chương vừa đọc', value: lastChapter),
    ];

    const coverHeight = 150.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BookCover(book: book, height: coverHeight),
              const SizedBox(width: 16),
              Expanded(
                child: SizedBox(
                  height: coverHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final item in rows)
                        Text(
                          '${item.label}: ${item.value}',
                          style: metaStyle,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Giới thiệu', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            intro.isEmpty ? 'Chưa có giới thiệu.' : intro,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12, child: Divider(height: 1)),
        ],
      ),
    );
  }
}
