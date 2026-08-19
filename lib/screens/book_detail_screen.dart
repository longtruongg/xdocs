import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xdocs/screens/widgets/widgets.dart';
import 'package:xdocs/service/service.dart';

import '../models/book.dart';

final translatedCountProvider = Provider.family<int, String>((ref, bookId) {
  final chapterAsync = ref.watch(chaptersProvider(bookId));
  return chapterAsync.maybeWhen(data: (chap) => chap.where((c) => c.isDone).length, orElse: () => 0);
});

class BookDetailScreen extends ConsumerWidget {
  const BookDetailScreen({super.key, required this.book});

  final Book book;

  Future<void> _downloadTranslatedOffline(BuildContext context, WidgetRef ref, List<Chapter> chapters) async {
    final translateCount = chapters.where((c) => c.isDone).length;
    if (translateCount == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Chưa có chương nào status=done để tải.')));
      return;
    }
    final process = ValueNotifier<({int done, int total})>((done: 0, total: translateCount));
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
                    Text('Chỉ tải chương đã dịch (status=done).\n${val.done}/$t'),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(value: ratio),
                    const SizedBox(height: 8),
                    Text('Nội dung lưu trên máy — đọc offline sau.', style: Theme.of(ctx).textTheme.bodySmall),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tải offline thất bại: $e')));
      }
    } finally {
      process.dispose();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final chaptersAsync = ref.watch(chaptersProvider(book.id));
    final translateCount = ref.watch(translatedCountProvider(book.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Tải $translateCount chương đã dịch (offline)',
            onPressed: translateCount == 0 || chaptersAsync.value == null
                ? null
                : () => _downloadTranslatedOffline(context, ref, chaptersAsync.value!),
            icon: const Icon(Icons.download_for_offline_outlined),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: BookDescription(book: book)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text('Danh sách chương', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  chaptersAsync.when(
                    data: (chs) => Text(
                      '${chs.length} chương',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    loading: () =>
                        Text('Đang tải…', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
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
                      Text('Không tải được chương:\n$err', textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => ref.invalidate(chaptersProvider(book.id)),
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            data: (allChapters) => [
              ChapterRangeSlivers(book: book, allChapters: allChapters),
            ],
          ),
        ],
      ),
    );
  }
}
