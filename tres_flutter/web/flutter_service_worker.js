// This is a minimal service worker for development
// It will be replaced by Flutter's generated service worker in production builds

self.addEventListener('install', function(event) {
  self.skipWaiting();
});

self.addEventListener('activate', function(event) {
  event.waitUntil(
    self.clients.claim().catch(error => {
      console.error('Failed to claim clients:', error);
    })
  );
});

self.addEventListener('fetch', function(event) {
  // Pass through all requests with error handling
  event.respondWith(
    fetch(event.request).catch(error => {
      console.error('Fetch failed:', error);
      // Return a basic response for failed requests
      return new Response('Service temporarily unavailable', {
        status: 503,
        statusText: 'Service Unavailable'
      });
    })
  );
});
