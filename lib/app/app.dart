import 'package:flutter/material.dart';

import '../features/library/presentation/library_screen.dart';
import '../infrastructure/database/app_database.dart';

class NotesApp extends StatefulWidget {
  const NotesApp({super.key});

  @override
  State<NotesApp> createState() => _NotesAppState();
}

class _NotesAppState extends State<NotesApp> {
  late final AppDatabase database;

  @override
  void initState() {
    super.initState();
    database = AppDatabase();
  }

  @override
  void dispose() {
    database.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Note References',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: LibraryScreen(database: database),
    );
  }
}

// Backward-compatible wrapper for the generated widget test.
// Prefer NotesApp in app code.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const NotesApp();
  }
}
