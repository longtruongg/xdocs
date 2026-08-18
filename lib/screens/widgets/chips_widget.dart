import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:xdocs/models/book.dart';

import '../../service/service.dart';
import 'chapters_index.dart';

const int kChapterPageSize = 30;

final chapterRangeIndexProvider = StateProvider.family<int, String>((ref, bookId) => 0);

int rangeCount(int total) {
  if (total == 0) return 0;
  return (total + kChapterPageSize - 1) ~/ kChapterPageSize;
}

int clampRangeIndex(int raw, int total) {
  final ranges = rangeCount(total);
  if (ranges <= 0) return 0;
  return raw >= ranges ? 0 : raw;
}

List<Chapter> visibleChapters(List<Chapter> all, int rangeIndex) {
  if (all.isEmpty) return const <Chapter>[];
  final start = rangeIndex * kChapterPageSize;
  if (start >= all.length) return const <Chapter>[];
  final end = (start + kChapterPageSize).clamp(0, all.length).toInt();
  return all.sublist(start, end);
}

String rangeLabel(int index, int total) {
  final start = index * kChapterPageSize + 1;
  final endRaw = (index + 1) * kChapterPageSize;
  final end = endRaw > total ? total : endRaw;
  return '$start-$end';
}

class ChipsWidget extends ConsumerWidget {
  const ChipsWidget({super.key, required this.book, required this.total});

  final Book book;
  final int total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = clampRangeIndex(ref.watch(chapterRangeIndexProvider(book.id)), total);
    final ranges = rangeCount(total);

    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemCount: ranges,
        itemBuilder: (context, i) {
          return ChoiceChip(
            label: Text(rangeLabel(i, total)),
            selected: i == selected,
            showCheckmark: false,
            onSelected: (_) => ref.read(chapterRangeIndexProvider(book.id).notifier).state = i,
          );
        },
      ),
    );
  }
}

/// Chips + paged chapter list. Watches range so [BookDetailScreen] header stays put.
class ChapterRangeSlivers extends ConsumerWidget {
  const ChapterRangeSlivers({super.key, required this.book, required this.allChapters});

  final Book book;
  final List<Chapter> allChapters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = allChapters.length;
    final ranges = rangeCount(total);
    final rangeIndex = clampRangeIndex(ref.watch(chapterRangeIndexProvider(book.id)), total);
    final chapters = visibleChapters(allChapters, rangeIndex);
    final cached = ref.watch(cachedChapterIndexesProvider(book.id)).asData?.value ?? const <int>{};

    return SliverMainAxisGroup(
      slivers: [
        if (ranges > 1) SliverToBoxAdapter(child: ChipsWidget(book: book, total: total)),
        if (chapters.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(padding: EdgeInsets.all(24), child: Text('Chưa có chương nào.')),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final chapter = chapters[index];
              return ChaptersIndex(
                key: ValueKey(chapter.index),
                book: book,
                allChapters: allChapters,
                chapter: chapter,
                isOffline: cached.contains(chapter.index),
              );
            }, childCount: chapters.length),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}
