import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:xdocs/screens/book_description.dart';
import 'package:xdocs/service/service.dart';

import '../models/book.dart';
import "chapter_reader_screen.dart";

// 'per range tab (e.g. 1-50, 51-100, …).
/// Larger pages = fewer chips = smoother open animation on big books.
const int kChapterPageSize = 30;

final chapterRageIndexProvider = StateProvider.family<int, String>(
  (ref, bookId) => 0,
);

final lastChapterProvider = FutureProvider.family<int?, String>((
  ref,
  bookId,
) async {
  return await ChapterReaderScreen.loadLastChapter(bookId);
});

final translatedCountProvider = Provider.family<int, String>((ref, bookId) {
  final chapterAsync = ref.watch(chaptersProvider(bookId));
  return chapterAsync.maybeWhen(
    data: (chap) => chap.where((c) => c.isDone).length,
    orElse: () => 0,
  );
});

class BookDetailScreen extends ConsumerStatefulWidget {
  const BookDetailScreen({super.key, required this.book});

  final Book book;

  @override
  ConsumerState<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends ConsumerState<BookDetailScreen> {
  final ValueNotifier<int> _rangeIndex = ValueNotifier<int>(0);

  Book get book => widget.book;

  @override
  void dispose() {
    _rangeIndex.dispose();
    super.dispose();
  }

  int _rangeCount(int total) {
    if (total == 0) return 0;
    return (total + kChapterPageSize - 1) ~/ kChapterPageSize;
  }

  List<Chapter> _visibleChapters(List<Chapter> all, int rangeIndex) {
    if (all.isEmpty) return const <Chapter>[];
    final start = rangeIndex * kChapterPageSize;
    if (start >= all.length) return const <Chapter>[];
    final end = (start + kChapterPageSize).clamp(0, all.length).toInt();
    return all.sublist(start, end);
  }

  String _rangeLabel(int index, int total) {
    final start = index * kChapterPageSize + 1;
    final endRaw = (index + 1) * kChapterPageSize;
    final end = endRaw > total ? total : endRaw;
    return '$start-$end';
  }

  Future<void> _downloadTranslatedOffline(
    BuildContext context,
    WidgetRef ref,
    List<Chapter> chapters,
  ) async {
    final translateCount = chapters.where((c) => c.isDone).length;
    if (translateCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có chương nào status=done để tải.')),
      );
      return;
    }
    final process = ValueNotifier<({int done, int total})>((
      done: 0,
      total: translateCount,
    ));
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text("Tải offline (đã dịch)"),
            content: ValueListenableBuilder<({int done, int total})>(
              valueListenable: process,
              builder: (_, val, _) {
                final t = val.total <= 0 ? 1 : val.total;
                final ratio = (val.done / t).clamp(0.0, 1.0);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Chỉ tải chương đã dịch (status=done).\n${val.done}/$t',
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(value: ratio),
                    const SizedBox(height: 8),
                    Text(
                      'Nội dung lưu trên máy — đọc offline sau.',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
    try {
      final result = await downloadTranslatedOffline(
        book.id,
        chapters: chapters,
        onProgress: (d, t) => process.value = (done: d, total: t),
      );
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      ref.invalidate(cachedChapterIndexesProvider(book.id));
      final msg = result.failed == 0
          ? 'Offline OK: ${result.totalReady}/${result.translatedTotal} chương đã dịch.'
          : 'Lưu ${result.totalReady}/${result.translatedTotal}, lỗi ${result.failed}.';
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Tải offline thất bại: $e')));
      }
    } finally {
      process.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final chaptersAsync = ref.watch(chaptersProvider(book.id));
    final cachedAsync = ref.watch(cachedChapterIndexesProvider(book.id));
    final cached = cachedAsync.asData?.value ?? const <int>{};
    final translateCount = ref.watch(translatedCountProvider(book.id));
    return Scaffold(
      appBar: AppBar(
        title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Tải $translateCount chương đã dịch (offline)',
            onPressed: translateCount == 0 || chaptersAsync.value == null
                ? null
                : () => _downloadTranslatedOffline(
                    context,
                    ref,
                    chaptersAsync.value!,
                  ),
            icon: const Icon(Icons.download_for_offline_outlined),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: BookDescription(book: book)),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 24),
              child: Divider(height: 1),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text(
                    'Danh sách chương',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  chaptersAsync.when(
                    data: (chs) => Text(
                      '${chs.length} chương',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    loading: () => Text(
                      'Đang tải…',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    error: (_, _) => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
          ...chaptersAsync.when(
            loading: () => [
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            ],
            error: (err, _) => [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Text(
                        'Không tải được chương:\n$err',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () =>
                            ref.invalidate(chaptersProvider(book.id)),
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            data: (allChapters) {
              final total = allChapters.length;
              final ranges = _rangeCount(total);
              final rangeIndexProvider = ref.watch(
                chapterRageIndexProvider(book.id),
              );
              final rangeIndex = rangeIndexProvider >= ranges
                  ? 0
                  : rangeIndexProvider;
              final chapters = _visibleChapters(allChapters, rangeIndex);
              return [
                SliverMainAxisGroup(
                  slivers: [
                    if (ranges > 1)
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: 44,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemCount: ranges,
                            itemBuilder: (context, i) {
                              return ChoiceChip(
                                label: Text(_rangeLabel(i, total)),
                                selected: i == rangeIndex,
                                showCheckmark: false,
                                onSelected: (_) =>
                                    ref
                                            .read(
                                              chapterRageIndexProvider(
                                                book.id,
                                              ).notifier,
                                            )
                                            .state =
                                        i,
                              );
                            },
                          ),
                        ),
                      ),
                    if (chapters.isEmpty)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Chưa có chương nào.'),
                        ),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final chapter = chapters[index];
                          final chapterNumber = chapter.index;
                          final isOffline = cached.contains(chapter.index);
                          return ListTile(
                            key: ValueKey(chapter.index),
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: scheme.primaryContainer,
                              foregroundColor: scheme.onPrimaryContainer,
                              child: Text(
                                '$chapterNumber',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            title: Text(
                              chapter.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              [
                                if (chapter.status.isNotEmpty) chapter.status,
                                if (isOffline) 'offline',
                              ].join(' . '),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isOffline
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isOffline)
                                  Icon(
                                    Icons.offline_pin,
                                    size: 18,
                                    color: scheme.primary,
                                  ),
                                Icon(
                                  Icons.chevron_right,
                                  color: scheme.outline,
                                ),
                              ],
                            ),
                            onTap: () async {
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
                              ref.invalidate(
                                cachedChapterIndexesProvider(book.id),
                              );
                              ref.invalidate(lastChapterProvider(book.id));
                            },
                          );
                        }, childCount: chapters.length),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 32)),
                  ],
                ),
              ];
            },
          ),
        ],
      ),
    );
  }
}
