from pathlib import Path
from playwright.sync_api import sync_playwright
from PIL import Image
from io import BytesIO

artifacts=Path(__file__).resolve().parents[1]/'artifacts'
errors=[]
checks=0
with sync_playwright() as p:
    browser=p.chromium.launch(executable_path='/usr/bin/chromium',headless=True,args=['--no-sandbox','--enable-unsafe-swiftshader','--disable-dev-shm-usage'])
    for width,height,density in [(640,360,3),(360,800,3),(960,480,2.25)]:
        context=browser.new_context(viewport={'width':width,'height':height},device_scale_factor=density,is_mobile=True,has_touch=True)
        page=context.new_page()
        page.on('pageerror',lambda e: errors.append(str(e)))
        page.on('console',lambda m: errors.append(m.text) if m.type=='error' else None)
        page.goto('http://127.0.0.1:8000',wait_until='domcontentloaded',timeout=60000)
        page.wait_for_function("!document.getElementById('status')",timeout=60000)
        page.wait_for_timeout(3500)
        page.screenshot(path=str(artifacts/f'web-phone-{width}x{height}.png'))
        image=Image.open(BytesIO(page.screenshot()))
        assert image.size==(round(width*density),round(height*density))
        checks+=1
        menu_pixel=image.getpixel((round(22*density),round(35*density)))[:3]
        assert max(abs(a-b) for a,b in zip(menu_pixel,(231,216,182)))<4,f'World menu is correctly scaled at system density: {menu_pixel}'
        checks+=1
        page.touchscreen.tap(60,height-36)
        page.wait_for_timeout(450)
        tools=Image.open(BytesIO(page.screenshot()))
        assert tools.getpixel((round(22*density),round(90*density)))!=image.getpixel((round(22*density),round(90*density))),'Touch opens the tools drawer'
        checks+=1
        page.screenshot(path=str(artifacts/f'web-phone-tools-{width}x{height}.png'))
        page.touchscreen.tap(298 if width>=420 else width-52,110)
        page.wait_for_timeout(450)
        page.touchscreen.tap(55,35)
        page.wait_for_timeout(300)
        page.screenshot(path=str(artifacts/f'web-phone-menu-{width}x{height}.png'))
        assert not errors,errors
        checks+=1
        context.close()
    browser.close()
print(f'Web mobile: {checks} checks, 0 failures')
