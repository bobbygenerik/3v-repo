import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tres_flutter/widgets/call_waiting_banner.dart';

void main() {
  testWidgets('CallWaitingBanner has accessible semantics', (
    WidgetTester tester,
  ) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CallWaitingBanner(
            callerName: 'Test Caller',
            isVideoCall: false,
            onAccept: () {},
            onDecline: () {},
            // callerPhotoUrl is null to avoid network issues
          ),
        ),
      ),
    );

    // Verify that the widget renders correctly
    expect(find.text('Test Caller'), findsOneWidget);
    expect(find.text('Waiting...'), findsOneWidget);

    // Verify Semantics
    // The implementation plan says: wrap Material in Semantics(liveRegion: true, label: ...)
    // In the BEFORE state, these semantics and tooltips do not exist, so this test should FAIL.

    // Check for the Semantics widget directly in the widget tree
    // We check for the widget presence because finding by semantics label
    // depends on how the framework merges semantics nodes, which can be tricky with Material widgets.
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label ==
                'Incoming call waiting from Test Caller' &&
            widget.properties.liveRegion == true,
      ),
      findsOneWidget,
      reason:
          'Should have a Semantics widget with correct label and liveRegion',
    );

    // Check for tooltips on buttons
    expect(
      find.byTooltip('Decline call'),
      findsOneWidget,
      reason: 'Decline button should have a tooltip',
    );

    expect(
      find.byTooltip('Accept call'),
      findsOneWidget,
      reason: 'Accept button should have a tooltip',
    );
  });
}
