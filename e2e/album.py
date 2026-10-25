import asyncio, sys, json, subprocess
sys.path.insert(0,'/workspace/e2e')
from lib import *
from PIL import Image, ImageChops
def imdiff(a,b,box=None):
    A=Image.open(S+a).convert('L'); B=Image.open(S+b).convert('L')
    if box: A=A.crop(box); B=B.crop(box)
    return sum(ImageChops.difference(A,B).point(lambda v:255 if v>30 else 0).histogram()[255:])
async def main():
    async with async_playwright() as p:
        b, app = await launch(p)
        await app.upload('Gallery', ['/workspace/test_imgs/doc.jpg','/workspace/test_imgs/sunset.jpg']); await app.wait(4000)
        await app.click('Highlight', exact=True, wait=5000); await app.drag(60,40,250,72); await app.click('Done', wait=5000)
        n1,_=await app.download_click('Save & Album'); await app.wait(1500)
        await app.click('Vertical', wait=2500); n2,_=await app.download_click('Save & Album'); await app.wait(1500)
        rec('Save twice -> two album items', True, f'{n1}, {n2}')
        # menu
        await app.click('⋮', exact=True, wait=900); await app.shot('flutter_menu_390.png')
        rec('⋮ menu opens', await app.find('In-App Album', role='') is not None)
        await app.click('In-App Album', role='', wait=1500); await app.shot('flutter_album_390.png'); await app.dump('/workspace/e2e/album_nodes.json')
        cnt=await app.count('🗑️ Delete'); rec('Album lists saved items', cnt==2, f'items={cnt}')
        t=await app.text_of('Album ('); rec('Album count header', t is not None, str(t))
        # image viewer: click first card image (above Edit button)
        e=await app.find('✏️ Edit'); await app.pg.mouse.click(e['x']+60, e['y']-90); await app.wait(1500)
        await app.shot('flutter_viewer_390.png')
        rec('Full image viewer (Hero)', imdiff('flutter_album_390.png','flutter_viewer_390.png')>20000)
        await app.pg.mouse.move(195,420); await app.pg.mouse.wheel(0,-300); await app.wait(600); await app.shot('_v_zoom.png')
        rec('Viewer zoom (InteractiveViewer)', imdiff('flutter_viewer_390.png','_v_zoom.png')>3000)
        await app.dump('/workspace/e2e/viewer_nodes.json')
        await app.pg.keyboard.press('Escape'); await app.wait(300)
        closeb=[x for x in await app.nodes() if x['role']=='button' and ('✕' in x['label'] or 'Close' in x['label'] or 'Back' in x['label'])]
        if not await app.find('✏️ Edit'):
            if closeb: c=closeb[0]; await app.pg.mouse.click(c['x']+c['w']/2,c['y']+c['h']/2)
            else: await app.pg.go_back()
            await app.wait(1200)
        rec('Viewer close returns to album', await app.find('✏️ Edit') is not None)
        # share (fallback download in headless)
        try:
            n,_=await app.download_click('📤 Share', timeout=10000); rec('Share (web fallback = download)', True, n)
        except Exception as ex: rec('Share (web fallback = download)', False, str(ex)[:100])
        await app.wait(800)
        try:
            n,pth=await app.download_click('Export All PDF', timeout=30000)
            pg=int([l for l in subprocess.run(['pdfinfo',pth],capture_output=True,text=True).stdout.splitlines() if l.startswith('Pages:')][0].split()[-1])
            rec('Export All PDF', pg==2, f'{n} pages={pg}')
        except Exception as ex: rec('Export All PDF', False, str(ex)[:100])
        # delete with confirm
        await app.click('🗑️ Delete', nth=1, wait=900); await app.shot('flutter_confirm_delete_390.png')
        await app.click('OK', exact=True, wait=1500)
        cnt=await app.count('🗑️ Delete'); rec('Delete album item (confirm)', cnt==1, f'items={cnt}')
        # edit -> restores project
        await app.click('✏️ Edit', wait=4000); await app.shot('_a_edit.png')
        n=await app.count('Scan', exact=True); rec('Edit from album restores editable project', n==2, f'thumbs={n}')
        await app.click('Highlight', exact=True, wait=5000); await app.click('Layers', wait=900)
        lc=len([x for x in await app.nodes() if x['role']=='button' and x['label'].strip()=='×'])
        rec('Restored project keeps highlight layers', lc==1, f'layers={lc}')
        await app.click('Cancel', exact=True, wait=2000)
        # theme toggle
        await app.click('Theme', wait=250); await app.shot('flutter_theme_crossfade_mid_390.png'); await app.wait(1200)
        await app.shot('flutter_light_390.png'); rec('Theme toggle (cross-fade) -> light', imdiff('_a_edit.png','flutter_light_390.png')>50000)
        ls=await app.pg.evaluate("localStorage.getItem('flutter.app_theme_mode')"); rec('Theme persisted (app_theme_mode)', ls is not None and 'light' in ls, str(ls))
        await app.pg.reload(wait_until='networkidle'); await app.wait(5000); await app.shot('_a_reload_light.png')
        px=Image.open(S+'_a_reload_light.png').convert('RGB').getpixel((20,300)); rec('Theme restored after reload', sum(px)>500, str(px))
        await app.pg.evaluate("document.querySelector('flt-semantics-placeholder')?.click()"); await app.wait(1200)
        # menu in light, switch theme via menu, reset dialog
        await app.click('⋮', exact=True, wait=900); await app.shot('flutter_menu_light_390.png')
        await app.click('Switch Theme', role='', wait=1500); await app.shot('_a_dark.png')
        px=Image.open(S+'_a_dark.png').convert('RGB').getpixel((20,300)); rec('Menu → Switch Theme', sum(px)<300, str(px))
        await app.upload('Gallery', ['/workspace/test_imgs/ocean.jpg']); await app.wait(3000)
        await app.click('⋮', exact=True, wait=900); await app.click('Reset / Reload', role='', wait=900); await app.shot('flutter_reset_confirm_390.png')
        rec('Reset confirm dialog "App ko Restart Kare?"', await app.find('App ko Restart Kare?', role='') is not None)
        await app.click('OK', exact=True, wait=6000)
        await app.pg.evaluate("document.querySelector('flt-semantics-placeholder')?.click()"); await app.wait(1500)
        n=await app.count('Scan', exact=True); rec('Reset/Reload clears images', n==0, f'thumbs={n}')
        rec('No page/console errors (album/theme)', not app.errors, '; '.join(app.errors)[:300])
        await b.close()
        json.dump(RESULTS, open('/workspace/e2e/res_album.json','w'), ensure_ascii=False)
asyncio.run(main())
