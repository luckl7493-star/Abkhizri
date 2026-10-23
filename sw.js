const V="aab-v2",SHELL=["./","manifest.json","icon-192.png","icon-512.png"];
self.addEventListener("install",e=>{e.waitUntil(caches.open(V).then(c=>c.addAll(SHELL)).then(()=>self.skipWaiting()))});
self.addEventListener("activate",e=>{e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!==V).map(x=>caches.delete(x)))).then(()=>self.clients.claim()))});
self.addEventListener("fetch",e=>{
  const r=e.request,u=new URL(r.url);
  if(r.method!=="GET"||u.origin!==location.origin)return; // orders/login (Supabase) always go to the network
  if(r.mode==="navigate"){e.respondWith(fetch(r,{cache:"no-store"}).then(x=>{const c=x.clone();caches.open(V).then(h=>h.put("./",c));return x}).catch(()=>caches.match("./")));return}
  e.respondWith(caches.match(r).then(x=>x||fetch(r).then(y=>{const c=y.clone();caches.open(V).then(h=>h.put(r,c));return y})));
});
