import 'package:flutter_test/flutter_test.dart';
import 'package:mapa/main.dart';

void main() {
  testWidgets('without server settings the app explains what is missing', (tester) async {
    await tester.pumpWidget(const MapaApp());
    expect(find.textContaining('needs its server settings'), findsOneWidget);
  });
}
