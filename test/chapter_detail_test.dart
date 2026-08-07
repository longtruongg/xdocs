import 'package:flutter_test/flutter_test.dart';
import 'package:xdocs/models/chapter.dart';
import 'package:xdocs/service/service.dart';

void main() {
  test('Chapter.fromJson parses detail payload shape', () {
    final chapter = Chapter.fromJson({
      'index': 1,
      'title_zh': '种仙观',
      'status': 'done',
      'content_vi': '【Lên xe xuất phát】\n\nKhi hoàng hôn dần buông.',
    });

    expect(chapter.index, 1);
    expect(chapter.titleZh, '种仙观');
    expect(chapter.status, 'done');
    expect(chapter.hasContent, isTrue);
    expect(chapter.contentVi, contains('Lên xe'));

    final blob = chapter.contentBlob;
    expect(blob, isNotNull);
    expect(Chapter.contentFromBlob(blob), chapter.contentVi);
  });

  test(
    'BookApi.fetchChapterDetail hits live /wm/books/.../chapters/1',
    () async {
      const bookId = 'cba02bf8-288e-468e-890b-dc4838b211c5';
      final chapter = await BookApi.fetchChapterDetail(bookId, 1);

      expect(chapter.index, 1);
      expect(chapter.titleZh, isNotEmpty);
      expect(chapter.status, 'done');
      expect(chapter.contentVi.length, greaterThan(100));
      expect(chapter.contentVi, contains('Lên xe'));
    },
    // Skip if backend is down — still validates model above.
    tags: ['integration'],
  );
}
