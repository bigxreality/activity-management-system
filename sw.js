// App shell 快取：讓已經打開過的人斷網時至少能開啟介面。
// 不快取 Supabase API 呼叫——資料要即時，斷網時本來就無法讀寫，這裡只保證畫面能開。
var CACHE_NAME = 'activity-mgmt-shell-v1';
var APP_SHELL = [
  './',
  './index.html',
  './manifest.json',
  './icons/icon.svg',
  './icons/icon-maskable.svg'
];

self.addEventListener('install', function (event) {
  event.waitUntil(
    caches.open(CACHE_NAME).then(function (cache) { return cache.addAll(APP_SHELL); })
  );
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  event.waitUntil(
    caches.keys().then(function (keys) {
      return Promise.all(keys.filter(function (k) { return k !== CACHE_NAME; }).map(function (k) { return caches.delete(k); }));
    })
  );
  self.clients.claim();
});

self.addEventListener('fetch', function (event) {
  var req = event.request;
  if (req.method !== 'GET') return; // 只快取讀取請求，Supabase 的寫入一律直接走網路
  var url = new URL(req.url);
  if (url.origin !== self.location.origin) return; // 跨網域（Supabase、CDN）一律不經過快取層，直接走網路

  event.respondWith(
    caches.match(req).then(function (cached) {
      var networkFetch = fetch(req).then(function (res) {
        if (res && res.ok) {
          var clone = res.clone();
          caches.open(CACHE_NAME).then(function (cache) { cache.put(req, clone); });
        }
        return res;
      }).catch(function () { return cached; });
      return cached || networkFetch;
    })
  );
});
