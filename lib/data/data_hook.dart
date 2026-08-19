import 'dart:typed_data';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:xdocs/models/book.dart';
/// Columns for list / metadata — never touch the heavy `content` BLOB.
const List<String> _chapterMetaColumns = [
  'book_id',
  'chapter_index',
  'title_zh',
  'title_vi',
  'status',
];

class DataHook {
  static final DataHook instance = DataHook._init();
  static Database? _database;

  DataHook._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('xdocs_store.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    final db = await openDatabase(
      path,
      version: 4,
      onConfigure: (db) async {
        // WAL returns a row ("wal") — must use rawQuery, not execute.
        // execute() treats that result as DatabaseException code 0 SQLITE_OK.
        await db.rawQuery('PRAGMA journal_mode = WAL');
        await db.execute('PRAGMA synchronous = NORMAL');
        await db.execute('PRAGMA temp_store = MEMORY');
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
    return db;
  }

  Future<void> _createDB(Database db, int version) async {
    // Mirrors GET /wm/books fields: id, title_zh, author, cover_url, total_chapters
    await db.execute('''
      CREATE TABLE books(
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        author TEXT NOT NULL DEFAULT '',
        cover_url TEXT NOT NULL DEFAULT '',
        total_chapters INTEGER NOT NULL DEFAULT 0,
        book_url TEXT NOT NULL DEFAULT '',
        content BLOB,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await _createChaptersTable(db);
  }

  Future<void> _createChaptersTable(Database db) async {
    // content = gzip BLOB of content_vi (same idea as Go translations.content_vi).
    await db.execute('''
      CREATE TABLE chapters(
        book_id TEXT NOT NULL,
        chapter_index INTEGER NOT NULL,
        title_zh TEXT NOT NULL DEFAULT '',
        title_vi TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT '',
        content BLOB,
        PRIMARY KEY (book_id, chapter_index)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_chapters_book ON chapters(book_id)',
    );
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE books ADD COLUMN author TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        'ALTER TABLE books ADD COLUMN total_chapters INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 3) {
      await _createChaptersTable(db);
    }
    if (oldVersion < 4) {
      // Dedicated cover_url column = backend cover_url (image), not API path.
      await db.execute(
        "ALTER TABLE books ADD COLUMN cover_url TEXT NOT NULL DEFAULT ''",
      );
      // Best-effort migrate old book_url if it was already a real image URL.
      await db.execute('''
        UPDATE books SET cover_url = book_url
        WHERE cover_url = ''
          AND book_url != ''
          AND book_url NOT LIKE '%/wm/books/%'
      ''');
    }
  }

  // ── Books ──────────────────────────────────────────────────────────────

  Future<void> saveBook(Book book) async {
    await saveBooks([book]);
  }

  /// Persist GET /wm/books rows. Keeps an existing cover BLOB unless [cover_url] changed.
  Future<void> saveBooks(List<Book> books) async {
    if (books.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final book in books) {
        batch.rawInsert(
          '''
          INSERT INTO books (id, title, author, cover_url, total_chapters, book_url, content, is_active)
          VALUES (?, ?, ?, ?, ?, ?, NULL, 1)
          ON CONFLICT(id) DO UPDATE SET
            title = excluded.title,
            author = excluded.author,
            cover_url = excluded.cover_url,
            total_chapters = excluded.total_chapters,
            book_url = excluded.book_url,
            is_active = 1,
            content = CASE
              WHEN books.cover_url = excluded.cover_url THEN books.content
              ELSE NULL
            END
          ''',
          [
            book.id,
            book.titleZh,
            book.author,
            book.coverUrl,
            book.totalChapters,
            book.coverUrl,
          ],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> saveBookCover(String bookId, Uint8List bytes) async {
    final db = await database;
    await db.update(
      'books',
      {'content': bytes},
      where: 'id = ?',
      whereArgs: [bookId],
    );
  }

  Future<List<Book>> getBooks({bool activeOnly = true}) async {
    final db = await database;
    final rows = await db.query(
      'books',
      columns: [
        'id',
        'title',
        'author',
        'cover_url',
        'book_url',
        'total_chapters',
        'is_active',
        'content',
      ],
      where: activeOnly ? 'is_active = ?' : null,
      whereArgs: activeOnly ? [1] : null,
      orderBy: 'title COLLATE NOCASE ASC',
    );
    return rows.map(_bookFromRow).toList(growable: false);
  }

  Future<Book?> getBookById(String id) async {
    final db = await database;
    final rows = await db.query(
      'books',
      columns: [
        'id',
        'title',
        'author',
        'cover_url',
        'book_url',
        'total_chapters',
        'is_active',
        'content',
      ],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _bookFromRow(rows.first);
  }

  Future<int> deleteBook(String id) async {
    final db = await database;
    await db.delete('chapters', where: 'book_id = ?', whereArgs: [id]);
    return db.delete('books', where: 'id = ?', whereArgs: [id]);
  }

  // ── Chapters (metadata + gzip content BLOB) ────────────────────────────

  /// Cache chapter list metadata. Never clears an existing content BLOB.
  Future<void> saveChapterList(String bookId, List<Chapter> chapters) async {
    if (chapters.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final c in chapters) {
        batch.rawInsert(
          '''
          INSERT INTO chapters (book_id, chapter_index, title_zh, title_vi, status, content)
          VALUES (?, ?, ?, ?, ?, NULL)
          ON CONFLICT(book_id, chapter_index) DO UPDATE SET
            title_zh = excluded.title_zh,
            title_vi = CASE
              WHEN length(excluded.title_vi) > 0 THEN excluded.title_vi
              ELSE chapters.title_vi
            END,
            status = excluded.status
          ''',
          [bookId, c.index, c.titleZh, c.titleVi, c.status],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Save full chapter; [content] stored as gzip BLOB for offline reading.
  ///
  /// Uses UPSERT so an empty body does not wipe an existing BLOB (no extra SELECT).
  Future<void> saveChapterDetail(String bookId, Chapter chapter) async {
    final db = await database;
    final Uint8List? blob = await chapter.contentBlobAsync();

    if (blob != null) {
      await db.insert(
        'chapters',
        {
          'book_id': bookId,
          'chapter_index': chapter.index,
          'title_zh': chapter.titleZh,
          'title_vi': chapter.titleVi,
          'status': chapter.status,
          'content': blob,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return;
    }

    // Metadata-only: preserve existing content BLOB.
    await db.rawInsert(
      '''
      INSERT INTO chapters (book_id, chapter_index, title_zh, title_vi, status, content)
      VALUES (?, ?, ?, ?, ?, NULL)
      ON CONFLICT(book_id, chapter_index) DO UPDATE SET
        title_zh = excluded.title_zh,
        title_vi = CASE
          WHEN length(excluded.title_vi) > 0 THEN excluded.title_vi
          ELSE chapters.title_vi
        END,
        status = excluded.status
      ''',
      [bookId, chapter.index, chapter.titleZh, chapter.titleVi, chapter.status],
    );
  }

  /// Bulk-save chapter bodies in one transaction (offline pack path).
  Future<void> saveChapterDetails(
    String bookId,
    List<Chapter> chapters,
  ) async {
    final withBody = chapters.where((c) => c.hasContent).toList();
    if (withBody.isEmpty) return;

    // Encode gzip off the UI isolate before the write transaction.
    final rows = <Map<String, Object?>>[];
    for (final c in withBody) {
      final blob = await c.contentBlobAsync();
      if (blob == null) continue;
      rows.add({
        'book_id': bookId,
        'chapter_index': c.index,
        'title_zh': c.titleZh,
        'title_vi': c.titleVi,
        'status': c.status,
        'content': blob,
      });
    }
    if (rows.isEmpty) return;

    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final row in rows) {
        batch.insert(
          'chapters',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Chapter list for UI — **metadata only** (no content BLOB, no gunzip).
  Future<List<Chapter>> getChapters(String bookId) async {
    final db = await database;
    final rows = await db.query(
      'chapters',
      columns: _chapterMetaColumns,
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'chapter_index ASC',
    );
    return rows.map(_chapterMetaFromRow).toList(growable: false);
  }

  /// Single chapter with body (gunzip only this one row).
  Future<Chapter?> getChapter(String bookId, int index) async {
    final db = await database;
    final rows = await db.query(
      'chapters',
      where: 'book_id = ? AND chapter_index = ?',
      whereArgs: [bookId, index],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return await _chapterFromRow(rows.first);
  }

  /// Whether this chapter already has offline body text (cheap EXISTS).
  Future<bool> hasChapterContent(String bookId, int index) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT 1 AS ok FROM chapters
      WHERE book_id = ? AND chapter_index = ? AND content IS NOT NULL
      LIMIT 1
      ''',
      [bookId, index],
    );
    return rows.isNotEmpty;
  }

  /// Indexes that already have a content BLOB for [bookId].
  Future<Set<int>> cachedContentIndexes(String bookId) async {
    final db = await database;
    final rows = await db.query(
      'chapters',
      columns: ['chapter_index'],
      where: 'book_id = ? AND content IS NOT NULL',
      whereArgs: [bookId],
    );
    return rows
        .map((r) => r['chapter_index'] as int? ?? 0)
        .where((i) => i > 0)
        .toSet();
  }

  Future<int> countCachedContent(String bookId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM chapters WHERE book_id = ? AND content IS NOT NULL',
      [bookId],
    );
    return (result.first['c'] as int?) ?? 0;
  }

  Book _bookFromRow(Map<String, Object?> row) {
    // Prefer cover_url; fall back to book_url for pre-v4 rows mid-migration.
    final cover = _rowString(row['cover_url']);
    final legacy = _rowString(row['book_url']);
    final coverUrl = cover.isNotEmpty
        ? cover
        : (legacy.contains('/wm/books/') ? '' : legacy);

    return Book(
      id: _rowString(row['id']),
      titleZh: _rowString(row['title']),
      author: _rowString(row['author']),
      totalChapters: (row['total_chapters'] as int?) ??
          int.tryParse('${row['total_chapters'] ?? ''}') ??
          0,
      coverUrl: coverUrl,
      coverBytes: _rowBlob(row['content']),
    );
  }

  static Uint8List? _rowBlob(Object? value) {
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    return null;
  }

  static String _rowString(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    return '$value';
  }

  Chapter _chapterMetaFromRow(Map<String, Object?> row) {
    return Chapter(
      index: (row['chapter_index'] as int?) ?? 0,
      titleZh: (row['title_zh'] as String?) ?? '',
      titleVi: (row['title_vi'] as String?) ?? '',
      status: (row['status'] as String?) ?? '',
    );
  }

  Future<Chapter> _chapterFromRow(Map<String, Object?> row) async {
    final raw = row['content'];
    Uint8List? blob;
    if (raw is Uint8List) {
      blob = raw;
    } else if (raw is List<int>) {
      blob = Uint8List.fromList(raw);
    }

    return Chapter(
      index: (row['chapter_index'] as int?) ?? 0,
      titleZh: (row['title_zh'] as String?) ?? '',
      titleVi: (row['title_vi'] as String?) ?? '',
      status: (row['status'] as String?) ?? '',
      contentVi: await Chapter.contentFromBlobAsync(blob),
    );
  }
}
