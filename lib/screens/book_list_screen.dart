import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xdocs/drawers/app_drawer.dart';
import 'package:xdocs/service/service.dart';

import '../models/book.dart';
import 'book_detail_screen.dart';

// Cover images use [resolveCoverUrl] so relative backend paths still load.

class BookListScreen extends ConsumerWidget {
  const BookListScreen({super.key});

  Future<void> _onRefresh(WidgetRef ref) {
    return ref.read(bookProvider.notifier).refresh();
  }

  void _openBook(BuildContext context, Book book) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (context, animation, secondaryAnimation) =>
            BookDetailScreen(book: book),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(opacity: curvedAnimation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bookAsync = ref.watch(bookProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('X-Docs'), centerTitle: false),
      body: bookAsync.when(
        data: (books) {
          // AlwaysScrollable so pull-to-refresh works on empty / short lists.
          return RefreshIndicator(
            onRefresh: () => _onRefresh(ref),
            child: books.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      Center(
                        child: Text('Chưa có truyện nào. Kéo xuống để tải.'),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: books.length,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final book = books[index];
                      return _BookCard(
                        book: book,
                        onTap: () => _openBook(context, book),
                      );
                    },
                  ),
          );
        },
        error: (err, stack) => RefreshIndicator(
          onRefresh: () => _onRefresh(ref),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 80),
              Text('Error: $err', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Center(
                child: FilledButton(
                  onPressed: () => _onRefresh(ref),
                  child: const Text('Thử lại'),
                ),
              ),
            ],
          ),
        ),
        // Only first open with empty SQLite shows spinner; cache hits skip this.
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
      backgroundColor: theme.colorScheme.surface,
      drawer: AppDrawer(),
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({required this.book, required this.onTap});

  final Book book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return RepaintBoundary(
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              // mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _CoverThumb(book: book, width: 72, height: 100),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      // Backend field: author
                      const SizedBox(height: 4),
                      Text(
                        book.author.trim().isEmpty ? '—' : book.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (book.intro.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          book.intro.replaceAll('\n', ' '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.menu_book_outlined,
                            size: 14,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${book.totalChapters} chương',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 18),
                Container(
                  height: 100,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: scheme.outline,
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

class _CoverThumb extends StatelessWidget {
  const _CoverThumb({
    required this.book,
    required this.width,
    required this.height,
  });

  final Book book;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(8);
    final cover = resolveCoverUrl(
      book.coverUrl,
      // "https://img22.ixdzs.com/96/96/96960e9fa88b658cad4e65e283fa4163.jpg",
    );

    return Hero(
      tag: "book_cover ${book.id}",
      child: ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          width: width,
          height: height,
          child: cover.isNotEmpty
              ? Image.network(
                  cover,
                  width: width,
                  height: height,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                  // Some CDNs reject empty / Dart default UA.
                  headers: const {
                    'User-Agent':
                        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
                        '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
                    'Accept':
                        'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
                  },
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return _CoverPlaceholder(
                      width: width,
                      height: height,
                      colors: _coverColors(book.coverColor),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: progress.expectedTotalBytes != null
                              ? progress.cumulativeBytesLoaded /
                                    progress.expectedTotalBytes!
                              : null,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    // ignore: avoid_print
                    print('cover load failed url=$cover error=$error');
                    return _CoverPlaceholder(
                      width: width,
                      height: height,
                      colors: _coverColors(book.coverColor),
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: scheme.onSurfaceVariant,
                      ),
                    );
                  },
                )
              : _CoverPlaceholder(
                  width: width,
                  height: height,
                  colors: _coverColors(book.coverColor),
                  child: Icon(
                    Icons.menu_book_rounded,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
        ),
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({
    required this.width,
    required this.height,
    required this.child,
    this.colors,
  });

  final double width;
  final double height;
  final Widget child;
  final List<Color>? colors;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: colors != null
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors!,
              )
            : null,
        color: colors == null ? scheme.surfaceContainerHighest : null,
      ),
      child: child,
    );
  }
}

List<Color> _coverColors(ColorSeed seed) {
  switch (seed) {
    case ColorSeed.indigo:
      return [const Color(0xFF3949AB), const Color(0xFF1A237E)];
    case ColorSeed.teal:
      return [const Color(0xFF00897B), const Color(0xFF004D40)];
    case ColorSeed.deepOrange:
      return [const Color(0xFFF4511E), const Color(0xFFBF360C)];
    case ColorSeed.purple:
      return [const Color(0xFF8E24AA), const Color(0xFF4A148C)];
    case ColorSeed.blueGrey:
      return [const Color(0xFF546E7A), const Color(0xFF263238)];
    case ColorSeed.brown:
      return [const Color(0xFF6D4C41), const Color(0xFF3E2723)];
  }
}

/// Shared cover widget used from detail screen too.
class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    required this.book,
    this.width = 110,
    this.height = 150,
  });

  final Book book;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return _CoverThumb(book: book, width: width, height: height);
  }
}
