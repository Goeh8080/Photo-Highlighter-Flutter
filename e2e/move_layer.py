import asyncio, sys
sys.path.insert(0,'/workspace/e2e')
from lib import *
from PIL import Image, ImageChops
def band_diff(a,b,y0,y1):
    A=Image.open(S+a).convert('L').crop((0,y0*2,780,y1*2)); B=Image.open(S+b).convert('L').crop((0,y0*2,780,y1*2))
    return sum(ImageChops.difference(A,B).point(lambda v:255 if v>20 else 0).histogram()[255:])
async def layers(app):
    await app.click('Layers', wait=700)
    n=len([x for x in await app.nodes() if x['role']=='button' and x['label'].strip()=='×'])
    await app.click('Layers', wait=500); return n
async def snap(app,name):
    await app.pg.mouse.click(75,350); await app.wait(500)   # empty tap in Select/Move only deselects
    await app.shot(name)
async def main():
    async with async_playwright() as p:
        b, app = await launch(p)
        await app.upload('Gallery', ['/workspace/test_imgs/doc.jpg']); await app.wait(4000)
        await app.click('Highlight', exact=True, wait=5000)
        await app.shot('_m0.png')
        await app.drag(60,40,250,72); await app.drag(60,130,250,162); await app.drag(60,220,250,252)
        await app.shot('_m1.png')
        rec('3 shapes drawn', await layers(app)==3, f'layers={await layers(app)}')
        # explicit liquid-glass Select / Move tool
        await app.click('Select / Move', wait=900)
        await snap(app,'_m2.png')
        # drag the middle shape by (+40,+0) with a single finger, starting on its body
        await app.drag(150,146,190,146, steps=10)
        await snap(app,'_m3.png')
        mid=band_diff('_m2.png','_m3.png',120,175); top=band_diff('_m2.png','_m3.png',25,85); bot=band_diff('_m2.png','_m3.png',210,262)
        rec('Middle layer moved', mid>1500, f'mid_px={mid}')
        rec('Top layer untouched', top<60, f'top_px={top}')
        rec('Bottom layer untouched', bot<60, f'bot_px={bot}')
        rec('Still 3 layers', await layers(app)==3)
        # undo reverts only the move
        await app.click('Undo', exact=True, wait=800); await snap(app,'_m4.png')
        rec('Undo restores middle position', band_diff('_m2.png','_m4.png',120,175)<200, f'px={band_diff("_m2.png","_m4.png",120,175)}')
        rec('Undo keeps 3 layers', await layers(app)==3)
        await app.click('Redo', exact=True, wait=800); await snap(app,'_m5.png')
        rec('Redo re-applies move', band_diff('_m3.png','_m5.png',120,175)<200)
        # Drag from the top layer next: only top moves
        await app.drag(150,56,150,90, steps=10); await snap(app,'_m6.png')
        rec('Dragging top moves only top', band_diff('_m5.png','_m6.png',25,100)>1000 and band_diff('_m5.png','_m6.png',210,262)<60 and band_diff('_m5.png','_m6.png',150,175)<400,
            f'top={band_diff("_m5.png","_m6.png",25,100)} bot={band_diff("_m5.png","_m6.png",210,262)}')
        # Drawing still works after leaving the Select tool
        await app.click('Select / Move', wait=700)
        await app.drag(60,300,250,330); await app.shot('_m7.png')
        rec('Drawing works again after leaving Select/Move', await layers(app)==4, f'layers={await layers(app)}')
        errs=[e for e in app.errors if 'Exception' in e or 'Error' in e]
        rec('No page errors', not errs, str(errs[:2]))
        await b.close()
    bad=[r for r in RESULTS if r[1]!='PASS']; print('\nTOTAL',len(RESULTS),'FAIL',len(bad)); sys.exit(1 if bad else 0)
asyncio.run(main())
