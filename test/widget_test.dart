import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xdocs/main.dart';
import 'package:xdocs/models/book.dart';
import 'package:xdocs/service/service.dart';

void main() {
  testWidgets('Book list loads from provider', (WidgetTester tester) async {
    final books = [
      const Book(
        id: 'cba02bf8-288e-468e-890b-dc4838b211c5',
        titleZh: '全员恶仙',
        author: '',
        totalChapters: 1541,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bookProvider.overrideWith(() => _FakeBookNotifier(books)),
        ],
        child: const XDocsApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('XDocs'), findsOneWidget);
    expect(find.text('全员恶仙'), findsWidgets);
    expect(find.text('1541 chương'), findsOneWidget);
  });
}

class _FakeBookNotifier extends BookNotifierService {
  _FakeBookNotifier(this._books);

  final List<Book> _books;

  @override
  Future<List<Book>> build() async => _books;
}
