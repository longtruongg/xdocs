import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xdocs/service/service.dart';

import '../models/book.dart';

/// Pack this many `\n` lines into one [Text] when the body has no `\n\n`.
const int _kLinesPerChunk = 6;

/// Reading mode: loads chapter body after the route animation so the
/// push transition stays smooth (no main-thread gunzip mid-slide).
class ChapterReaderScreen extends ConsumerStatefulWidget {
  const ChapterReaderScreen({
    super.key,
    required this.book,
    required this.chapter,
    // required this.chapterNumber,
    this.chapters = const <Chapter>[],
  });

  final Book book;
  final Chapter chapter;

  /// Backend chapter `index` (1-based) to open first.
  // final int chapterNumber;

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
  ConsumerState<ChapterReaderScreen> createState() => _ChapterReaderScreenState();
}

final lastChapterProvider = FutureProvider.family<int?, String>((ref, bookId) {
  return ChapterReaderScreen.loadLastChapter(bookId);
});

class _ChapterReaderScreenState extends ConsumerState<ChapterReaderScreen> {
  late int _currentIndex;
  final _scrollController = ScrollController();

  /// False until the incoming route animation finishes (or a short fallback).
  bool _loadContent = false;

  bool _armedTransitionWait = false;

  /// Translated chapters only — built once, not in [build].
  late List<Chapter> _nav;
  int _navPos = -1;

  /// Paragraph / line-chunk widgets for the current body.
  List<String> _paragraphs = const [];
  int? _paragraphsForIndex;
  String? _paragraphsSource;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.chapter.index;
    _rebuildNav();
    // Don't hit disk during the push animation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ChapterReaderScreen.saveLastChapter(widget.book.id, _currentIndex);
    });
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
    Future<void>.delayed(const Duration(milliseconds: 450), () {
      if (mounted && !_loadContent) setState(() => _loadContent = true);
    });
  }

  void _rebuildNav() {
    final full = widget.chapters.isNotEmpty ? widget.chapters : <Chapter>[widget.chapter];
    final done = full.where((c) => c.isDone).toList(growable: false);
    _nav = done.isNotEmpty ? done : full;
    _navPos = _nav.indexWhere((c) => c.index == _currentIndex);
  }

  Chapter get _meta {
    if (_navPos >= 0) return _nav[_navPos];
    if (widget.chapter.index == _currentIndex) return widget.chapter;
    return Chapter(index: _currentIndex, titleZh: 'Chương $_currentIndex');
  }

  void _ensureParagraphs(int chapterIndex, String body) {
    if (_paragraphsForIndex == chapterIndex && identical(_paragraphsSource, body)) {
      return;
    }
    _paragraphsForIndex = chapterIndex;
    _paragraphsSource = body;
    _paragraphs = _splitChapterBody(body);
  }

  void _goTo(int index) {
    if (index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
      _navPos = _nav.indexWhere((c) => c.index == index);
      _paragraphs = const [];
      _paragraphsForIndex = null;
      _paragraphsSource = null;
    });
    ChapterReaderScreen.saveLastChapter(widget.book.id, index);
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  void _goPrev() {
    if (_navPos > 0) _goTo(_nav[_navPos - 1].index);
  }

  void _goNext() {
    if (_navPos >= 0 && _navPos < _nav.length - 1) {
      _goTo(_nav[_navPos + 1].index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final meta = _meta;
    final hasPrev = _navPos > 0;
    final hasNext = _navPos >= 0 && _navPos < _nav.length - 1;

    final args = ChapterDetailArgs(bookId: widget.book.id, index: _currentIndex);

    // Only subscribe after transition so SQLite + gunzip don't freeze the slide.
    final AsyncValue<Chapter> detailAsync = _loadContent
        ? ref.watch(chapterDetailProvider(args))
        : const AsyncLoading();

    return Scaffold(
      appBar: AppBar(
        title: Text('Chương $_currentIndex', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Tải lại',
            onPressed: !_loadContent ? null : () => ref.invalidate(chapterDetailProvider(args)),
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
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
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
          final title = detail.displayTitle.isNotEmpty ? detail.displayTitle : meta.displayTitle;
          final body = detail.hasContent
              ? detail.contentVi
              : 'Chưa có nội dung cho chương này '
                    '(status: ${detail.status.isEmpty ? meta.status : detail.status}).';
          _ensureParagraphs(_currentIndex, body);
          final bodyStyle = theme.textTheme.bodyLarge?.copyWith(height: 1.65, color: scheme.onSurface);

          return ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            itemCount: _paragraphs.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(widget.book.title, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.primary)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (detail.status.isNotEmpty)
                            Text(
                              'status: ${detail.status}',
                              style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          if (detail.hasContent) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.offline_pin, size: 16, color: scheme.primary),
                            const SizedBox(width: 4),
                            Text('đã lưu máy', style: theme.textTheme.labelMedium?.copyWith(color: scheme.primary)),
                          ],
                        ],
                      ),
                    ],
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(_paragraphs[index - 1], style: bodyStyle),
              );
            },
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
                    onPressed: hasPrev ? _goPrev : null,
                    icon: const Icon(Icons.chevron_left),
                    label: const Text('Trước'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    _navPos >= 0 ? '${_navPos + 1}/${_nav.length}' : 'Ch. $_currentIndex',
                    style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: hasNext ? _goNext : null,
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

/// Prefer blank-line paragraphs. If the body is only single `\n`s, pack
/// [_kLinesPerChunk] lines per widget so the list isn't 500 one-liners.
List<String> _splitChapterBody(String body) {
  final normalized = body.replaceAll('\r\n', '\n');
  if (normalized.isEmpty) return const [''];

  if (normalized.contains('\n\n')) {
    final parts = <String>[];
    for (final chunk in normalized.split(RegExp(r'\n{2,}'))) {
      final trimmed = chunk.trim();
      if (trimmed.isNotEmpty) parts.add(trimmed);
    }
    if (parts.isNotEmpty) return parts;
  }

  final lines = normalized.split('\n');
  if (lines.length == 1) return lines;

  final chunks = <String>[];
  final buf = StringBuffer();
  var packed = 0;
  for (final line in lines) {
    if (packed > 0) buf.writeln();
    buf.write(line);
    packed++;
    if (packed >= _kLinesPerChunk) {
      chunks.add(buf.toString());
      buf.clear();
      packed = 0;
    }
  }
  if (packed > 0) chunks.add(buf.toString());
  return chunks;
}
