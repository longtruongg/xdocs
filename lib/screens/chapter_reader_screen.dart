import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xdocs/service/service.dart';

import '../models/book.dart';

/// Reading mode: loads chapter body after the route animation so the
/// push transition stays smooth (no main-thread gunzip mid-slide).
class ChapterReaderScreen extends ConsumerStatefulWidget {
  const ChapterReaderScreen({
    super.key,
    required this.book,
    required this.chapter,
    required this.chapterNumber,
    this.chapters = const <Chapter>[],
  });

  final Book book;
  final Chapter chapter;

  /// Backend chapter `index` (1-based) to open first.
  final int chapterNumber;

  /// Full TOC for prev/next (usually all chapters from book detail).
  final List<Chapter> chapters;

  /// SharedPreferences key for last-read chapter (per book).
  static String lastChapterKey(String bookId) => 'last_chapter_$bookId';

  static Future<void> saveLastChapter(String bookId, int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(lastChapterKey(bookId), index);
  }

  static Future<int?> loadLastChapter(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(lastChapterKey(bookId));
  }

  @override
  ConsumerState<ChapterReaderScreen> createState() =>
      _ChapterReaderScreenState();
}

class _ChapterReaderScreenState extends ConsumerState<ChapterReaderScreen> {
  late int _currentIndex;
  final _scrollController = ScrollController();

  /// False until the incoming route animation finishes (or a short fallback).
  bool _loadContent = false;

  bool _armedTransitionWait = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.chapterNumber;
    // Persist as soon as the reader opens this chapter.
    ChapterReaderScreen.saveLastChapter(widget.book.id, _currentIndex);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadContent || _armedTransitionWait) return;
    _armedTransitionWait = true;

    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.status == AnimationStatus.completed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _loadContent = true);
      });
      return;
    }

    void listener(AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        animation.removeStatusListener(listener);
        if (mounted) setState(() => _loadContent = true);
      }
    }

    animation.addStatusListener(listener);
    // Safety net if the status listener is skipped (rare).
    Future<void>.delayed(const Duration(milliseconds: 450), () {
      if (mounted && !_loadContent) setState(() => _loadContent = true);
    });
  }

  /// Full TOC (for fallback metadata).
  List<Chapter> _fullToc(List<Chapter>? fromProvider) {
    if (widget.chapters.isNotEmpty) return widget.chapters;
    if (fromProvider != null && fromProvider.isNotEmpty) return fromProvider;
    return [widget.chapter];
  }

  /// Prev/Next only walks **translated** chapters (status=done), ~450 not 1541.
  List<Chapter> _navToc(List<Chapter> full) {
    final done = full.where((c) => c.isDone).toList(growable: false);
    if (done.isNotEmpty) return done;
    return full;
  }

  int _posInToc(List<Chapter> toc) {
    return toc.indexWhere((c) => c.index == _currentIndex);
  }

  Chapter _metaFor(List<Chapter> full, List<Chapter> nav) {
    for (final list in [nav, full]) {
      final i = _posInToc(list);
      if (i >= 0) return list[i];
    }
    if (widget.chapter.index == _currentIndex) return widget.chapter;
    return Chapter(index: _currentIndex, titleZh: 'Chương $_currentIndex');
  }

  void _goTo(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
    ChapterReaderScreen.saveLastChapter(widget.book.id, index);
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _goPrev(List<Chapter> nav) {
    final pos = _posInToc(nav);
    if (pos > 0) _goTo(nav[pos - 1].index);
  }

  void _goNext(List<Chapter> nav) {
    final pos = _posInToc(nav);
    if (pos >= 0 && pos < nav.length - 1) _goTo(nav[pos + 1].index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Prefer TOC passed from detail — do not re-watch chaptersProvider on open
    // (that was re-triggering soft-refresh + rebuild during the push animation).
    final full = _fullToc(null);
    final nav = _navToc(full);
    final pos = _posInToc(nav);
    final hasPrev = pos > 0;
    final hasNext = pos >= 0 && pos < nav.length - 1;
    final meta = _metaFor(full, nav);

    final args = ChapterDetailArgs(
      bookId: widget.book.id,
      index: _currentIndex,
    );

    // Only subscribe after transition so SQLite + gunzip don't freeze the slide.
    final AsyncValue<Chapter> detailAsync = _loadContent
        ? ref.watch(chapterDetailProvider(args))
        : const AsyncLoading();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Chương $_currentIndex',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Tải lại',
            onPressed: !_loadContent
                ? null
                : () => ref.invalidate(chapterDetailProvider(args)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: detailAsync.when(
        loading: () => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                meta.displayTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$err', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => ref.invalidate(chapterDetailProvider(args)),
                  child: const Text('Thử lại'),
                ),
              ],
            ),
          ),
        ),
        data: (detail) {
          final title = detail.displayTitle.isNotEmpty
              ? detail.displayTitle
              : meta.displayTitle;
          final body = detail.hasContent
              ? detail.contentVi
              : 'Chưa có nội dung cho chương này '
                    '(status: ${detail.status.isEmpty ? meta.status : detail.status}).';

          // SelectionArea + Text is much cheaper than SelectableText for long bodies.
          return SelectionArea(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.book.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (detail.status.isNotEmpty)
                      Text(
                        'status: ${detail.status}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    if (detail.hasContent) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.offline_pin, size: 16, color: scheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        'đã lưu máy',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  body,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    height: 1.65,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Material(
          elevation: 8,
          color: scheme.surfaceContainerHigh,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: hasPrev ? () => _goPrev(nav) : null,
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('Trước'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    pos >= 0
                        ? '${pos + 1}/${nav.length}'
                        : 'Ch. $_currentIndex',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: hasNext ? () => _goNext(nav) : null,
                    icon: const Icon(Icons.chevron_right),
                    label: const Text('Sau'),
                    iconAlignment: IconAlignment.end,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
