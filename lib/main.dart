import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;

import 'app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Initializes the PDFium-backed pdfrx runtime.
  //
  // This is safe to call here and keeps us ready for lower-level pdfrx/PDFium
  // document APIs later.
  pdfrx.pdfrxFlutterInitialize();

  runApp(const ProviderScope(child: NotesApp()));
}