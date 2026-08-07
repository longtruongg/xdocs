import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xdocs/models/book.dart';
import 'package:xdocs/service/service.dart';

void main() {
  test('parses GET /wm/books list payload', () {
    const body =
        '[{"id":"cba02bf8-288e-468e-890b-dc4838b211c5",'
        '"title_zh":"全员恶仙",'
        '"author":"天外有山",'
        '"cover_url":"https://img22.ixdzs.com/96/96/96960e9fa88b658cad4e65e283fa4163.jpg",'
        '"total_chapters":1541}]';

    final decoded = jsonDecode(body) as List<dynamic>;
    final books = decoded.map((e) {
      if (e is Map<String, dynamic>) return Book.fromJson(e);
      return Book.fromJson(Map<String, dynamic>.from(e as Map));
    }).toList();

    expect(books, hasLength(1));
    final b = books.single;
    expect(b.id, 'cba02bf8-288e-468e-890b-dc4838b211c5');
    expect(b.titleZh, '全员恶仙');
    expect(b.title, '全员恶仙');
    expect(b.author, '天外有山');
    expect(
      b.coverUrl,
      'https://img22.ixdzs.com/96/96/96960e9fa88b658cad4e65e283fa4163.jpg',
    );
    expect(b.totalChapters, 1541);
    expect(b.chapterCount, 1541);
    expect(b.hasCover, isTrue);
    expect(resolveCoverUrl(b.coverUrl), b.coverUrl);
  });
}
