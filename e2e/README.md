# Playwright web flows

Run against a release web build served on port 8812:

    flutter build web --release && (cd build/web && python3 -m http.server 8812 --bind 127.0.0.1 &)
    python3 -m venv venv && venv/bin/pip install playwright pillow
    venv/bin/python e2e/move_layer.py   # draw 3 shapes, drag the middle one, assert only it moved (+undo/redo)
    venv/bin/python e2e/editor.py       # crop/highlight/OCR/Done flows
    venv/bin/python e2e/album.py

Scripts use `/workspace/test_imgs/*` sample photos and `/usr/bin/google-chrome`; adjust the paths for your machine.
