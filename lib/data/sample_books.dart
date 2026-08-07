import '../models/book.dart';

List<Chapter> _generateChapters(
  int count, {
  String prefix = 'Chương',
}) {
  return List.generate(count, (i) {
    final n = i + 1;
    return Chapter(
      index: n,
      titleZh: '$prefix $n',
      status: 'done',
      titleVi: '$prefix $n: Phần $n của câu chuyện',
      contentVi:
          'Nội dung chương $n.\n\n'
          'Đây là bản demo — sau này thay bằng content_vi từ API Go.\n\n'
          '${List.generate(3, (p) => 'Đoạn văn ${p + 1}: câu chuyện tiếp tục phát triển.').join('\n\n')}',
    );
  });
}

/// Local mock only — list screen loads from `GET /wm/books`.
final List<Book> sampleBooks = [
  Book(
    id: '1',
    titleZh: 'Toàn Viên Ác Tiên!!!',
    author: 'Thiên Ngoại Hữu Sơn',
    totalChapters: 48,
    coverUrl:
        'https://img22.ixdzs.com/96/96/96960e9fa88b658cad4e65e283fa4163.jpg',
    intro:
        'Thiên hạ đồn rằng, có một đạo quan, bên trong có một tảng đất thần kỳ. '
        'Chỉ cần coi con người là một "hạt giống", gieo vào đất, thì có thể thành tiên.\n\n'
        'Lý Thập Ngũ tìm tiên suốt mười năm, cuối cùng cũng tìm được đạo quan, '
        'cũng tự mình gieo mình vào đất, nhưng lại không ngờ...\n\n'
        'Chào mừng đến với thế giới của Toàn Viên Ác Tiên.',
    chapters: _generateChapters(48),
  ),
];
