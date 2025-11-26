import 'package:flutter/material.dart';
import '../config/app_theme.dart';

/// Call Waiting Banner Widget
/// Shows a compact notification banner when receiving a call while already in another call
class CallWaitingBanner extends StatelessWidget {
  final String callerName;
  final String? callerPhotoUrl;
  final bool isVideoCall;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const CallWaitingBanner({
    super.key,
    required this.callerName,
    this.callerPhotoUrl,
    required this.isVideoCall,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.primaryDark,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.primaryBlue.withOpacity(0.5),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Caller Avatar
            CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.primaryBlue,
              backgroundImage: callerPhotoUrl != null
                  ? NetworkImage(callerPhotoUrl!)
                  : null,
              child: callerPhotoUrl == null
                  ? Text(
                      callerName.isNotEmpty
                          ? callerName[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    )
                  : null,
            ),
            
            const SizedBox(width: 12),
            
            // Caller Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    callerName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textWhite,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        isVideoCall ? Icons.videocam : Icons.phone,
                        color: AppColors.primaryBlue,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Waiting...',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textLight.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(width: 8),
            
            // Decline Button
            IconButton(
              onPressed: onDecline,
              icon: const Icon(Icons.call_end),
              color: Colors.red,
              iconSize: 20,
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
              style: IconButton.styleFrom(
                backgroundColor: Colors.red.withOpacity(0.2),
                shape: const CircleBorder(),
              ),
            ),
            
            const SizedBox(width: 8),
            
            // Accept Button
            IconButton(
              onPressed: onAccept,
              icon: Icon(isVideoCall ? Icons.videocam : Icons.phone),
              color: Colors.green,
              iconSize: 20,
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(),
              style: IconButton.styleFrom(
                backgroundColor: Colors.green.withOpacity(0.2),
                shape: const CircleBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
