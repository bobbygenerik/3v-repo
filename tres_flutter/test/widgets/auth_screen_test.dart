import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:tres_flutter/services/auth_service.dart';
import 'package:tres_flutter/screens/auth_screen.dart';

void main() {
  testWidgets('AuthScreen renders sign-in UI', (WidgetTester tester) async {
    final auth = MockFirebaseAuth(signedIn: false);
    final firestore = FakeFirebaseFirestore();
    final authService = AuthService(auth: auth, firestore: firestore);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthService>.value(
        value: authService,
        child: const MaterialApp(home: AuthScreen()),
      ),
    );

    expect(find.text('Sign In'), findsWidgets);
    expect(find.text('Create Account'), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
  });
}
