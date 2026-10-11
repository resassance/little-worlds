
import base64
import gzip
import json
import time
from pathlib import Path
from playwright.sync_api import sync_playwright

read_world = """async () => {
 const db = await new Promise((resolve,reject)=>{const r=indexedDB.open('/userfs'); r.onsuccess=()=>resolve(r.result); r.onerror=()=>reject(r.error);});
 try {
  if(!db.objectStoreNames.contains('FILE_DATA')) return false;
  const store=db.transaction('FILE_DATA','readonly').objectStore('FILE_DATA');
  const read=r=>new Promise((resolve,reject)=>{r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error);});
  const [keys,values]=await Promise.all([read(store.getAllKeys()),read(store.getAll())]);
  const index=keys.findIndex(k=>k.endsWith('/world.json')); if(index<0) return false;
  const decode=value=>JSON.parse(new TextDecoder().decode(value.contents));
  const data=decode(values[index]); if(data.version!==8||!data.regions) return false;
  data.chunks=[];
  for(const r of data.regions){const at=keys.indexOf(keys[index]+'.regions/'+r.file);if(at<0)return false;data.chunks.push(decode(values[at]));}
  delete data.regions; return data;
 } finally {db.close();}
}"""
mock = """(() => {
 const state=window.__sdk={ready:0,starts:0,stops:0,events:{},data:{},callbacks:null};
 window.YaGames={init:async()=>({
  features:{LoadingAPI:{ready:()=>state.ready++},GameplayAPI:{start:()=>state.starts++,stop:()=>state.stops++}},
  on:(name,callback)=>state.events[name]=callback,
  getPlayer:async()=>({setData:async value=>{state.data=value;},getData:async()=>state.data}),
  adv:{showRewardedVideo:({callbacks})=>{state.callbacks=callbacks;callbacks.onOpen();}}
 })};
})();"""
errors = []
checks = 0
with sync_playwright() as playwright:
    browser = playwright.chromium.launch(executable_path='/usr/bin/chromium',headless=True,
        args=['--no-sandbox','--enable-unsafe-swiftshader','--disable-dev-shm-usage'])
    page = browser.new_page(viewport={'width':1280,'height':800})
    page.add_init_script(mock)
    page.on('pageerror', lambda error: errors.append(str(error)))
    page.on('console', lambda message: errors.append(message.text) if message.type=='error' else None)
    page.goto('http://127.0.0.1:8000',wait_until='domcontentloaded',timeout=60000)
    page.wait_for_function("!document.getElementById('status') && window.__sdk.ready===1",timeout=60000)
    page.wait_for_function('window.__sdk.starts>0',timeout=10000)
    checks += 2
    page.mouse.click(800,400)
    page.keyboard.press('Escape')
    page.evaluate("window.__sdk.events.game_api_pause()")
    page.wait_for_timeout(500)
    page.locator('canvas').focus()
    page.keyboard.press('Control+s')
    page.wait_for_function(read_world,timeout=15000)
    frozen = page.evaluate(read_world)
    page.wait_for_timeout(1200)
    page.locator('canvas').focus()
    page.keyboard.press('Control+s')
    page.wait_for_timeout(600)
    assert page.evaluate(read_world)['ticks']==frozen['ticks'], 'SDK pause freezes simulation'
    checks += 1
    page.evaluate("window.__sdk.events.game_api_resume()")
    page.wait_for_timeout(1800)
    page.locator('canvas').focus()
    page.keyboard.press('Control+s')
    deadline=time.monotonic()+15
    while time.monotonic()<deadline:
        if page.evaluate(read_world)['ticks']>frozen['ticks']: break
        page.wait_for_timeout(200)
    assert page.evaluate(read_world)['ticks']>frozen['ticks'], ('SDK resume advances simulation',frozen['ticks'],page.evaluate(read_world)['ticks'],page.evaluate('({ready:__sdk.ready, starts:__sdk.starts, stops:__sdk.stops,hidden:document.hidden})'), errors)
    checks += 1
    page.keyboard.press('Space')
    page.evaluate("window.LittleWorldsPlatform.rewarded()")
    page.evaluate("window.__sdk.callbacks.onRewarded();window.__sdk.callbacks.onRewarded();window.__sdk.callbacks.onClose()")
    page.wait_for_timeout(500)
    page.locator('canvas').focus()
    page.keyboard.press('Control+s')
    deadline=time.monotonic()+15
    while time.monotonic()<deadline:
        current=page.evaluate(read_world)
        if any(event['title']=='Живительный дождь' for event in current['history']): break
        page.wait_for_timeout(200)
    rewarded=page.evaluate(read_world)
    assert sum(event['title']=='Живительный дождь' for event in rewarded['history'])==1, 'duplicate callbacks produce one actual reward'
    checks += 1
    encoded=base64.b64encode(gzip.compress(json.dumps(frozen,ensure_ascii=False).encode())).decode()
    page.evaluate('(data)=>window.LittleWorldsPlatform.save(data)', encoded)
    page.wait_for_function('typeof window.__sdk.data.littleWorldsV7 === "string"',timeout=5000)
    page.evaluate('window.LittleWorldsPlatform.load()')
    page.wait_for_timeout(800)
    page.locator('canvas').focus()
    page.keyboard.press('Control+s')
    deadline=time.monotonic()+15
    while time.monotonic()<deadline:
        current=page.evaluate(read_world)
        if current['ticks']==frozen['ticks'] and current['people']==frozen['people']: break
        page.wait_for_timeout(200)
    cloud=page.evaluate(read_world)
    assert cloud['ticks']==frozen['ticks'] and cloud['people']==frozen['people'], 'cloud payload restores the actual Godot world'
    checks += 1
    assert not errors, json.dumps(errors,ensure_ascii=False)
    checks += 1
    output=Path(__file__).resolve().parents[1]/'artifacts'
    output.mkdir(exist_ok=True)
    page.screenshot(path=str(output/'world-web-sdk.png'))


    large=json.loads((output/'population-2000-world.json').read_text())
    assert len(large['people'])==2000
    encoded=base64.b64encode(gzip.compress(json.dumps(large,ensure_ascii=False).encode())).decode()
    page.evaluate('(data)=>{window.__sdk.data.littleWorldsV7=data;window.LittleWorldsPlatform.load()}',encoded)
    page.wait_for_timeout(1500)
    page.locator('canvas').focus()
    page.keyboard.press('Control+s')
    deadline=time.monotonic()+45
    while time.monotonic()<deadline:
        current=page.evaluate(read_world)
        if current and len(current['people'])==2000: break
        page.wait_for_timeout(250)
    assert len(current['people'])==2000 and current['people']==large['people'], 'WASM restores 2000 individual people with their work and families'
    checks+=1
    page.keyboard.press('Space')
    page.wait_for_timeout(3000)
    page.keyboard.press('Space')
    page.locator('canvas').focus()
    page.keyboard.press('Control+s')
    deadline=time.monotonic()+45
    while time.monotonic()<deadline:
        current=page.evaluate(read_world)
        if current and current['ticks']>large['ticks']: break
        page.wait_for_timeout(250)
    assert current['ticks']>large['ticks'] and len(current['people'])==2000, 'WASM advances a full population and commits its v8 snapshot'
    checks+=1
    assert not errors,json.dumps(errors,ensure_ascii=False)
    checks+=1
    page.screenshot(path=str(output/'world-web-population-2000.png'))
    browser.close()
print(f'Web SDK: {checks} checks, 0 failures; actual bridge readiness, pause/resume, one reward, cloud restore and 2000-person WASM simulation; no console errors.')
