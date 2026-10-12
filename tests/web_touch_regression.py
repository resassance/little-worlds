from pathlib import Path
from io import BytesIO
from PIL import Image
from playwright.sync_api import sync_playwright

errors = []
output = Path(__file__).resolve().parents[1] / 'artifacts'
with sync_playwright() as engine:
    browser = engine.chromium.launch(executable_path='/usr/bin/chromium', headless=True, args=['--no-sandbox', '--enable-unsafe-swiftshader', '--disable-dev-shm-usage'])
    for width, height, density in [(960, 480, 2.25), (360, 800, 3)]:
        context = browser.new_context(viewport={'width': width, 'height': height}, device_scale_factor=density, is_mobile=True, has_touch=True)
        page = context.new_page()
        page.on('pageerror', lambda error: errors.append(str(error)))
        page.on('console', lambda message: errors.append(message.text) if message.type == 'error' else None)
        page.goto('http://127.0.0.1:8000', wait_until='domcontentloaded', timeout=60000)
        page.wait_for_function("!document.getElementById('status')", timeout=60000)
        page.wait_for_timeout(3000)
        page.keyboard.press('Space')
        page.wait_for_timeout(300)
        def shot():
            return Image.open(BytesIO(page.screenshot())).convert('RGB')
        def pixel(image, x, y):
            return image.getpixel((round(x * density), round(y * density)))
        original = shot()
        page.touchscreen.tap(60, height - 36)
        page.wait_for_timeout(400)
        assert pixel(shot(), 40, 90) != pixel(original, 40, 90), 'Touch opens the drawer'
        page.touchscreen.tap(100, 230)
        page.wait_for_timeout(300)
        assert pixel(shot(), 40, 380) != pixel(original, 40, 380), 'Touch opens the actual group popup'
        page.touchscreen.tap(100, 336)
        page.wait_for_timeout(400)
        assert pixel(shot(), 200, 440)[1] > 60, 'Selecting Life dismisses the popup and exposes the map below the drawer'
        page.touchscreen.tap(60, height - 36)
        page.wait_for_timeout(400)
        assert pixel(shot(), 14, 90)[1] > 60, 'Drawer button responds after selecting a popup item'
        page.touchscreen.tap(60, height - 36)
        page.wait_for_timeout(400)
        page.touchscreen.tap(100, 230)
        page.wait_for_timeout(250)
        page.touchscreen.tap(width - 6, 380)
        page.wait_for_timeout(250)
        page.touchscreen.tap(60, height - 36)
        page.wait_for_timeout(350)
        assert pixel(shot(), 14, 90)[1] > 60, 'Outside touch releases the popup input grab'
        page.screenshot(path=str(output / f'web-touch-preview-{width}x{height}.png'))
        assert not errors, errors
        context.close()
    browser.close()
print('Web touch regression: popup selection, outside dismissal and subsequent controls respond at two mobile densities')
