import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;

/// List item from `GET /wm/books/:id/chapters`:
/// `{ "index", "title_zh", "status" }`
///
/// Detail from `GET /wm/books/:id/chapters/:index`:
/// `{ "index", "title_zh", "status", "title_vi?", "content_vi?" }`
///
/// On the **Go DB**, `content_vi` is a **gzip BLOB**. The HTTP handler
/// decompresses it before JSON, so clients usually get a plain string.
/// [contentFromJson] still accepts base64 / raw bytes if the wire format changes.
class Chapter {
  final int index;
  final String titleZh;
  final String status;
  final String titleVi;
  final String contentVi;

  const Chapter({
    required this.index,
    required this.titleZh,
    this.status = '',
    this.titleVi = '',
    this.contentVi = '',
  });

  /// Prefer Vietnamese title when present.
  String get displayTitle =>
      titleVi.trim().isNotEmpty ? titleVi : titleZh;

  bool get isDone => status == 'done';
  bool get isTranslating => status == 'translating';
  bool get isActive =>
      status.isEmpty || status == 'done' || status == 'pending';

  bool get hasContent => contentVi.trim().isNotEmpty;

  Chapter copyWith({
    int? index,
    String? titleZh,
    String? status,
    String? titleVi,
    String? contentVi,
  }) {
    return Chapter(
      index: index ?? this.index,
      titleZh: titleZh ?? this.titleZh,
      status: status ?? this.status,
      titleVi: titleVi ?? this.titleVi,
      contentVi: contentVi ?? this.contentVi,
    );
  }

  factory Chapter.fromJson(Map<String, dynamic> json) {
    return Chapter(
      index: _asInt(json['index'] ?? json['chapter_index']),
      titleZh: (json['title_zh'] ?? '') as String,
      status: (json['status'] ?? '') as String,
      titleVi: (json['title_vi'] ?? json['title_vn'] ?? '') as String,
      contentVi: contentFromJson(json['content_vi'] ?? json['content_vn']),
    );
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        'title_zh': titleZh,
        'status': status,
        if (titleVi.isNotEmpty) 'title_vi': titleVi,
        if (contentVi.isNotEmpty) 'content_vi': contentVi,
      };

  /// Gzip BLOB for local SQLite (same idea as Go `content_vi` column).
  Uint8List? get contentBlob {
    if (!hasContent) return null;
    return Uint8List.fromList(gzip.encode(utf8.encode(contentVi)));
  }

  /// Encode on a worker isolate when the body is large (avoids jank on save).
  Future<Uint8List?> contentBlobAsync() async {
    if (!hasContent) return null;
    if (contentVi.length < 24 * 1024) return contentBlob;
    return compute(_gzipEncodeIsolate, contentVi);
  }

  /// Decode a local/server BLOB → text (gzip preferred, plain UTF-8 fallback).
  static String contentFromBlob(Uint8List? data) {
    if (data == null || data.isEmpty) return '';
    try {
      return utf8.decode(gzip.decode(data));
    } catch (_) {
      try {
        return utf8.decode(data);
      } catch (_) {
        return '';
      }
    }
  }

  /// Decode off the UI isolate when the BLOB is large (smooth route animations).
  static Future<String> contentFromBlobAsync(Uint8List? data) async {
    if (data == null || data.isEmpty) return '';
    if (data.length < 16 * 1024) return contentFromBlob(data);
    return compute(_gzipDecodeIsolate, data);
  }

  static Uint8List _gzipEncodeIsolate(String text) {
    return Uint8List.fromList(gzip.encode(utf8.encode(text)));
  }

  static String _gzipDecodeIsolate(Uint8List data) => contentFromBlob(data);

  /// Wire JSON may be plain string (current API), base64, or byte list.
  static String contentFromJson(dynamic value) {
    if (value == null) return '';
    if (value is String) {
      if (value.isEmpty) return value;
      // Current Go API already gunzips → plain UTF-8 string.
      // If someone posts base64(gzip), try that when plain looks binary-ish.
      if (_looksLikeBase64(value)) {
        try {
          final bytes = base64Decode(value);
          final text = contentFromBlob(Uint8List.fromList(bytes));
          if (text.isNotEmpty) return text;
        } catch (_) {/* keep as plain string */}
      }
      return value;
    }
    if (value is List) {
      final bytes = Uint8List.fromList(
        value.map((e) => e is int ? e : int.tryParse('$e') ?? 0).toList(),
      );
      return contentFromBlob(bytes);
    }
    return '$value';
  }

  static bool _looksLikeBase64(String s) {
    if (s.length < 16 || s.length % 4 != 0) return false;
    // gzip magic in base64 often starts with H4sI
    if (s.startsWith('H4sI')) return true;
    return false;
  }

  static List<Chapter> listFromJson(List<dynamic> list) {
    return list
        .whereType<Map<String, dynamic>>()
        .map(Chapter.fromJson)
        .toList(growable: false);
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

/// Paged list payload from `GET /wm/books/:id/chapters`.
class ChapterPage {
  final int offset;
  final int limit;
  final List<Chapter> chapters;

  const ChapterPage({
    required this.offset,
    required this.limit,
    required this.chapters,
  });

  factory ChapterPage.fromJson(Map<String, dynamic> json) {
    final raw = json['chapters'];
    return ChapterPage(
      offset: Chapter._asInt(json['offset']),
      limit: Chapter._asInt(json['limit']),
      chapters: raw is List ? Chapter.listFromJson(raw) : const <Chapter>[],
    );
  }
}
