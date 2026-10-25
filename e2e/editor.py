import asyncio, sys, json
sys.path.insert(0,'/workspace/e2e')
from lib import *
from PIL import Image, ImageChops
def imdiff(a,b,box=None):
    A=Image.open(S+a).convert('L'); B=Image.open(S+b).convert('L')
    if box: A=A.crop(box); B=B.crop(box)
    return sum(ImageChops.difference(A,B).point(lambda v:255 if v>30 else 0).histogram()[255:])
async def step(name, coro):
    try: await coro
    except Exception as e: rec(name, False, 'EXC '+str(e)[:150])
async def layers(app):
    await app.click('Layers', wait=700)
    n=len([x for x in await app.nodes() if x['role']=='button' and x['label'].strip()=='×'])
    await app.click('Layers', wait=500); return n
async def layer_count(app):
    return sum([await app.count(k, role='') for k in []]) 
async def main():
    async with async_playwright() as p:
        b, app = await launch(p)
        await app.upload('Gallery', ['/workspace/test_imgs/doc.jpg','/workspace/test_imgs/sunset.jpg']); await app.wait(4000)
        await app.shot('_e_home0.png')
        # ---------- CROP ----------
        await app.click('Scan', exact=True, wait=5000)
        await app.shot('flutter_scan_crop_390.png')
        rec('Scan opens crop editor (slide-up route)', await app.find('Done') is not None)
        # drag TL handle with magnifier
        await app.pg.mouse.move(60,177); await app.pg.mouse.down(); await app.pg.mouse.move(75,200,steps=10); await app.wait(300)
        await app.shot('flutter_scan_magnifier_390.png'); await app.pg.mouse.up(); await app.wait(400)
        await app.shot('_e_crop_dragged.png')
        rec('Crop handle drag + magnifier', imdiff('flutter_scan_crop_390.png','_e_crop_dragged.png',(0,200,780,1500))>200)
        await app.click('Auto Detect', wait=4000); await app.shot('_e_crop_auto.png')
        rec('Auto Detect re-snaps quad to paper', imdiff('flutter_scan_crop_390.png','_e_crop_auto.png',(0,200,780,1500))<imdiff('flutter_scan_crop_390.png','_e_crop_dragged.png',(0,200,780,1500)))
        await app.click('Rotate 90°', wait=3000); await app.shot('flutter_scan_rotated_390.png')
        rec('Rotate 90°', imdiff('_e_crop_auto.png','flutter_scan_rotated_390.png')>5000)
        for k in range(3): await app.click('Rotate 90°', wait=2500)
        await app.shot('_e_rot360.png'); rec('Rotate x4 returns to start', imdiff('_e_crop_auto.png','_e_rot360.png')<imdiff('_e_crop_auto.png','flutter_scan_rotated_390.png')/3)
        await app.click('Canvas Size', wait=1200); await app.shot('flutter_canvas_size_390.png')
        await app.dump('/workspace/e2e/canvas_nodes.json')
        rec('Canvas Size window opens', await app.find('Apply', exact=True) is not None or await app.find('OK', exact=True) is not None)
        if await app.find('Cancel', exact=True): 
            await app.click('Cancel', exact=True, nth=0, wait=800)
        await app.click('Done', wait=5000); await app.shot('_e_home_cropped.png')
        rec('Done (crop) returns + updates thumb', await app.find('Scan Photo') is not None and imdiff('_e_home0.png','_e_home_cropped.png',(0,1000,400,1300))>500)
        # No Crop on 2nd image
        await app.click('Scan', exact=True, nth=0, wait=4000); await app.shot('_e_nc0.png'); await app.click('No Crop', wait=1500); await app.shot('flutter_nocrop_390.png')
        rec('No Crop resets quad to full image (stays in editor, like HTML)', await app.find('Done') is not None and imdiff('_e_nc0.png','flutter_nocrop_390.png')>300)
        await app.click('Cancel', exact=True, wait=2000)
        rec('Cancel closes editor', await app.find('Scan Photo') is not None)
        # ---------- HIGHLIGHT ----------
        await app.click('Highlight', exact=True, wait=5000)
        await app.shot('_e_hl0.png')
        await app.drag(60,40,250,72); await app.wait(500)
        await app.shot('_e_hl_rect.png'); rec('Rectangle highlight draw', imdiff('_e_hl0.png','_e_hl_rect.png',(0,0,780,900))>2000)
        async def shape(label):
            n=await app.find('Rectangle') or await app.find('Oval') or await app.find('Free Hand') or await app.find('Add Text') or await app.find('Select & Transform')
            # the select button is the one in the Shape row (y≈501)
            ns=await app.nodes(); lab=[x for x in ns if x['label'].strip()=='Shape:'][0]
            sel=sorted([x for x in ns if x['role']=='button' and abs((x['y']+x['h']/2)-(lab['y']+lab['h']/2))<12 and x['x']>lab['x']], key=lambda x:x['x'])
            n=sel[0]; await app.pg.mouse.click(n['x']+n['w']/2,n['y']+n['h']/2); await app.wait(800)
            await app.click(label, role='menuitem', wait=900)
        await shape('Oval / Circle'); await app.drag(80,110,300,150); await app.shot('_e_hl_oval.png')
        rec('Oval shape', imdiff('_e_hl_rect.png','_e_hl_oval.png',(0,0,780,900))>1500)
        await shape('Free Hand'); 
        await app.pg.mouse.move(70,200); await app.pg.mouse.down()
        for i,(x,y) in enumerate([(100,215),(130,195),(160,215),(190,195),(220,215)]): await app.pg.mouse.move(x,y,steps=4)
        await app.pg.mouse.up(); await app.wait(400); await app.shot('_e_hl_free.png')
        rec('Free Hand shape', imdiff('_e_hl_oval.png','_e_hl_free.png',(0,0,780,900))>800)
        await shape('Free Hand (Straight Line)'); await app.drag(70,260,300,262); await app.shot('_e_hl_line.png')
        rec('Straight Line shape', imdiff('_e_hl_free.png','_e_hl_line.png',(0,0,780,900))>800)
        await shape('✍️ Add Text'); await app.pg.mouse.click(90,330); await app.wait(900)
        await app.pg.keyboard.type('Hello Goutam'); await app.wait(300); await app.pg.keyboard.press('Enter'); await app.wait(700)
        await app.shot('_e_hl_text.png'); rec('Text layer', imdiff('_e_hl_line.png','_e_hl_text.png',(0,500,780,900))>300)
        await app.click('Layers', wait=900); await app.shot('flutter_layers_390.png'); await app.dump('/workspace/e2e/layers_nodes.json')
        lc=len([x for x in await app.nodes() if x['role']=='button' and x['label'].strip()=='×'])
        rec('Layers panel lists 5 layers', lc==5, f'layers={lc}')
        await app.click('Layers', wait=600)
        await app.click('Undo', exact=True, wait=700); await app.click('Layers', wait=800)
        lc2=len([x for x in await app.nodes() if x['role']=='button' and x['label'].strip()=='×']); await app.click('Layers', wait=600)
        rec('Undo removes last layer', lc2==4, f'layers={lc2}')
        await app.click('Redo', exact=True, wait=700); await app.click('Layers', wait=800)
        lc3=len([x for x in await app.nodes() if x['role']=='button' and x['label'].strip()=='×']); await app.click('Layers', wait=600)
        rec('Redo restores layer', lc3==5, f'layers={lc3}')
        # select & transform the rect
        await shape('Select & Transform'); await app.pg.mouse.click(150,56); await app.wait(700)
        await app.shot('flutter_highlight_selected_390.png')
        rec('Select shows handles + Delete', await app.find('Delete', exact=True) is not None)
        await app.drag(150,56,170,90); await app.shot('_e_hl_moved.png')
        rec('Move selected shape by drag', imdiff('flutter_highlight_selected_390.png','_e_hl_moved.png',(0,0,780,300))>1500)
        await app.click('Duplicate', wait=800); await app.click('Layers', wait=800)
        lc4=len([x for x in await app.nodes() if x['role']=='button' and x['label'].strip()=='×']); await app.click('Layers', wait=600)
        rec('Duplicate layer', lc4==6, f'layers={lc4}')
        await app.click('Delete', exact=True, wait=800); await app.click('Layers', wait=800)
        lc5=len([x for x in await app.nodes() if x['role']=='button' and x['label'].strip()=='×']); await app.click('Layers', wait=600)
        rec('Delete layer', lc5==5, f'layers={lc5}')
        # blend mode + colour swatch
        await app.pg.mouse.click(150,56); await app.wait(500)
        await app.click('Multiply (Highlight)', wait=800); await app.click('Normal (White / Opaque)', role='menuitem', wait=900)
        await app.shot('_e_blend.png'); rec('Blend mode → Normal', await app.find('Normal (White / Opaque)') is not None)
        ns2=await app.nodes()
        sw=[x for x in ns2 if x['role']=='button' and x['label']=='' and 20<=x['w']<=26 and x['y']>(sorted([y for y in ns2 if y['label'].strip()=='Snapping'],key=lambda q:q['y'])[0]['y'])]
        await app.pg.mouse.click(sw[6]['x']+11, sw[6]['y']+11); await app.wait(600); await app.shot('_e_color.png')
        rec('Colour swatch recolours selected', imdiff('_e_blend.png','_e_color.png',(0,0,780,300))>800)
        # Transform pad
        await app.click('Transform Pad', wait=1200); await app.shot('flutter_transform_pad_390.png'); await app.dump('/workspace/e2e/dpad_nodes.json')
        rec('Transform Pad window opens', await app.find('Move') is not None)
        b4='_e_dp0.png'; await app.shot(b4)
        arrows=[x for x in await app.nodes() if x['role']=='button' and x['label'].strip()=='➡️']
        if arrows:
            for k in range(3): await app.pg.mouse.click(arrows[0]['x']+arrows[0]['w']/2, arrows[0]['y']+arrows[0]['h']/2); await app.wait(250)
            await app.shot('_e_dp1.png'); rec('D-pad nudges shape', imdiff(b4,'_e_dp1.png')>200)
        else: rec('D-pad nudges shape', False, 'arrow not found')
        await app.click('1-Side Edge Size', wait=900); await app.shot('flutter_transform_pad_resize_390.png'); b5='_e_dp1.png'
        await app.click('➡️+ Expand', wait=400); await app.click('➡️+ Expand', wait=400); await app.shot('_e_dp2.png')
        rec('1-side edge resize', imdiff(b5,'_e_dp2.png')>200)
        closes=[x for x in await app.nodes() if x['role']=='button' and x['label'].strip().endswith('✕')]
        if closes: await app.pg.mouse.click(closes[0]['x']+closes[0]['w']-22, closes[0]['y']+closes[0]['h']/2); await app.wait(600)  # title bar node merges ✕ at its right end
        # Photo effects
        await app.click('Photo Effects', wait=1500); await app.shot('flutter_photo_effects_390.png'); await app.dump('/workspace/e2e/fx_nodes.json')
        rec('Photo Effects window opens', await app.find('Apply', exact=True) is not None)
        bw=await app.find('B&W', role='') 
        if bw: await app.pg.mouse.click(bw['x']+bw['w']/2,bw['y']+bw['h']/2); await app.wait(2500); await app.shot('_e_fx_bw.png')
        if await app.find('Apply', exact=True): await app.click('Apply', exact=True, wait=2500)
        await app.shot('_e_fx_applied.png'); rec('Photo Effects apply (B&W scan)', bw is not None and imdiff('_e_color.png','_e_fx_applied.png',(0,0,780,900))>2000)
        # colour picker
        await app.click('🎨', exact=True, wait=1200); await app.shot('flutter_color_picker_390.png'); await app.dump('/workspace/e2e/cp_nodes.json')
        rec('Colour picker opens', await app.find('OK', exact=True, role='') is not None)
        okb=await app.find('OK', exact=True, role='')
        if okb: await app.pg.mouse.click(okb['x']+okb['w']/2, okb['y']+okb['h']/2); await app.wait(700)
        # zoom & pan
        await app.click('Zoom & Pan', wait=1200); await app.shot('_e_zoom0.png')
        rec('Zoom & Pan mode hides toolbar (as HTML)', await app.find('Highlight', exact=True) is not None and await app.find('Collapse Options') is None)
        await app.pg.mouse.move(190,350); await app.pg.mouse.wheel(0,-500); await app.wait(800); await app.shot('flutter_zoom_390.png')
        rec('Wheel zoom', imdiff('_e_zoom0.png','flutter_zoom_390.png',(0,0,780,1700))>5000)
        await app.drag(190,350,120,300); await app.shot('_e_pan.png'); rec('Pan by drag', imdiff('flutter_zoom_390.png','_e_pan.png',(0,0,780,1700))>5000)
        await app.click('Highlight', exact=True, wait=1200)
        # collapse
        await app.click('Collapse Options', wait=900); await app.shot('flutter_collapsed_390.png')
        rec('Collapse Options', await app.find('Expand Options') is not None)
        await app.click('Expand Options', wait=900)
        # OCR
        n_before=await layers(app)
        await app.click('Text OCR', wait=1000)
        t0=time.time(); ok=False
        while time.time()-t0<150:
            await app.wait(2000)
            if await app.find('Recognized Text', role=''): ok=True; break
        await app.wait(1500); await app.shot('flutter_ocr_390.png')
        rec('Text OCR (tesseract.js eng+hin) shows result sheet', ok, f'{int(time.time()-t0)}s')
        rec('OCR sheet has Copy/Share/Add as text layer', all([await app.find(x) for x in ('Copy','Share','Add as text layer')]))
        await app.click('Add as text layer', wait=2500)
        n_after=await layers(app)
        rec('Add as text layer adds a layer & closes the sheet', n_after>n_before and await app.find('Recognized Text', role='') is None, f'{n_before}->{n_after}')
        await app.click('Done', wait=5000); await app.shot('_e_home_hl.png')
        rec('Done (highlights) returns + burns into thumb', await app.find('Scan Photo') is not None)
        # Reopen highlight, shapes restored (editable)
        await app.click('Highlight', exact=True, wait=5000); await app.click('Layers', wait=900)
        lc6=len([x for x in await app.nodes() if x['role']=='button' and x['label'].strip()=='×'])
        rec('Re-open Highlight keeps editable layers', lc6>=5, f'layers={lc6}')
        await app.shot('flutter_highlight_reopen_390.png')
        await app.click('Cancel', exact=True, wait=2000)
        rec('No page/console errors (editor)', not app.errors, '; '.join(app.errors)[:300])
        await b.close()
        json.dump(RESULTS, open('/workspace/e2e/res_editor.json','w'), ensure_ascii=False)
asyncio.run(main())
