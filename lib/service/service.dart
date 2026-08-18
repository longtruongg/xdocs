import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:xdocs/data/data_hook.dart';
import 'package:xdocs/models/book.dart';
import 'package:xdocs/service/local_service.dart';

/// Your PC LAN IP (same Wi‑Fi as the phone).
/// Not the gateway (192.168.100.1) and not the public WAN IP.
const String kLanHost = '192.168.100.63';
const int kApiPort = 8080;

/// Go :8080 is plain HTTP — must stay false or mobile fetch fails → empty cache.
const bool kApiUseHttps = false;

/// Backend max page size for chapter list.
const int kChapterFetchLimit = 200;

/// Parallel detail downloads for offline pack.
const int kOfflineDownloadConcurrency = 4;

/// How many chapter bodies to accumulate before one SQLite transaction flush.
const int kOfflineSaveBatchSize = 8;

String resolveApiBaseUrl() {
  final scheme = kApiUseHttps ? 'https' : 'http';
  if (kIsWeb) return '$scheme://127.0.0.1:$kApiPort';
  // Phone on same Wi‑Fi. Android emulator: set kLanHost to 10.0.2.2
  if (Platform.isAndroid || Platform.isIOS) {
    return '$scheme://$kLanHost:$kApiPort';
  }
  return '$scheme://127.0.0.1:$kApiPort';
}

/// Turn backend `cover_url` into something [Image.network] can load.
/// Absolute http(s) kept as-is; paths like `/covers/x.jpg` join API base.
String resolveCoverUrl(String? coverUrl) {
  final raw = coverUrl?.trim() ?? '';
  if (raw.isEmpty) return '';
  final lower = raw.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    return raw;
  }
  final base = resolveApiBaseUrl();
  if (raw.startsWith('/')) return '$base$raw';
  return '$base/$raw';
}

final bookProvider = AsyncNotifierProvider<BookNotifierService, List<Book>>(() {
  return BookNotifierService();
});

/// Chapter list when a book is opened; cache-first like Google Books.
final chaptersProvider = AsyncNotifierProvider.autoDispose.family<ChaptersNotifier, List<Chapter>, String>(
  ChaptersNotifier.new,
);

class ChaptersNotifier extends AsyncNotifier<List<Chapter>> {
  ChaptersNotifier(this.bookId);

  final String bookId;

  @override
  Future<List<Chapter>> build() async {
    final db = DataHook.instance;
    final cached = await db.getChapters(bookId);

    if (cached.isNotEmpty) {
      // After route animation (~300ms) so push/pop doesn't freeze.
      unawaited(_softRefresh());
      return cached;
    }

    final remote = await BookApi.fetchAllChapters(bookId);
    await db.saveChapterList(bookId, remote);
    return remote;
  }

  Future<void> _softRefresh() async {
    // Let MaterialPageRoute transition finish before network + bulk write.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!ref.mounted) return;
    try {
      final remote = await BookApi.fetchAllChapters(bookId);
      await DataHook.instance.saveChapterList(bookId, remote);
      if (!ref.mounted) return;
      final current = state.asData?.value;
      if (current != null && _chapterMetaEqual(current, remote)) return;
      state = AsyncData(remote);
    } catch (_) {
      // Keep showing cache.
    }
  }
}

bool _chapterMetaEqual(List<Chapter> a, List<Chapter> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i];
    final y = b[i];
    if (x.index != y.index || x.status != y.status || x.titleZh != y.titleZh || x.titleVi != y.titleVi) {
      return false;
    }
  }
  return true;
}

/// Indexes already stored offline (with content BLOB) for a book.
final cachedChapterIndexesProvider = FutureProvider.autoDispose.family<Set<int>, String>((ref, bookId) {
  return DataHook.instance.cachedContentIndexes(bookId);
});

/// Args for [chapterDetailProvider]:
/// `GET /wm/books/{bookId}/chapters/{index}`
@immutable
class ChapterDetailArgs {
  const ChapterDetailArgs({required this.bookId, required this.index});

  final String bookId;
  final int index;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ChapterDetailArgs && bookId == other.bookId && index == other.index;

  @override
  int get hashCode => Object.hash(bookId, index);
}

/// Loads full chapter body (DB first → network → save BLOB).
final chapterDetailProvider = FutureProvider.autoDispose.family<Chapter, ChapterDetailArgs>((ref, args) {
  return loadChapterDetail(args.bookId, args.index);
});

/// One-shot load (offline pack etc.): local metadata first, else network.
Future<List<Chapter>> loadChapters(String bookId) async {
  final db = DataHook.instance;
  final cached = await db.getChapters(bookId);
  if (cached.isNotEmpty) return cached;

  final remote = await BookApi.fetchAllChapters(bookId);
  await db.saveChapterList(bookId, remote);
  return remote;
}

/// Offline-first chapter body:
/// 1) local gzip BLOB if present
/// 2) else network detail, then save BLOB
Future<Chapter> loadChapterDetail(String bookId, int index) async {
  final db = DataHook.instance;
  final cached = await db.getChapter(bookId, index);
  if (cached != null && cached.hasContent) {
    return cached;
  }

  try {
    final remote = await BookApi.fetchChapterDetail(bookId, index);
    await db.saveChapterDetail(bookId, remote);
    return remote;
  } catch (e) {
    if (cached != null) return cached;
    rethrow;
  }
}

/// Download **translated** chapter bodies (`status == done`) into SQLite.
///
/// Skips indexes already cached. Does **not** pull untranslated chapters.
/// [onProgress] gets (done, total) for the translated set only.
///
/// Bodies are flushed in batches ([kOfflineSaveBatchSize]) per transaction.
Future<OfflineDownloadResult> downloadTranslatedOffline(
  String bookId, {
  List<Chapter>? chapters,
  void Function(int done, int total)? onProgress,
  bool Function()? isCancelled,
}) async {
  final db = DataHook.instance;
  final list = chapters ?? await loadChapters(bookId);

  // Only chapters already translated on the back-end.
  final translated = list.where((c) => c.isDone && c.index > 0).toList();
  final translatedIndexes = translated.map((c) => c.index).toSet();

  final alreadyAll = await db.cachedContentIndexes(bookId);
  final already = alreadyAll.intersection(translatedIndexes);

  final todo = translated.where((c) => !already.contains(c.index)).map((c) => c.index).toList(growable: false);

  final total = translated.length; // e.g. ~450 done, not 1541
  var progressDone = already.length;
  onProgress?.call(progressDone, total == 0 ? 1 : total);

  var saved = 0;
  var failed = 0;

  var cursor = 0;
  final pending = <Chapter>[];
  // Serialize flushes so concurrent workers don't double-clear the buffer.
  Future<void> writeChain = Future.value();

  Future<void> flushPending() {
    writeChain = writeChain.then((_) async {
      if (pending.isEmpty) return;
      final chunk = List<Chapter>.from(pending);
      pending.clear();
      await db.saveChapterDetails(bookId, chunk);
      saved += chunk.where((c) => c.hasContent).length;
    });
    return writeChain;
  }

  Future<void> worker() async {
    while (true) {
      if (isCancelled?.call() == true) return;
      final i = cursor;
      if (i >= todo.length) return;
      cursor = i + 1;
      final index = todo[i];
      try {
        final detail = await BookApi.fetchChapterDetail(bookId, index);
        if (detail.hasContent) {
          pending.add(detail);
          if (pending.length >= kOfflineSaveBatchSize) {
            await flushPending();
          }
        } else {
          failed++;
        }
      } catch (_) {
        failed++;
      } finally {
        progressDone++;
        onProgress?.call(progressDone, total == 0 ? 1 : total);
      }
    }
  }

  final workers = List.generate(kOfflineDownloadConcurrency, (_) => worker());
  await Future.wait(workers);
  await flushPending();

  return OfflineDownloadResult(
    translatedTotal: translated.length,
    alreadyCached: already.length,
    newlySaved: saved,
    failed: failed,
    cancelled: isCancelled?.call() == true,
  );
}

class OfflineDownloadResult {
  const OfflineDownloadResult({
    required this.translatedTotal,
    required this.alreadyCached,
    required this.newlySaved,
    required this.failed,
    this.cancelled = false,
  });

  /// How many chapters have status=done on the server.
  final int translatedTotal;
  final int alreadyCached;
  final int newlySaved;
  final int failed;
  final bool cancelled;

  int get totalReady => alreadyCached + newlySaved;
}

class BookNotifierService extends AsyncNotifier<List<Book>> {
  BookLocalStorage get _local => ref.read(bookLocalStorage);

  @override
  FutureOr<List<Book>> build() => fetchBooks();

  /// Offline-first shelf:
  /// 1) SQLite immediately (if any rows)
  /// 2) background network soft-refresh
  /// Empty DB → network, then save.
  ///
  /// Payload: `[{ id, title_zh, author, cover_url, total_chapters }, …]`
  Future<List<Book>> fetchBooks() async {
    final cached = await _local.fetchBookLocal();
    if (cached.isNotEmpty) {
      unawaited(_softRefresh());
      return cached;
    }

    try {
      return await _fetchRemoteAndSave();
    } catch (e, st) {
      // ignore: avoid_print
      print('fetchBooks failed (${resolveApiBaseUrl()}/wm/books): $e\n$st');
      rethrow;
    }
  }

  Future<List<Book>> _fetchRemoteAndSave() async {
    final remote = await BookApi.fetchBooks();
    await _local.saveBooks(remote);
    return remote;
  }

  /// Quiet network update after showing cache (same idea as chapters).
  Future<void> _softRefresh() async {
    try {
      final remote = await _fetchRemoteAndSave();
      if (!ref.mounted) return;
      final current = state.asData?.value;
      if (current != null && _booksEqual(current, remote)) return;
      state = AsyncData(remote);
    } catch (_) {
      // Keep showing SQLite cache.
    }
  }

  /// Pull-to-refresh: always hit network, keep list visible (no blank loading).
  Future<void> refresh() async {
    try {
      final remote = await _fetchRemoteAndSave();
      if (!ref.mounted) return;
      state = AsyncData(remote);
    } catch (e, st) {
      // ignore: avoid_print
      print('refresh books failed: $e\n$st');
      if (!ref.mounted) return;
      final current = state.asData?.value;
      if (current != null && current.isNotEmpty) {
        // Stay on cache; RefreshIndicator still completes.
        return;
      }
      final cached = await _local.fetchBookLocal();
      if (cached.isNotEmpty) {
        state = AsyncData(cached);
        return;
      }
      state = AsyncError(e, st);
    }
  }
}

bool _booksEqual(List<Book> a, List<Book> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i];
    final y = b[i];
    if (x.id != y.id ||
        x.titleZh != y.titleZh ||
        x.author != y.author ||
        x.coverUrl != y.coverUrl ||
        x.totalChapters != y.totalChapters) {
      return false;
    }
  }
  return true;
}

/// Thin HTTP client for Go `/wm/*` routes.
class BookApi {
  /// `GET /wm/books` →
  /// `[{ "id", "title_zh", "author", "cover_url", "total_chapters" }, …]`
  static Future<List<Book>> fetchBooks() async {
    final uri = Uri.parse('${resolveApiBaseUrl()}/wm/books');
    final response = await _get(uri);
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    // ignore: avoid_print
    print('from backend $uri → $decoded');
    if (decoded is! List) {
      throw Exception('Expected a JSON list from /wm/books');
    }
    final books = decoded.map(_bookMap).map(Book.fromJson).toList(growable: false);
    // ignore: avoid_print
    print('parsed books: ${books.map((b) => '${b.titleZh}|author=${b.author}|cover=${b.coverUrl}').join('; ')}');
    return books;
  }

  static Map<String, dynamic> _bookMap(dynamic item) {
    if (item is Map<String, dynamic>) return item;
    if (item is Map) return Map<String, dynamic>.from(item);
    throw Exception('Expected book object in /wm/books list, got $item');
  }

  static Future<ChapterPage> fetchChapterPage(String bookId, {int offset = 0, int limit = kChapterFetchLimit}) async {
    final uri = Uri.parse(
      '${resolveApiBaseUrl()}/wm/books/$bookId/chapters',
    ).replace(queryParameters: {'offset': '$offset', 'limit': '$limit'});

    final response = await _get(uri);
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Expected object from /wm/books/:id/chapters');
    }
    return ChapterPage.fromJson(decoded);
  }

  static Future<List<Chapter>> fetchAllChapters(String bookId) async {
    final all = <Chapter>[];
    var offset = 0;

    while (true) {
      final page = await fetchChapterPage(bookId, offset: offset, limit: kChapterFetchLimit);
      if (page.chapters.isEmpty) break;
      all.addAll(page.chapters);
      if (page.chapters.length < kChapterFetchLimit) break;
      offset += kChapterFetchLimit;
    }

    return List<Chapter>.unmodifiable(all);
  }

  /// `GET /wm/books/:id/chapters/:index`
  static Future<Chapter> fetchChapterDetail(String bookId, int index) async {
    final uri = Uri.parse('${resolveApiBaseUrl()}/wm/books/$bookId/chapters/$index');
    final response = await _get(uri, acceptAccepted: true);

    if (response.statusCode == 202) {
      throw Exception('Chapter $index is still translating');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Expected chapter detail object');
    }
    return Chapter.fromJson(decoded);
  }

  static Future<http.Response> _get(Uri uri, {bool acceptAccepted = false}) async {
    late final http.Response response;
    try {
      response = await http.get(uri).timeout(const Duration(seconds: 8));
    } on TimeoutException {
      throw Exception(
        'Timeout calling $uri\n'
        'Phone must reach your PC (kLanHost=$kLanHost, port $kApiPort).',
      );
    } on SocketException catch (e) {
      throw Exception('Cannot reach $uri ($e)');
    }

    final ok = response.statusCode == 200 || (acceptAccepted && response.statusCode == 202);
    if (!ok) {
      throw Exception('HTTP ${response.statusCode} $uri: ${response.body}');
    }
    return response;
  }

  static Future<Uint8List> saveRawCoverBook(String urlPath) async {
    late final http.Response resp;
    try {
      resp = await http.get(urlPath as Uri).timeout(const Duration(seconds: 8));
    } on TimeoutException {
      throw Exception(
        'Timeout calling \n'
        'Phone must reach your PC (kLanHost=$kLanHost, port $kApiPort).',
      );
    } on SocketException catch (e) {
      throw Exception('Cannot reach  ($e)');
    }
    final ok = resp.statusCode == 200 || resp.statusCode == 202;
    if (!ok) {
      throw Exception('HTTP ${resp.statusCode}  ${resp.body}');
    }
    Uint8List encode = utf8.encode(resp.body);
    return encode;
  }
}
