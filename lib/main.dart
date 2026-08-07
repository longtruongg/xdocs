import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xdocs/data/data_hook.dart';

import 'screens/book_list_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    print("Initializing SQLite database....");
    await DataHook.instance.database;
    print('SQLite Database initialized successfully.');
  } catch (e) {
    print('Failed to initialize database: $e');
  }

  runApp(ProviderScope(child: XDocsApp()));
}

class XDocsApp extends StatelessWidget {
  const XDocsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'X-Docs',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0E97EC),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: false),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0E97EC),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(centerTitle: false),
      ),
      themeMode: ThemeMode.light,
      home: const BookListScreen(),
    );
  }
}
