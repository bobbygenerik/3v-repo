// This is a minimal service worker for development
// It will be replaced by Flutter's generated service worker in production builds

self.addEventListener('install', function(event) {
  self.skipWaiting();
});

self.addEventListener('activate', function(event) {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', function(event) {
  // Just pass through all requests in development
  event.respondWith(fetch(event.request));
});
