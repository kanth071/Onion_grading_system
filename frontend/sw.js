// Minimal service worker — enables "Add to Home Screen" installability.
// No offline caching of API data (inspection results need a live backend).
self.addEventListener("install", (e) => self.skipWaiting());
self.addEventListener("activate", (e) => self.clients.claim());
self.addEventListener("fetch", (e) => {
  // pass-through; no caching
});
