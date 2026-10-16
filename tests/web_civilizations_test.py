import base64
import gzip
import json
import time
from pathlib import Path
from playwright.sync_api import sync_playwright

root = Path(__file__).resolve().parents[1]
world = json.loads((root / 'tests/fixtures/living-civilizations-world.json').read_text())
payload = base64.b64encode(gzip.compress(json.dumps(world, ensure_ascii=False).encode())).decode()
mock = """(() => {
 const state=window.__sdk={data:{},events:{}};
 window.YaGames={init:async()=>({features:{LoadingAPI:{ready:()=>{}},GameplayAPI:{start:()=>{},stop:()=>{}}},on:(name,callback)=>state.events[name]=callback,getPlayer:async()=>({setData:async value=>{state.data=value},getData:async()=>state.data})})};
})();"""
read = """async () => {
 const db=await new Promise((resolve,reject)=>{const r=indexedDB.open('/userfs');r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error)});
 try {
  if(!db.objectStoreNames.contains('FILE_DATA'))return false;
  const store=db.transaction('FILE_DATA','readonly').objectStore('FILE_DATA');
  const fetch=r=>new Promise((resolve,reject)=>{r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error)});
  const [keys,values]=await Promise.all([fetch(store.getAllKeys()),fetch(store.getAll())]);
  const at=keys.findIndex(k=>k.endsWith('/world.json'));if(at<0)return false;
  const data=JSON.parse(new TextDecoder().decode(values[at].contents));
  if(!data.regions)return false;
  if(!data.regions.every(r=>keys.includes(keys[at]+'.regions/'+r.file)))return false;
  return {ticks:data.ticks,people:data.people.length,regions:data.regions.length,version:data.version,networks:data.networks,buildings:data.buildings,stamp:values[at].timestamp};
 }finally{db.close()}
}"""
errors = []
with sync_playwright() as playwright:
    browser = playwright.chromium.launch(executable_path='/usr/bin/chromium', headless=True, args=['--no-sandbox', '--enable-unsafe-swiftshader', '--disable-dev-shm-usage'])
    page = browser.new_page(viewport={'width': 1280, 'height': 800})
    page.add_init_script(mock)
    page.on('pageerror', lambda e: errors.append(str(e)))
    page.on('console', lambda m: errors.append(m.text) if m.type == 'error' else None)
    page.goto('http://127.0.0.1:8000', wait_until='domcontentloaded', timeout=60000)
    page.wait_for_function("!document.getElementById('status') && typeof window.__sdk.events.game_api_pause === 'function'", timeout=60000)
    page.evaluate("window.__sdk.events.game_api_pause()")
    page.wait_for_timeout(500)
    page.evaluate('(data)=>{window.__sdk.data={littleWorldsV7:data};window.LittleWorldsPlatform.load()}', payload)
    page.wait_for_timeout(1500)
    page.locator('canvas').focus()
    page.keyboard.press('Control+s')
    deadline = time.monotonic() + 45
    saved = None
    while time.monotonic() < deadline:
        saved = page.evaluate(read)
        if isinstance(saved, dict) and saved['regions'] == len(world['chunks']):
            break
        assert not errors, errors
        page.wait_for_timeout(500)
    assert isinstance(saved, dict) and saved['regions'] == len(world['chunks']), (saved, errors)
    assert saved['people'] == len(world['people']) and saved['ticks'] == world['ticks'] and saved['version'] == 13, saved
    assert saved['networks'] == world['networks'], 'City stages, founding origin and relations survive Web storage'
    assert saved['buildings'] == world['buildings'], 'Public works and modern housing survive Web storage'
    assert not errors, errors
    browser.close()
print('Web civilizations: city stages, buildings, origins and relations survive cloud import and IndexedDB save')
