import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xdocs/service/service.dart';

import '../models/book.dart';
import 'book_list_screen.dart';
import 'chapter_reader_screen.dart';

/// How many chapters per range tab (e.g. 1-50, 51-100, …).
/// Larger pages = fewer chips = smoother open animation on big books.
const int kChapterPageSize = 50;

class BookDetailScreen extends ConsumerStatefulWidget {
  const BookDetailScreen({super.key, required this.book});

  final Book book;

  @override
  ConsumerState<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends ConsumerState<BookDetailScreen> {
  final ValueNotifier<int> _rangeIndex = ValueNotifier<int>(0);
  bool _downloading = false;

  /// Last chapter index the user opened (0 = none yet).
  int _lastChapter = 0;
  Book get book => widget.book;

  @override
  void initState() {
    super.initState();
    _loadLastChapter();
  }

  @override
  void dispose() {
    _rangeIndex.dispose();
    super.dispose();
  }

  Future<void> _loadLastChapter() async {
    final index = await ChapterReaderScreen.loadLastChapter(book.id);
    if (!mounted || index == null || index <= 0) return;
    setState(() => _lastChapter = index);
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

  Future<void> _downloadTranslatedOffline(List<Chapter> chapters) async {
    if (_downloading) return;

    final translatedCount = chapters.where((c) => c.isDone).length;
    if (translatedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có chương nào status=done để tải.')),
      );
      return;
    }

    setState(() => _downloading = true);

    final progress = ValueNotifier<({int done, int total})>((
      done: 0,
      total: translatedCount,
    ));

    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Tải offline (đã dịch)'),
            content: ValueListenableBuilder<({int done, int total})>(
              valueListenable: progress,
              builder: (_, value, _) {
                final t = value.total <= 0 ? 1 : value.total;
                final ratio = (value.done / t).clamp(0.0, 1.0);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Chỉ tải chương đã dịch (status=done).\n'
                      '${value.done}/$t',
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(value: ratio),
                    const SizedBox(height: 8),
                    Text(
                      'Nội dung lưu gzip BLOB trên máy — đọc offline sau.',
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
        onProgress: (d, t) {
          progress.value = (done: d, total: t);
        },
      );

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      ref.invalidate(cachedChapterIndexesProvider(book.id));

      final msg = result.failed == 0
          ? 'Offline OK: ${result.totalReady}/${result.translatedTotal} '
                'chương đã dịch (mới ${result.newlySaved}, có sẵn ${result.alreadyCached}).'
          : 'Lưu ${result.totalReady}/${result.translatedTotal}, lỗi ${result.failed}.';

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Tải offline thất bại: $e')));
      }
    } finally {
      progress.dispose();
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chaptersAsync = ref.watch(chaptersProvider(book.id));
    final cachedAsync = ref.watch(cachedChapterIndexesProvider(book.id));
    final cached = cachedAsync.asData?.value ?? const <int>{};

    return Scaffold(
      appBar: AppBar(
        title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          chaptersAsync.maybeWhen(
            data: (chs) {
              final n = chs.where((c) => c.isDone).length;
              return IconButton(
                tooltip: 'Tải $n chương đã dịch (offline)',
                onPressed: _downloading || n == 0
                    ? null
                    : () => _downloadTranslatedOffline(chs),
                icon: _downloading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_for_offline_outlined),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BookCover(book: book),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          book.title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          book.author.trim().isEmpty ? '—' : book.author,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${book.totalChapters} chương',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (cached.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Offline: ${cached.length} chương đã lưu',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Giới thiệu',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    book.intro.trim().isEmpty
                        ? 'Chưa có giới thiệu.'
                        : book.intro,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.45,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(label: 'Tên truyện', value: book.title),
                  const SizedBox(height: 4),
                  _InfoRow(
                    label: 'Tác giả',
                    value: book.author.trim().isEmpty ? '—' : book.author,
                  ),
                  const SizedBox(height: 4),
                  _InfoRow(label: 'Số chương', value: '${book.totalChapters}'),
                  const SizedBox(height: 4),
                  _InfoRow(
                    label: 'Chương vừa đọc',
                    value: _lastChapter > 0 ? '$_lastChapter' : '—',
                  ),
                  const SizedBox(height: 12),
                  chaptersAsync.maybeWhen(
                    data: (chs) {
                      final translated = chs.where((c) => c.isDone).length;
                      return FilledButton.tonalIcon(
                        onPressed: _downloading || translated == 0
                            ? null
                            : () => _downloadTranslatedOffline(chs),
                        icon: const Icon(Icons.download_for_offline_outlined),
                        label: Text(
                          translated == 0
                              ? 'Chưa có chương đã dịch'
                              : 'Tải $translated chương đã dịch (offline)',
                        ),
                      );
                    },
                    orElse: () => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
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

              return [
                ValueListenableBuilder<int>(
                  valueListenable: _rangeIndex,
                  builder: (context, rangeIndex, _) {
                    if (rangeIndex >= ranges && ranges > 0) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _rangeIndex.value = 0;
                      });
                    }
                    final chapters = _visibleChapters(allChapters, rangeIndex);

                    return SliverMainAxisGroup(
                      slivers: [
                        if (ranges > 1)
                          SliverToBoxAdapter(
                            child: SizedBox(
                              height: 44,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  8,
                                ),
                                itemCount: ranges,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, i) {
                                  return ChoiceChip(
                                    label: Text(_rangeLabel(i, total)),
                                    selected: i == rangeIndex,
                                    showCheckmark: false,
                                    onSelected: (_) {
                                      _rangeIndex.value = i;
                                    },
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
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
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
                                    if (chapter.status.isNotEmpty)
                                      chapter.status,
                                    if (isOffline) 'offline',
                                  ].join(' · '),
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
                                  if (mounted) {
                                    ref.invalidate(
                                      cachedChapterIndexesProvider(book.id),
                                    );
                                    // Refresh "Chương vừa đọc" after leaving reader.
                                    await _loadLastChapter();
                                  }
                                },
                              );
                            }, childCount: chapters.length),
                          ),
                        const SliverToBoxAdapter(child: SizedBox(height: 32)),
                      ],
                    );
                  },
                ),
              ];
            },
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            '$label:',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
