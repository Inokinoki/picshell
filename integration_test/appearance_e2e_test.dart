import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:picshell/models/terminal_palette.dart';

import 'package:picshell/providers/settings_provider.dart';

import 'helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Appearance: palette swatch selection updates the colour scheme',
      (tester) async {
    final container = await initApp();
    await pumpApp(tester, container);

    expect(container.read(settingsProvider).palette,
        TerminalPalette.defaultTheme);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    // The palette swatches each render an 'Aa' preview; tap one for nord.
    final swatches = find.text('Aa');
    expect(swatches, findsWidgets);
    final nordIndex = TerminalPalette.values.indexOf(TerminalPalette.nord);
    await tester.tap(swatches.at(nordIndex));
    await tester.pumpAndSettle();

    expect(container.read(settingsProvider).palette, TerminalPalette.nord,
        reason: 'tapping a swatch should switch the colour scheme');
    container.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
