// Firebase Cloud Messaging Service Worker
// This runs in the background to receive notifications even when app is closed

importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js');

// Your Firebase configuration
// This should match your firebase_options.dart web configuration
firebase.initializeApp({
  apiKey: "AIzaSyBwqg-oGQGa4LjQDmqg0LiJqZLH-5ViGkg",
  authDomain: "tres3-5fdba.firebaseapp.com",
  projectId: "tres3-5fdba",
  storageBucket: "tres3-5fdba.firebasestorage.app",
  messagingSenderId: "920237066671",
  appId: "1:920237066671:web:4c7d77f0f4d7b7c7e7d7c7",
});

const messaging = firebase.messaging();

// Handle background messages (when app is closed or in background)
messaging.onBackgroundMessage((payload) => {
  console.log('📬 Background message received:', payload);

  const notificationTitle = payload.notification?.title || 'Incoming Call';
  const notificationOptions = {
    body: payload.notification?.body || 'Someone is calling you',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: 'incoming-call', // Replaces previous notifications
    requireInteraction: true, // Stays visible until user acts
    vibrate: [200, 100, 200], // Vibration pattern
    data: {
      url: payload.data?.url || '/',
      invitationId: payload.data?.invitationId,
      roomName: payload.data?.roomName,
      token: payload.data?.token,
      livekitUrl: payload.data?.livekitUrl,
    },
    actions: [
      {
        action: 'answer',
        title: 'Answer',
        icon: '/icons/Icon-192.png'
      },
      {
        action: 'decline',
        title: 'Decline',
        icon: '/icons/Icon-192.png'
      }
    ]
  };

  return self.registration.showNotification(notificationTitle, notificationOptions);
});

// Handle notification click
self.addEventListener('notificationclick', (event) => {
  console.log('🔔 Notification clicked:', event.action);
  
  event.notification.close();

  const data = event.notification.data;

  if (event.action === 'answer') {
    // Open app and navigate to call screen
    const callUrl = `${data.url}?action=answer&invitationId=${data.invitationId}`;
    event.waitUntil(
      clients.openWindow(callUrl)
    );
  } else if (event.action === 'decline') {
    // Send decline request (you'll need to handle this in your app)
    const declineUrl = `${data.url}?action=decline&invitationId=${data.invitationId}`;
    event.waitUntil(
      clients.openWindow(declineUrl)
    );
  } else {
    // Default click - just open the app
    event.waitUntil(
      clients.openWindow(data.url || '/')
    );
  }
});
