import 'package:flutter_test/flutter_test.dart';
import 'package:picshell/app/app.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const PicshellApp());
    expect(find.text('Picshell'), findsOneWidget);
  });
}
