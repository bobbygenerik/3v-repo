import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:tres_flutter/screens/home_screen.dart';
import 'package:tres_flutter/services/auth_service.dart';
import 'package:tres_flutter/services/call_listener_service.dart';
import 'package:tres_flutter/services/call_session_service.dart';
import 'package:tres_flutter/services/call_signaling_service.dart';
import 'package:tres_flutter/services/contact_service.dart';

// Mocks
class MockAuthService extends Mock implements AuthService {}
class MockContactService extends Mock implements ContactService {}
class MockCallListenerService extends Mock implements CallListenerService {}
class MockCallSignalingService extends Mock implements CallSignalingService {}
class MockCallSessionService extends Mock implements CallSessionService {}

void main() {
  late MockAuthService mockAuthService;
  late MockContactService mockContactService;
  late MockCallListenerService mockCallListenerService;
  late MockCallSignalingService mockCallSignalingService;
  late MockCallSessionService mockCallSessionService;
  late FakeFirebaseFirestore fakeFirestore;
  late MockUser mockUser;

  setUp(() {
    mockAuthService = MockAuthService();
    mockContactService = MockContactService();
    mockCallListenerService = MockCallListenerService();
    mockCallSignalingService = MockCallSignalingService();
    mockCallSessionService = MockCallSessionService();
    fakeFirestore = FakeFirebaseFirestore();

    mockUser = MockUser(
      uid: 'test_uid',
      email: 'test@example.com',
      displayName: 'Test User',
    );

    // Setup Auth Service
    when(() => mockAuthService.currentUser).thenReturn(mockUser);
    when(() => mockAuthService.authStateChanges).thenAnswer((_) => Stream.value(mockUser));
    when(() => mockAuthService.addListener(any())).thenReturn(null);
    when(() => mockAuthService.removeListener(any())).thenReturn(null);

    // Setup Contact Service
    when(() => mockContactService.isFavorite(any())).thenReturn(false);
    when(() => mockContactService.addListener(any())).thenReturn(null);
    when(() => mockContactService.removeListener(any())).thenReturn(null);

    // Setup Call Services
    when(() => mockCallListenerService.startListening()).thenReturn(null);
    when(() => mockCallListenerService.addListener(any())).thenReturn(null);
    when(() => mockCallListenerService.stopListening()).thenReturn(null);
    when(() => mockCallListenerService.removeListener(any())).thenReturn(null);
    when(() => mockCallListenerService.currentIncomingCall).thenReturn(null);
  });

  testWidgets('HomeScreen profile button has correct tooltip', (WidgetTester tester) async {
    // Populate Firestore with dummy data
    await fakeFirestore.collection('users').doc(mockUser.uid).set({
      'uid': mockUser.uid,
      'email': mockUser.email,
      'displayName': mockUser.displayName,
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: mockAuthService),
          ChangeNotifierProvider<ContactService>.value(value: mockContactService),
        ],
        child: MaterialApp(
          home: HomeScreen(
            firestore: fakeFirestore,
            callListener: mockCallListenerService,
            signalingService: mockCallSignalingService,
            sessionService: mockCallSessionService,
          ),
        ),
      ),
    );

    // Pump to settle animations/init
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Find the profile button by tooltip
    final profileButtonFinder = find.byTooltip('Account Menu');
    expect(profileButtonFinder, findsOneWidget);

    // Verify Add Contact button tooltip
    expect(find.byTooltip('Add Contact'), findsOneWidget);

    // Teardown: Remove HomeScreen from tree to set mounted=false
    // This allows the infinite timer loop in HomeScreen to break (it checks if (mounted))
    await tester.pumpWidget(const Placeholder());

    // Pump enough time for pending timers to fire and exit gracefully
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('HomeScreen shows empty state buttons', (WidgetTester tester) async {
    // Populate Firestore with dummy data (but NO contacts)
    await fakeFirestore.collection('users').doc(mockUser.uid).set({
      'uid': mockUser.uid,
      'email': mockUser.email,
      'displayName': mockUser.displayName,
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: mockAuthService),
          ChangeNotifierProvider<ContactService>.value(value: mockContactService),
        ],
        child: MaterialApp(
          home: HomeScreen(
            firestore: fakeFirestore,
            callListener: mockCallListenerService,
            signalingService: mockCallSignalingService,
            sessionService: mockCallSessionService,
          ),
        ),
      ),
    );

    // Pump to settle animations/init
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Wait for async loading to complete (loading contacts)
    await tester.pump(const Duration(seconds: 1));

    // Verify "Add Contact" button text
    expect(find.text('Add Contact'), findsOneWidget);
    expect(find.text('Start by adding friends to call'), findsOneWidget);

    // Teardown
    await tester.pumpWidget(const Placeholder());
    await tester.pump(const Duration(seconds: 5));
  });
}
