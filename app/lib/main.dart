import 'package:flutter/material.dart';

import 'screens/library_screen.dart';

void main() {
  runApp(const ElinkBookApp());
}

/// elinkBook App 根元件。
class ElinkBookApp extends StatelessWidget {
  const ElinkBookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'elinkBook',
      home: LibraryScreen(),
    );
  }
}
