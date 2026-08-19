import 'dart:typed_data';

import 'chapter.dart';

export 'chapter.dart';

/// Book list item from `GET /wm/books`:
/// ```json
/// { "id", "title_zh", "author", "cover_url", "total_chapters", "intro?" }
/// ```
class Book {
  final String id;
  final String titleZh;
  final String author;
  final int totalChapters;

  /// Image URL from backend `cover_url` (absolute or relative to API host).
  final String coverUrl;

  /// JPEG/WebP bytes from SQLite `books.content`. Null until first download.
  final Uint8List? coverBytes;
  final String intro;
  final List<Chapter> chapters;
  final ColorSeed coverColor;

  const Book({
    required this.id,
    required this.titleZh,
    required this.author,
    required this.totalChapters,
    this.coverUrl = '',
    this.coverBytes,
    this.intro = '',
    this.chapters = const <Chapter>[],
    this.coverColor = ColorSeed.indigo,
  });

  /// Display title (backend field is `title_zh`).
  String get title => titleZh;

  factory Book.fromJson(Map<String, dynamic> json) {
    final rawChapters = json['chapters'];
    final id = '${json['id'] ?? ''}';
    return Book(
      id: id,
      titleZh: _asString(json['title_zh'] ?? json['title']),
      author: _asString(json['author']),
      totalChapters: _asInt(json['total_chapters'] ?? json['totalChapters']),
      coverUrl: _asString(json['cover_url'] ?? json['coverUrl']),
      intro: _asString(json['intro'] ?? json['description']),
      chapters: rawChapters is List
          ? Chapter.listFromJson(rawChapters)
          : const <Chapter>[],
      coverColor: ColorSeed.values[id.hashCode.abs() % ColorSeed.values.length],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title_zh': titleZh,
        'author': author,
        'total_chapters': totalChapters,
        if (coverUrl.isNotEmpty) 'cover_url': coverUrl,
        if (intro.isNotEmpty) 'intro': intro,
        if (chapters.isNotEmpty)
          'chapters': chapters.map((c) => c.toJson()).toList(),
      };

  /// Prefer loaded chapters; otherwise use list-API `total_chapters`.
  List<Chapter> get activeChapters =>
      chapters.where((c) => c.isActive).toList(growable: false);

  int get chapterCount =>
      chapters.isNotEmpty ? activeChapters.length : totalChapters;

  bool get hasCoverImage => coverBytes != null && coverBytes!.isNotEmpty;

  bool get hasCover => hasCoverImage || coverUrl.trim().isNotEmpty;

  /// UI number from backend `index` (1-based).
  int chapterNumberOf(Chapter chapter) => chapter.index;

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static String _asString(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    return '$value';
  }
}

/// Fallback palette when cover image is missing / fails to load.
enum ColorSeed { indigo, teal, deepOrange, purple, blueGrey, brown }
