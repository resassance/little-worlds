
import json
import time
from io import BytesIO
from PIL import Image
from pathlib import Path
from playwright.sync_api import sync_playwright

artifacts = Path(__file__).resolve().parents[1] / 'artifacts'
errors = []


persisted_world = """async (expected) => {
    const db = await new Promise((resolve, reject) => {
        const request = indexedDB.open('/userfs');
        request.onsuccess = () => resolve(request.result);
        request.onerror = () => reject(request.error);
    });
    try {
        if (!db.objectStoreNames.contains('FILE_DATA')) return false;
        const store = db.transaction('FILE_DATA', 'readonly').objectStore('FILE_DATA');
        const keysRequest = store.getAllKeys(), valuesRequest = store.getAll();
        const read = request => new Promise((resolve, reject) => {
            request.onsuccess = () => resolve(request.result);
            request.onerror = () => reject(request.error);
        });
        const [keys, values] = await Promise.all([read(keysRequest), read(valuesRequest)]);
        const index = keys.findIndex(key => key.endsWith('/world.json'));
        if (index < 0 || !values[index].contents) return false;
        const data = JSON.parse(new TextDecoder().decode(values[index].contents));
        if (!data.regions || data.version !== 10 || !data.households || !data.ancestry_archive || !data.societies) return false;
        if (expected && !data.regions.some(r => r.x === expected[0] && r.y === expected[1])) return false;
        const directory = keys[index] + '.regions/';
        if (!data.regions.every(r => keys.includes(directory + r.file))) return false;
        return data;
    } catch (_) { return false; }
    finally { db.close(); }
}"""
with sync_playwright() as p:
    browser = p.chromium.launch(executable_path='/usr/bin/chromium', headless=True,
        args=['--no-sandbox', '--enable-unsafe-swiftshader', '--disable-dev-shm-usage'])
    page = browser.new_page(viewport={'width': 1280, 'height': 800}, device_scale_factor=1)
    def await_persisted(expected=None):
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            data = page.evaluate(persisted_world, expected)
            if isinstance(data, dict):
                return data
            page.wait_for_timeout(200)
        raise AssertionError(f'Complete save was not committed to IndexedDB: {expected}; console: {errors}')
    page.on('pageerror', lambda error: errors.append(str(error)))
    page.on('console', lambda message: errors.append(message.text) if message.type == 'error' else None)
    page.goto('http://127.0.0.1:8000', wait_until='domcontentloaded', timeout=60000)
    page.wait_for_function("!document.getElementById('status')", timeout=60000)
    page.wait_for_timeout(4500)
    page.keyboard.press('Space')
    page.screenshot(path=str(artifacts / 'world-web.png'))
    page.mouse.click(90, 762)
    page.wait_for_timeout(350)
    page.screenshot(path=str(artifacts / 'world-web-tools.png'))
    page.keyboard.press('Escape')
    page.wait_for_timeout(350)
    before = Image.open(BytesIO(page.screenshot())).getpixel((40, 22))
    page.keyboard.press('Tab')
    page.wait_for_timeout(200)
    clean = Image.open(BytesIO(page.screenshot())).getpixel((40, 22))
    assert before != clean, 'Tab should hide the menu button'
    page.screenshot(path=str(artifacts / 'world-web-clean.png'))
    page.keyboard.press('Tab')
    page.wait_for_timeout(200)
    restored = Image.open(BytesIO(page.screenshot())).getpixel((40, 22))
    assert restored == before, 'Tab should restore the HUD'
    page.mouse.click(1190, 762)
    page.wait_for_timeout(200)
    page.screenshot(path=str(artifacts / 'world-web-closeup.png'))
    page.keyboard.press('Control+s')
    first_save = await_persisted()
    assert any(person['task'] for person in first_save['people']), 'Save should include active worker tasks'
    assert all(set(person['skills']) == {'food', 'wood', 'build', 'farm'} and
               set(person['traits']) == {'sociability', 'diligence', 'curiosity'} and
               isinstance(person['links'], list) and isinstance(person['lesson'], dict)
               and isinstance(person['ideas'], list)
               for person in first_save['people']), 'Web save includes skills, personality, friendships and lessons'
    assert {society['town'] for society in first_save['societies']} == {town['id'] for town in first_save['towns']}, 'Every Web settlement has its own society'
    assert all(set(society['tech']) == {'preservation','carpentry','rotation','records','stonework','ceramics','weaving','metallurgy','governance','navigation','sailing'}
               and set(society['practice']) == {'food', 'wood', 'build', 'farm'}
               and isinstance(society['choice_rng'], int) and len(society['domain_practice']) == 12
               and all(isinstance(state['threshold'], (int, float)) and isinstance(state['spent'], bool)
                       for state in society['tech'].values()) for society in first_save['societies']), 'Web save preserves independent directions, project randomness and paid experiments'
    page.keyboard.press('Control+l')
    page.wait_for_timeout(1000)
    page.screenshot(path=str(artifacts / 'world-web-save.png'))
    def travel(x, y):
        page.keyboard.press('g')
        page.wait_for_timeout(250)
        page.mouse.click(535, 400)
        page.keyboard.press('Control+a')
        page.keyboard.type(str(x))
        page.mouse.click(735, 400)
        page.keyboard.press('Control+a')
        page.keyboard.type(str(y))
        page.mouse.click(720, 500)
        page.wait_for_timeout(700)
        page.mouse.move(40, 30)

    travel(-600000, 700000)
    ocean = Image.open(BytesIO(page.screenshot())).getpixel((642, 402))
    page.keyboard.press('t')
    page.wait_for_timeout(350)
    page.mouse.click(63, 346)
    page.keyboard.press('Escape')
    page.wait_for_timeout(350)
    page.mouse.click(640, 400)
    page.mouse.move(40, 30)
    page.wait_for_timeout(1200)
    forest = Image.open(BytesIO(page.screenshot())).getpixel((642, 402))
    deadline = time.monotonic() + 8
    while forest == ocean and time.monotonic() < deadline:
        page.wait_for_timeout(150)
        forest = Image.open(BytesIO(page.screenshot())).getpixel((642, 402))
    assert forest != ocean, 'Painting should create land in distant ocean'
    page.screenshot(path=str(artifacts / 'world-web-distant.png'))
    page.keyboard.press('Control+s')
    far_save = await_persisted([-18750, 21875])
    assert far_save['people'] == first_save['people'], 'Painting distant land must preserve paused worker tasks and cargo'
    assert far_save['societies'] == first_save['societies'], 'Distant painting must preserve paused local ideas, research and eras'
    page.reload(wait_until='domcontentloaded')
    page.wait_for_function("!document.getElementById('status')", timeout=60000)
    page.wait_for_timeout(3500)
    page.keyboard.press('Space')
    travel(-600000, 700000)
    restored_forest = Image.open(BytesIO(page.screenshot())).getpixel((642, 402))
    assert restored_forest == forest, (forest, restored_forest, 'Remote land must survive browser reload')
    page.screenshot(path=str(artifacts / 'world-web-restored.png'))
    travel(64, 64)

    page.set_viewport_size({'width': 844, 'height': 480})
    page.wait_for_timeout(500)
    page.screenshot(path=str(artifacts / 'world-web-mobile.png'))
    dimensions = page.locator('canvas').evaluate('(c) => ({width:c.width, height:c.height})')
    assert dimensions == {'width':844, 'height':480}, dimensions
    assert not errors, json.dumps(errors, ensure_ascii=False)
    print('Web: Chromium launch, drawers, camera, resize, v10 save/load with local societies and technologies, distant painting without canceling work or resetting knowledge, complete IndexedDB commit and land persistence across page reload; no console errors.')
    browser.close()
