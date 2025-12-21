import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tres_flutter/firebase_options.dart';
import 'package:tres_flutter/main.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } on FirebaseException catch (e) {
      if (e.code != 'duplicate-app') {
        rethrow;
      }
    }
  });

  testWidgets('Startup trace', (WidgetTester tester) async {
    await binding.traceAction(() async {
      await tester.pumpWidget(const TresApp());
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      expect(find.byType(MaterialApp), findsOneWidget);
    }, reportKey: 'startup_trace');
  });
}
