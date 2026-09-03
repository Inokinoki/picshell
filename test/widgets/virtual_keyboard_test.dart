import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:picshell/models/terminal_palette.dart';
import 'package:picshell/widgets/virtual_keyboard.dart';

void main() {
  group('KeyboardBarStyle', () {
    test('light palettes map to the light bar style', () {
      for (final palette in TerminalPalette.values) {
        final style = KeyboardBarStyle.forBrightness(
          palette.keyboardBrightness,
        );
        if (palette == TerminalPalette.solarizedLight) {
          expect(style, same(KeyboardBarStyle.light),
              reason: '${palette.displayName} should use the light style');
        } else {
          expect(style, same(KeyboardBarStyle.dark),
              reason: '${palette.displayName} should use the dark style');
        }
      }
    });
  });

  group('VirtualKeyboardBar rendering', () {
    Future<void> pumpBar(
      WidgetTester tester,
      Brightness brightness,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VirtualKeyboardBar(
              terminal: Terminal(maxLines: 100),
              keyboardBrightness: brightness,
            ),
          ),
        ),
      );
    }

    testWidgets('dark brightness renders the dark bar', (tester) async {
      await pumpBar(tester, Brightness.dark);

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(VirtualKeyboardBar),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(container.color, KeyboardBarStyle.dark.background);
    });

    testWidgets('light brightness renders the light bar', (tester) async {
      await pumpBar(tester, Brightness.light);

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(VirtualKeyboardBar),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(container.color, KeyboardBarStyle.light.background);
      // Spot-check a key label uses the light foreground.
      final label = tester.widget<Text>(find.text('Esc'));
      expect(label.style?.color, KeyboardBarStyle.light.foreground);
    });
  });
}
