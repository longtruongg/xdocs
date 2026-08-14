import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xdocs/models/book.dart';
import 'package:xdocs/screens/book_detail_screen.dart';
import 'package:xdocs/service/service.dart';

import 'book_list_screen.dart';

class BookDescription extends ConsumerWidget {
  final Book book;

  const BookDescription({super.key, required this.book});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cachedAsync = ref.watch(cachedChapterIndexesProvider(book.id));
    final cached = cachedAsync.asData?.value ?? const <int>{};
    final lastChapterAsyn = ref.watch(lastChapterProvider(book.id));

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BookCover(book: book),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tên truyện: ${book.title}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w300,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tác giả:  ${book.author.trim().isEmpty ? '—' : book.author}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Hiện tại: ${book.totalChapters} chương',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (cached.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Offline: ${cached.length} chương dịch đã lưu',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      'Chương vừa đọc: ${lastChapterAsyn.maybeWhen(data: (val) => (val != null && val > 0) ? '$val' : '-', orElse: () => '-')}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                        fontStyle: FontStyle.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Text(
                'Giới thiệu',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                book.intro.trim().isEmpty ? 'Chưa có giới thiệu.' : book.intro,
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.45,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
