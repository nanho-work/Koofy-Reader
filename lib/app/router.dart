import 'package:flutter/material.dart';
import 'package:koofy_reader/features/library/domain/book.dart';
import 'package:koofy_reader/features/library/presentation/library_page.dart';
import 'package:koofy_reader/features/reader/presentation/reader_page.dart';
import 'package:koofy_reader/features/settings/presentation/settings_page.dart';

class AppRoutes {
  static const String library = '/';
  static const String reader = '/reader';
  static const String settings = '/settings';
}

class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.library:
        return MaterialPageRoute<void>(
          builder: (_) => const LibraryPage(),
          settings: settings,
        );
      case AppRoutes.reader:
        final argument = settings.arguments;
        if (argument is Book) {
          return MaterialPageRoute<void>(
            builder: (_) => ReaderPage(book: argument),
            settings: settings,
          );
        }
        return _errorRoute('책 정보를 불러오지 못했습니다.');
      case AppRoutes.settings:
        return MaterialPageRoute<void>(
          builder: (_) => const SettingsPage(),
          settings: settings,
        );
      default:
        return _errorRoute('알 수 없는 화면입니다: ${settings.name}');
    }
  }

  static Route<dynamic> _errorRoute(String message) {
    return MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('오류')),
        body: Center(child: Text(message)),
      ),
    );
  }
}
