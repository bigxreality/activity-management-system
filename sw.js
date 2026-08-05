// App shell 快取：讓已經打開過的人斷網時至少能開啟介面。
// 不快取 Supabase API 呼叫——資料要即時，斷網時本來就無法讀寫，這裡只保證畫面能開。
//
// 快取策略是「網路優先，斷網才用快取」（network-first），不是「快取優先」：
// 這是持續在改版的內部工具，使用者應該要一打開就看到最新版本，快取只是離線時的
// 保底，不應該讓大家卡在舊版本、還要手動清快取才看得到更新。
var CACHE_NAME = 'activity-mgmt-shell-v3';
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

  // cache: 'no-store'：繞過瀏覽器自己的 HTTP 快取，強制真的問一次伺服器，
  // 不然就算這裡邏輯是 network-first，fetch() 還是可能被瀏覽器 HTTP 快取
  // 擋下來、直接回傳舊回應，等於白做——這是上一版只改 Service Worker
  // 邏輯、沒堵到的另一層快取。
  var freshReq = new Request(req, { cache: 'no-store' });

  event.respondWith(
    fetch(freshReq).then(function (res) {
      if (res && res.ok) {
        var clone = res.clone();
        caches.open(CACHE_NAME).then(function (cache) { cache.put(req, clone); });
      }
      return res;
    }).catch(function () {
      return caches.match(req); // 只有網路真的打不通（離線）才退回快取
    })
  );
});
