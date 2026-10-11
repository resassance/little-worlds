
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
  const data=decode(values[index]); if(data.version!==9||!data.regions) return false;
  data.chunks=[];
  for(const r of data.regions){const at=keys.indexOf(keys[index]+'.regions/'+r.file);if(at<0)return false;data.chunks.push(decode(values[at]));}
  delete data.regions; return data;
 } finally {db.close();}
}"""
read_world_brief = read_world.replace("delete data.regions; return data;", "delete data.regions; delete data.chunks; if(data.people.length>32)data.people=data.people.map(person=>person.id); return data;")
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
    def await_world(predicate=lambda value: True, timeout=60):
        deadline=time.monotonic()+timeout
        next_save=time.monotonic()+30
        while time.monotonic()<deadline:
            value=page.evaluate(read_world_brief)
            if isinstance(value,dict) and predicate(value):
                complete=page.evaluate(read_world)
                if isinstance(complete,dict) and predicate(complete):
                    return complete
            if time.monotonic()>=next_save:
                page.locator('canvas').focus()
                page.keyboard.press('Control+s')
                next_save=time.monotonic()+30
            page.wait_for_timeout(200)
        page.screenshot(path=str(Path(__file__).resolve().parents[1]/'artifacts'/'web-sdk-timeout.png'))
        raise AssertionError(f'Complete saved world did not become available: ticks={value.get("ticks") if isinstance(value,dict) else None}, people={len(value.get("people",[])) if isinstance(value,dict) else None}, errors={errors}')

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
    frozen = await_world()
    page.wait_for_timeout(1200)
    page.locator('canvas').focus()
    page.keyboard.press('Control+s')
    current=await_world(lambda value: value['ticks']==frozen['ticks'])
    assert current['ticks']==frozen['ticks'], 'SDK pause freezes simulation'
    checks += 1
    page.evaluate("window.__sdk.events.game_api_resume()")
    page.wait_for_timeout(1800)
    page.locator('canvas').focus()
    page.keyboard.press('Control+s')
    current=await_world(lambda value: value['ticks']>frozen['ticks'])
    assert current['ticks']>frozen['ticks'], 'SDK resume advances simulation'
    checks += 1
    page.keyboard.press('Space')
    page.evaluate("window.LittleWorldsPlatform.rewarded()")
    page.evaluate("window.__sdk.callbacks.onRewarded();window.__sdk.callbacks.onRewarded();window.__sdk.callbacks.onClose()")
    page.wait_for_timeout(500)
    page.locator('canvas').focus()
    page.keyboard.press('Control+s')
    rewarded=await_world(lambda value: any(event['title']=='Живительный дождь' for event in value['history']))
    assert sum(event['title']=='Живительный дождь' for event in rewarded['history'])==1, 'duplicate callbacks produce one actual reward'
    checks += 1
    encoded=base64.b64encode(gzip.compress(json.dumps(frozen,ensure_ascii=False).encode())).decode()
    page.evaluate('(data)=>window.LittleWorldsPlatform.save(data)', encoded)
    page.wait_for_function('typeof window.__sdk.data.littleWorldsV7 === "string"',timeout=5000)
    page.evaluate('window.LittleWorldsPlatform.load()')
    page.wait_for_timeout(800)
    page.locator('canvas').focus()
    page.keyboard.press('Control+s')
    cloud=await_world(lambda value: value['ticks']==frozen['ticks'] and value['people']==frozen['people'])
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
    page.evaluate('(data)=>{window.__sdk.data.littleWorldsV7=data;return window.LittleWorldsPlatform.load()}',encoded)
    page.wait_for_timeout(1500)
    page.locator('canvas').focus()
    page.keyboard.press('Control+s')
    current=await_world(lambda value: len(value['people'])==2000, timeout=90)
    assert len(current['people'])==2000 and current['people']==large['people'], 'WASM restores 2000 individual people with their work and families'
    checks+=1
    page.keyboard.press('Space')
    page.wait_for_timeout(1000)
    page.locator('canvas').focus()
    page.keyboard.press('Control+s')
    current=await_world(lambda value: value['ticks']>large['ticks'], timeout=90)
    page.keyboard.press('Space')
    assert current['ticks']>large['ticks'] and len(current['people'])==2000, 'WASM advances a full population and commits its v9 snapshot'
    checks+=1
    assert not errors,json.dumps(errors,ensure_ascii=False)
    checks+=1
    page.screenshot(path=str(output/'world-web-population-2000.png'))
    browser.close()
print(f'Web SDK: {checks} checks, 0 failures; actual bridge readiness, pause/resume, one reward, cloud restore and 2000-person WASM simulation; no console errors.')
