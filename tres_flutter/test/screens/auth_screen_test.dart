import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:tres_flutter/screens/auth_screen.dart';
import 'package:tres_flutter/services/auth_service.dart';

class MockAuthService extends Mock implements AuthService {}

void main() {
  late MockAuthService mockAuthService;

  setUp(() {
    mockAuthService = MockAuthService();
  });

  Widget createWidgetUnderTest() {
    return MaterialApp(
      home: ChangeNotifierProvider<AuthService>.value(
        value: mockAuthService,
        child: const AuthScreen(),
      ),
    );
  }

  testWidgets('Email field shows clear button when text is entered', (tester) async {
    await tester.pumpWidget(createWidgetUnderTest());

    // Find email field
    final emailField = find.ancestor(
      of: find.text('Email'),
      matching: find.byType(TextField),
    ).first;

    expect(emailField, findsOneWidget);

    // Verify clear button is not initially visible
    expect(find.byIcon(Icons.clear), findsNothing);

    // Enter text
    await tester.enterText(emailField, 'test@example.com');
    await tester.pumpAndSettle();

    final textFieldWidget = tester.widget<TextField>(emailField);
    print('Text is: ${textFieldWidget.controller!.text}');

    // Verify clear button is visible
    final clearButton = find.byIcon(Icons.clear);
    expect(clearButton, findsOneWidget);

    // Tap clear button
    await tester.tap(clearButton);
    await tester.pumpAndSettle();

    // Verify text is cleared
    expect(find.text('test@example.com'), findsNothing);
    expect(textFieldWidget.controller!.text, isEmpty);
  });
}
