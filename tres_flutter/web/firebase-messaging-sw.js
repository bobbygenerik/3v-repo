// Firebase Cloud Messaging Service Worker
// This runs in the background to receive notifications even when app is closed

importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js');

// Firebase configuration with error handling
try {
  firebase.initializeApp({
    apiKey: "AIzaSyBwqg-oGQGa4LjQDmqg0LiJqZLH-5ViGkg",
    authDomain: "tres3-5fdba.firebaseapp.com",
    projectId: "tres3-5fdba",
    storageBucket: "tres3-5fdba.firebasestorage.app",
    messagingSenderId: "920237066671",
    appId: "1:920237066671:web:4c7d77f0f4d7b7c7e7d7c7",
  });
} catch (error) {
  console.error('Failed to initialize Firebase:', error);
}

const messaging = firebase.messaging();

// Handle background messages (when app is closed or in background)
messaging.onBackgroundMessage((payload) => {
  console.log('📬 Background message received:', payload);

  try {
    const notificationTitle = payload.notification?.title || 'Incoming Call';
    const notificationOptions = {
      body: payload.notification?.body || 'Someone is calling you',
      icon: '/icons/Icon-192.png',
      badge: '/icons/Icon-192.png',
      tag: 'incoming-call',
      requireInteraction: true,
      vibrate: [200, 100, 200],
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
  } catch (error) {
    console.error('Error handling background message:', error);
    // Fallback notification
    return self.registration.showNotification('Incoming Call', {
      body: 'Someone is calling you',
      icon: '/icons/Icon-192.png',
      tag: 'incoming-call'
    });
  }
});

// Handle notification click
self.addEventListener('notificationclick', (event) => {
  console.log('🔔 Notification clicked:', event.action);
  
  event.notification.close();

  try {
    const data = event.notification.data || {};
    let targetUrl;

    if (event.action === 'answer') {
      targetUrl = `${data.url || '/'}?action=answer&invitationId=${data.invitationId || ''}`;
    } else if (event.action === 'decline') {
      targetUrl = `${data.url || '/'}?action=decline&invitationId=${data.invitationId || ''}`;
    } else {
      targetUrl = data.url || '/';
    }

    event.waitUntil(
      clients.openWindow(targetUrl).catch(error => {
        console.error('Failed to open window:', error);
        // Fallback: try to focus existing client
        return clients.matchAll({ type: 'window' }).then(clientList => {
          if (clientList.length > 0) {
            return clientList[0].focus();
          }
        });
      })
    );
  } catch (error) {
    console.error('Error handling notification click:', error);
    // Fallback: just try to open the app
    event.waitUntil(clients.openWindow('/'));
  }
});
