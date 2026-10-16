import base64
import gzip
import json
import time
from pathlib import Path
from playwright.sync_api import sync_playwright

root = Path(__file__).resolve().parents[1]
mock = """(() => {
 const state=window.__sdk={data:{},events:{}};
 window.YaGames={init:async()=>({features:{LoadingAPI:{ready:()=>{}},GameplayAPI:{start:()=>{},stop:()=>{}}},on:(name,callback)=>state.events[name]=callback,getPlayer:async()=>({setData:async value=>{state.data=value},getData:async()=>state.data})})};
})();"""
read = """async () => {
 const db=await new Promise((ok,no)=>{const r=indexedDB.open('/userfs');r.onsuccess=()=>ok(r.result);r.onerror=()=>no(r.error)});
 try {
  if(!db.objectStoreNames.contains('FILE_DATA'))return false;
  const store=db.transaction('FILE_DATA','readonly').objectStore('FILE_DATA');
  const fetch=r=>new Promise((ok,no)=>{r.onsuccess=()=>ok(r.result);r.onerror=()=>no(r.error)});
  const [keys,values]=await Promise.all([fetch(store.getAllKeys()),fetch(store.getAll())]);
  const at=keys.findIndex(k=>k.endsWith('/world.json'));if(at<0)return false;
  const w=JSON.parse(new TextDecoder().decode(values[at].contents));
  if(!w.regions?.every(r=>keys.includes(keys[at]+'.regions/'+r.file)))return false;
  return {seed:w.seed,ticks:w.ticks,version:w.version,towns:w.towns,people:w.people,networks:w.networks,buildings:w.buildings};
 }finally{db.close()}
}"""
errors = []

def boot(page):
    page.goto('http://127.0.0.1:8000', wait_until='domcontentloaded', timeout=60000)
    page.wait_for_function("!document.getElementById('status') && typeof window.__sdk.events.game_api_pause === 'function'", timeout=60000)
    page.evaluate('window.__sdk.events.game_api_pause()')
    page.wait_for_timeout(400)

def save(page, expected=None):
    page.locator('canvas').focus()
    page.keyboard.press('Control+s')
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        data = page.evaluate(read)
        if isinstance(data, dict) and (expected is None or data['ticks'] == expected['ticks']):
            assert not errors, errors
            return data
        page.wait_for_timeout(300)
    raise AssertionError(('Save did not finish', errors))

def import_world(page, name):
    world = json.loads((root / 'tests/fixtures' / name).read_text())
    payload = base64.b64encode(gzip.compress(json.dumps(world, ensure_ascii=False).encode())).decode()
    page.evaluate('(v)=>{window.__sdk.data={littleWorldsV7:v};window.LittleWorldsPlatform.load()}', payload)
    page.wait_for_timeout(1500)
    return world, save(page, world)

with sync_playwright() as playwright:
    browser = playwright.chromium.launch(executable_path='/usr/bin/chromium', headless=True, args=['--no-sandbox', '--enable-unsafe-swiftshader', '--disable-dev-shm-usage'])
    context = browser.new_context(viewport={'width': 1280, 'height': 800})
    context.add_init_script(mock)
    page = context.new_page()
    page.on('pageerror', lambda error: errors.append(str(error)))
    page.on('console', lambda message: errors.append(message.text) if message.type == 'error' else None)
    boot(page)
    first = save(page)
    assert first['version'] == 15 and 0 < first['seed'] <= 2147483647
    boot(page)
    again = save(page)
    assert again['seed'] == first['seed'], 'Reload must preserve the initial world'
    old, saved = import_world(page, 'living-civilizations-world.json')
    assert saved['version'] == 15 and saved['networks'] == old['networks'] and saved['buildings'] == old['buildings']
    active, saved = import_world(page, 'territory-world.json')
    assert saved['towns'] == active['towns'] and saved['people'] == active['people'], 'Land project, progress and carried supplies must survive Web storage'
    assert saved['towns'][0]['landworks']['project']['work'] > 0
    context.close()
    context = browser.new_context(viewport={'width': 1280, 'height': 800})
    context.add_init_script(mock)
    page = context.new_page()
    page.on('pageerror', lambda error: errors.append(str(error)))
    page.on('console', lambda message: errors.append(message.text) if message.type == 'error' else None)
    boot(page)
    other = save(page)
    assert other['seed'] != first['seed'], 'Independent players must start with different seeds'
    assert not errors, errors
    context.close()
    browser.close()
print('Web territory: random first worlds, reload, old saves and active resident work persist correctly')
