import asyncio, json, re, time
from playwright.async_api import async_playwright
S='/workspace/html_to_flutter/screenshots/'
DL='/workspace/e2e/downloads/'
RESULTS=[]
def rec(name, ok, note=''):
    RESULTS.append((name, 'PASS' if ok else 'FAIL', note)); print(('PASS' if ok else 'FAIL'), name, note, flush=True)

class App:
    def __init__(s, pg): s.pg=pg; s.errors=[]
    async def nodes(s):
        return await s.pg.evaluate("""[...document.querySelectorAll('flt-semantics')].map(e=>{const r=e.getBoundingClientRect();return {role:e.getAttribute('role')||'',label:(e.getAttribute('aria-label')||[...e.childNodes].filter(n=>n.nodeType==3).map(n=>n.textContent).join('')||e.textContent||'').replace(/\\n/g,' '),x:r.x,y:r.y,w:r.width,h:r.height}}).filter(n=>n.w>0&&n.h>0)""")
    async def find(s, text, role='button', nth=0, exact=False):
        ns=[n for n in await s.nodes() if (not role or n['role']==role) and ((n['label'].strip()==text) if exact else (text in n['label']))]
        # prefer smallest (most specific)
        ns.sort(key=lambda n:(n['w']*n['h']) if not role else (n['y'],n['x']))
        return ns[nth] if len(ns)>nth else None
    async def count(s, text, role='button', exact=False):
        return len([n for n in await s.nodes() if (not role or n['role']==role) and ((n['label'].strip()==text) if exact else (text in n['label']))])
    async def click(s, text, role='button', nth=0, exact=False, wait=700):
        n=await s.find(text, role, nth, exact)
        if not n: raise Exception(f'not found: {text}')
        await s.pg.mouse.click(n['x']+n['w']/2, n['y']+n['h']/2); await s.pg.wait_for_timeout(wait); return n
    async def text_of(s, prefix):
        for n in await s.nodes():
            m=re.search(re.escape(prefix)+r'[^🖼]*?(?=  |$)', n['label'])
            if n['label'].startswith(prefix): return n['label']
        for n in await s.nodes():
            if prefix in n['label']:
                i=n['label'].index(prefix); return n['label'][i:i+60]
        return None
    async def shot(s, name): await s.pg.screenshot(path=S+name)
    async def wait(s, ms): await s.pg.wait_for_timeout(ms)
    async def wait_for(s, text, role='', timeout=20000):
        t=time.time()
        while time.time()-t<timeout/1000:
            if await s.find(text, role): return True
            await s.pg.wait_for_timeout(300)
        return False
    async def wait_gone(s, text, role='', timeout=20000):
        t=time.time()
        while time.time()-t<timeout/1000:
            if not await s.find(text, role): return True
            await s.pg.wait_for_timeout(300)
        return False
    async def download_click(s, text, nth=0, timeout=30000):
        n=await s.find(text,'button',nth)
        async with s.pg.expect_download(timeout=timeout) as d:
            await s.pg.mouse.click(n['x']+n['w']/2, n['y']+n['h']/2)
        dv=await d.value; p=DL+dv.suggested_filename; await dv.save_as(p); return dv.suggested_filename, p
    async def upload(s, btn_text, files, tries=6):
        for k in range(tries):
            n=await s.find(btn_text)
            try:
                async with s.pg.expect_file_chooser(timeout=7000) as fc:
                    await s.pg.mouse.click(n['x']+n['w']/2, n['y']+n['h']/2)
                await (await fc.value).set_files(files); return k
            except Exception:
                print('retry upload', btn_text); await s.pg.wait_for_timeout(800)
        raise Exception('file chooser never opened for '+btn_text)
    async def drag(s, x0,y0,x1,y1, steps=12):
        await s.pg.mouse.move(x0,y0); await s.pg.mouse.down()
        await s.pg.mouse.move(x1,y1,steps=steps); await s.pg.mouse.up(); await s.pg.wait_for_timeout(300)
    async def dump(s, path):
        open(path,'w').write(json.dumps(await s.nodes(),ensure_ascii=False,indent=0))

async def launch(p, w=390, h=844, dsf=2):
    b = await p.chromium.launch(executable_path='/usr/bin/google-chrome', args=['--no-sandbox','--use-angle=swiftshader','--enable-unsafe-swiftshader'])
    ctx = await b.new_context(viewport={'width':w,'height':h}, device_scale_factor=dsf, accept_downloads=True)
    pg = await ctx.new_page()
    app=App(pg)
    pg.on('pageerror', lambda e: (app.errors.append(str(e)), print('PAGEERROR', e)))
    pg.on('console', lambda m: (app.errors.append(m.text), print('CONSOLE', m.text)) if m.type=='error' else None)
    await pg.goto('http://127.0.0.1:8812/', wait_until='networkidle'); await pg.wait_for_timeout(4500)
    await pg.evaluate("document.querySelector('flt-semantics-placeholder')?.click()"); await pg.wait_for_timeout(1200)
    return b, app
