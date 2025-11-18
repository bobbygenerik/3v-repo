const CACHE_NAME = '3v-call-v1';
const urlsToCache = [
  '/',
  '/index.html',
  '/splash.html',
  '/signin.html',
  '/signup.html',
  '/home.html',
  '/profile.html',
  '/settings.html',
  '/call.html',
  '/incoming.html',
  '/logo.png',
  '/splash-logo.png'
];

// Install event - cache resources
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => {
        console.log('📦 Opened cache');
        return cache.addAll(urlsToCache);
      })
      .catch(error => {
        console.error('Failed to cache resources:', error);
        // Continue installation even if caching fails
      })
  );
  self.skipWaiting();
});

// Fetch event - serve from cache, fallback to network
self.addEventListener('fetch', event => {
  event.respondWith(
    caches.match(event.request)
      .then(response => {
        // Cache hit - return response
        if (response) {
          return response;
        }
        
        // Clone the request
        const fetchRequest = event.request.clone();
        
        return fetch(fetchRequest).then(response => {
          // Check if valid response
          if (!response || response.status !== 200 || response.type !== 'basic') {
            return response;
          }
          
          // Clone the response
          const responseToCache = response.clone();
          
          caches.open(CACHE_NAME)
            .then(cache => {
              cache.put(event.request, responseToCache);
            })
            .catch(cacheError => {
              console.error('Failed to cache response:', cacheError);
            });
          
          return response;
        })
        .catch(fetchError => {
          console.error('Fetch failed:', fetchError);
          // Return offline page or basic error response
          return new Response('Offline - Please check your connection', {
            status: 503,
            statusText: 'Service Unavailable'
          });
        });
      })
  );
});

// Activate event - clean up old caches
self.addEventListener('activate', event => {
  const cacheWhitelist = [CACHE_NAME];
  event.waitUntil(
    caches.keys().then(cacheNames => {
      return Promise.all(
        cacheNames.map(cacheName => {
          if (cacheWhitelist.indexOf(cacheName) === -1) {
            return caches.delete(cacheName);
          }
        })
      );
    })
    .catch(error => {
      console.error('Failed to clean up caches:', error);
    })
  );
  self.clients.claim();
});
