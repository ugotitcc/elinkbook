import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elinkbook/l10n/app_localizations.dart';
import 'package:elinkbook/windows/window_fullscreen_controller.dart';
import 'package:elinkbook/windows/window_fullscreen_shortcuts.dart';

class FakeWindowFullscreenController implements WindowFullscreenController {
  bool _fullscreen;
  final List<bool> history = [];

  FakeWindowFullscreenController({bool initialFullscreen = false})
      : _fullscreen = initialFullscreen;

  @override
  bool get isFullscreenNow => _fullscreen;

  @override
  Future<bool> isFullscreen() async => _fullscreen;

  @override
  Future<void> setFullscreen(bool isFullscreen) async {
    _fullscreen = isFullscreen;
    history.add(isFullscreen);
  }
}

Widget buildTestApp({
  required WindowFullscreenController? controller,
  required Widget home,
}) {
  return MaterialApp(
    locale: const Locale('zh', 'TW'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => WindowFullscreenShortcuts(
      controller: controller,
      child: child ?? const SizedBox.shrink(),
    ),
    home: home,
  );
}

void main() {
  tearDown(() {
    WindowFullscreenShortcuts.activeEscOverrideCount = 0;
  });

  group('WindowFullscreenShortcuts', () {
    testWidgets('F11 在任何畫面都切換視窗全螢幕（首頁與 push 後的第二頁）', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final fake = FakeWindowFullscreenController(initialFullscreen: false);
        await tester.pumpWidget(
          buildTestApp(
            controller: fake,
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const Scaffold(body: Text('Page 2')),
                      ),
                    );
                  },
                  child: const Text('Go to Page 2'),
                ),
              ),
            ),
          ),
        );

        // 首頁按 F11
        await tester.sendKeyEvent(LogicalKeyboardKey.f11);
        await tester.pumpAndSettle();
        expect(fake.isFullscreenNow, isTrue);
        expect(fake.history, [true]);

        // 前往第二頁
        await tester.tap(find.text('Go to Page 2'));
        await tester.pumpAndSettle();
        expect(find.text('Page 2'), findsOneWidget);

        // 第二頁按 F11 -> 退出全螢幕
        await tester.sendKeyEvent(LogicalKeyboardKey.f11);
        await tester.pumpAndSettle();
        expect(fake.isFullscreenNow, isFalse);
        expect(fake.history, [true, false]);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('F11 按住不放（KeyRepeatEvent）只切換一次；Alt+F11、Ctrl+F11 不切換', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final fake = FakeWindowFullscreenController(initialFullscreen: false);
        await tester.pumpWidget(
          buildTestApp(
            controller: fake,
            home: const Scaffold(body: Text('Home')),
          ),
        );

        // KeyDown F11 -> 切換至 true
        await tester.sendKeyDownEvent(LogicalKeyboardKey.f11);
        await tester.pumpAndSettle();
        expect(fake.history, [true]);

        // KeyRepeat F11 -> 忽略
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.f11);
        await tester.pumpAndSettle();
        expect(fake.history, [true]);

        await tester.sendKeyUpEvent(LogicalKeyboardKey.f11);
        await tester.pumpAndSettle();

        // Alt+F11
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.f11);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.pumpAndSettle();
        expect(fake.history, [true]); // 未改變

        // Ctrl+F11
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.f11);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
        expect(fake.history, [true]); // 未改變
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('視窗全螢幕且沒有浮層時按 Esc：退出全螢幕', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final fake = FakeWindowFullscreenController(initialFullscreen: true);
        await tester.pumpWidget(
          buildTestApp(
            controller: fake,
            home: const Scaffold(body: Text('Home')),
          ),
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(fake.isFullscreenNow, isFalse);
        expect(fake.history, [false]);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('非全螢幕時按 Esc：不呼叫 setFullscreen；此時有 dismissible 對話框則照常關閉', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final fake = FakeWindowFullscreenController(initialFullscreen: false);
        await tester.pumpWidget(
          buildTestApp(
            controller: fake,
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (_) => const AlertDialog(title: Text('Dialog Title')),
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        );

        // 無對話框時按 Esc -> 不呼叫 setFullscreen
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(fake.history, isEmpty);

        // 打開對話框
        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();
        expect(find.text('Dialog Title'), findsOneWidget);

        // 按 Esc -> 對話框關閉，且不呼叫 setFullscreen
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('Dialog Title'), findsNothing);
        expect(fake.history, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('全螢幕且有 dismissible 對話框：第一次 Esc 只關對話框、全螢幕維持；第二次 Esc 才退出 (Review Focus 6)', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final fake = FakeWindowFullscreenController(initialFullscreen: true);
        await tester.pumpWidget(
          buildTestApp(
            controller: fake,
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (_) => const AlertDialog(title: Text('Modal Dialog')),
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        );

        // 打開對話框
        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();
        expect(find.text('Modal Dialog'), findsOneWidget);
        expect(fake.isFullscreenNow, isTrue);

        // 第一次按 Esc：只關對話框，全螢幕維持！
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('Modal Dialog'), findsNothing);
        expect(fake.isFullscreenNow, isTrue);
        expect(fake.history, isEmpty);

        // 第二次按 Esc：退出全螢幕！
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(fake.isFullscreenNow, isFalse);
        expect(fake.history, [false]);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('全螢幕且有 barrierDismissible: false 的對話框：Esc 退出全螢幕 (已知邊界)', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final fake = FakeWindowFullscreenController(initialFullscreen: true);
        await tester.pumpWidget(
          buildTestApp(
            controller: fake,
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => const AlertDialog(title: Text('Non-Dismissible Dialog')),
                    );
                  },
                  child: const Text('Open Non-Dismissible Dialog'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Non-Dismissible Dialog'));
        await tester.pumpAndSettle();
        expect(find.text('Non-Dismissible Dialog'), findsOneWidget);

        // barrierDismissible: false 的對話框不消費 DismissIntent，Esc 傳遞給外層退出視窗全螢幕
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(fake.isFullscreenNow, isFalse);
        expect(fake.history, [false]);
        // 對話框仍存在
        expect(find.text('Non-Dismissible Dialog'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('切換畫面（push／pop）本身不呼叫 setFullscreen（全螢幕狀態不被重置）', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final fake = FakeWindowFullscreenController(initialFullscreen: true);
        await tester.pumpWidget(
          buildTestApp(
            controller: fake,
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (ctx) => Scaffold(
                          body: ElevatedButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: const Text('Pop'),
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('Push'),
                ),
              ),
            ),
          ),
        );

        // Push
        await tester.tap(find.text('Push'));
        await tester.pumpAndSettle();
        expect(find.text('Pop'), findsOneWidget);
        expect(fake.history, isEmpty); // 沒有呼叫 setFullscreen

        // Pop
        await tester.tap(find.text('Pop'));
        await tester.pumpAndSettle();
        expect(find.text('Push'), findsOneWidget);
        expect(fake.history, isEmpty); // 沒有呼叫 setFullscreen
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('非 Windows（預設平台）或控制器為 null 時：找不到 Key("window_fullscreen_dismiss_actions")，F11 不呼叫任何控制器', (tester) async {
      // 預設 TargetPlatform.android (非 Windows)
      final fake = FakeWindowFullscreenController(initialFullscreen: false);
      await tester.pumpWidget(
        buildTestApp(
          controller: fake,
          home: const Scaffold(body: Text('Android Page')),
        ),
      );

      expect(find.byKey(const Key('window_fullscreen_dismiss_actions')), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pumpAndSettle();
      expect(fake.history, isEmpty);
    });
  });
}
