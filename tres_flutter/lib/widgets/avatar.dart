import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Reusable Avatar widget with caching, error fallback, and optional logging.
class Avatar extends StatelessWidget {
  final String? url;
  final double radius;
  final String? initials;
  final bool enableLogging;

  const Avatar({
    super.key,
    required this.url,
    this.radius = 20,
    this.initials,
    this.enableLogging = false,
  });

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.grey[700],
        child: Text(
          (initials ?? '?'),
          style: TextStyle(
            color: Colors.white,
            fontSize: radius * 0.6,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.grey[700],
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: url!,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            width: radius * 2,
            height: radius * 2,
            color: Colors.grey[800],
            child: Center(
              child: SizedBox(
                width: radius,
                height: radius,
                child: const CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          errorWidget: (context, url, error) {
            if (enableLogging) {
              debugPrint('Avatar load failed: $url -> $error');
            }
            return Container(
              width: radius * 2,
              height: radius * 2,
              color: Colors.grey[700],
              child: Center(
                child: Text(
                  (initials ?? '?'),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: radius * 0.6,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
