import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xdocs/models/book.dart';

import '../service/service.dart';
import 'chapter_reader_screen.dart';

class ChaptersIndex extends ConsumerWidget {
  const ChaptersIndex({
    super.key,
    required this.book,
    required this.allChapters,
    required this.chapter,
    required this.isOffline,
  });

  final Book book;
  final List<Chapter> allChapters;
  final Chapter chapter;
  final bool isOffline;

  Future<void> _openReader(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChapterReaderScreen(
          book: book,
          chapter: chapter,
          chapterNumber: chapter.index,
          chapters: allChapters,
        ),
      ),
    );
    ref.invalidate(lastChapterProvider(book.id));
    if (!isOffline) {
      ref.invalidate(cachedChapterIndexesProvider(book.id));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = isOffline
        ? 'offline'
        : (chapter.status.isEmpty ? 'need download' : chapter.status);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openReader(context, ref),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text(
                    '${chapter.index}',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chapter.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isOffline
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  isOffline ? Icons.offline_pin : Icons.chevron_right_outlined,
                  size: 20,
                  color: isOffline ? scheme.primary : scheme.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
