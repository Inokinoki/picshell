import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:picshell/providers/settings_provider.dart';
import 'package:picshell/widgets/terminal_widget/terminal_widget.dart';

Widget _wrapWithOverrides({Terminal? terminal}) {
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith(
        (ref) => SettingsNotifier(loadFromStorage: false),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: TerminalWidget(terminal: terminal ?? Terminal(maxLines: 1000)),
      ),
    ),
  );
}

Widget _emptyWithOverrides() {
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith(
        (ref) => SettingsNotifier(loadFromStorage: false),
      ),
    ],
    child: MaterialApp(
      home: Scaffold(body: const SizedBox.shrink()),
    ),
  );
}

void main() {
  group('TerminalWidget lifecycle', () {
    testWidgets('builds without throwing', (tester) async {
      await tester.pumpWidget(_wrapWithOverrides());
      await tester.pump();

      expect(find.byType(TerminalWidget), findsOneWidget);
    });

    testWidgets('requestFocus on resume does not throw', (tester) async {
      await tester.pumpWidget(_wrapWithOverrides());
      await tester.pump();

      final binding = TestWidgetsFlutterBinding.instance;

      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      expect(
        () => binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
        returnsNormally,
      );

      await tester.pump();
    });

    testWidgets('pause then resume cycle completes', (tester) async {
      await tester.pumpWidget(_wrapWithOverrides());
      await tester.pump();

      final binding = TestWidgetsFlutterBinding.instance;

      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(find.byType(TerminalWidget), findsOneWidget);
    });

    testWidgets('multiple lifecycle transitions do not crash',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides());
      await tester.pump();

      final binding = TestWidgetsFlutterBinding.instance;

      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.resumed,
        AppLifecycleState.paused,
        AppLifecycleState.resumed,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
      }

      expect(find.byType(TerminalWidget), findsOneWidget);
    });

    testWidgets('resume after dispose does not crash', (tester) async {
      final terminal = Terminal(maxLines: 1000);

      await tester.pumpWidget(_wrapWithOverrides(terminal: terminal));
      await tester.pump();

      await tester.pumpWidget(_emptyWithOverrides());
      await tester.pump();

      final binding = TestWidgetsFlutterBinding.instance;
      expect(
        () => binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
        returnsNormally,
      );
    });

    testWidgets('renders TerminalView', (tester) async {
      await tester.pumpWidget(_wrapWithOverrides());
      await tester.pump();

      expect(find.byType(TerminalView), findsOneWidget);
    });
  });
}
