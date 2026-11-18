import 'package:flutter_test/flutter_test.dart';
import 'package:nix_client/main.dart';

void main() {
  testWidgets('Nix app initializes with tactical UI', (WidgetTester tester) async {
    await tester.pumpWidget(const NixApp());
    expect(find.text('PROJETO NIX'), findsOneWidget);
  });
}
