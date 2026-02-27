import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:tres_flutter/widgets/avatar.dart';

void main() {
  testWidgets('Avatar optimizes memory usage by setting memCache properties', (
    WidgetTester tester,
  ) async {
    const double radius = 30.0;
    const String testUrl = 'https://example.com/avatar.jpg';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Avatar(url: testUrl, radius: radius),
        ),
      ),
    );

    // Find the CachedNetworkImage widget
    final cachedImageFinder = find.byType(CachedNetworkImage);
    expect(cachedImageFinder, findsOneWidget);

    final CachedNetworkImage cachedImage = tester.widget(cachedImageFinder);

    // Expected cache size: radius * 2 (diameter) * 3 (pixel density factor)
    final int expectedCacheSize = (radius * 2 * 3).toInt();

    expect(
      cachedImage.memCacheWidth,
      equals(expectedCacheSize),
      reason: 'memCacheWidth should be optimized',
    );
    expect(
      cachedImage.memCacheHeight,
      equals(expectedCacheSize),
      reason: 'memCacheHeight should be optimized',
    );
  });
}
