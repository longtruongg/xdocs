import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xdocs/data/data_hook.dart';
import 'package:xdocs/models/book.dart';

/// SQLite-backed shelf cache (offline-first source for [bookProvider]).
class BookLocalStorage {
  Future<List<Book>> fetchBookLocal() async {
    return DataHook.instance.getBooks();
  }

  Future<void> saveBooks(List<Book> books) async {
    await DataHook.instance.saveBooks(books);
  }
}

final bookLocalStorage = Provider((ref) => BookLocalStorage());
