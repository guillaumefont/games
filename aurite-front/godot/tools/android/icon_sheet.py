"""Print a contact sheet of the launcher icons packed in an APK, as a base64 PNG in @@SHEET chunks.

CI cannot share files with reviewers who only see logs, so this proves which images the built APK
really carries for each chapter: adaptive foreground over background, cropped to a circle, plus
the legacy full icon. Usage: icon_sheet.py app.apk aapt2"""
import base64, io, re, subprocess, sys, zipfile
from PIL import Image, ImageDraw

apk, aapt2 = sys.argv[1], sys.argv[2]
dump = subprocess.run([aapt2, "dump", "resources", apk], capture_output=True, text=True).stdout
files, cur = {}, None
for line in dump.splitlines():
    m = re.match(r"\s*resource \S+ mipmap/(\S+)", line)
    if m: cur = m.group(1); continue
    if re.match(r"\s*resource ", line): cur = None; continue
    m = re.search(r"\((\w*)\) \(file\) (res/\S+\.(?:png|webp))", line)
    if cur and m:
        files.setdefault(cur, []).append(m.group(2))
z = zipfile.ZipFile(apk)
def img(name):
    # the biggest density available
    best = max(files.get(name, []), key=lambda f: len(z.read(f)), default=None)
    return Image.open(io.BytesIO(z.read(best))).convert("RGBA") if best else None
S = 160
rows = [("icon", "icon_foreground", "icon_background"), ("icon_stage2", "icon_stage2_fg", "icon_stage2_bg"), ("icon_stage3", "icon_stage3_fg", "icon_stage3_bg")]
sheet = Image.new("RGBA", (S * 2 + 30, S * 3 + 40), (40, 40, 40, 255))
mask = Image.new("L", (S, S)); ImageDraw.Draw(mask).ellipse((0, 0, S - 1, S - 1), fill=255)
for r, (full, fg, bg) in enumerate(rows):
    y = 10 + r * (S + 10)
    f, b = img(fg), img(bg)
    if f and b:
        a = Image.alpha_composite(b.resize((432, 432)), f.resize((432, 432)))
        # launchers show the middle 66% of the 108dp layer
        a = a.crop((72, 72, 360, 360)).resize((S, S), Image.LANCZOS)
        sheet.paste(a, (10, y), mask)
    l = img(full)
    if l: sheet.paste(l.resize((S, S), Image.LANCZOS), (S + 20, y))
    print(full, files.get(full), fg, files.get(fg), bg, files.get(bg))
buf = io.BytesIO(); sheet.convert("RGB").save(buf, "PNG", optimize=True)
b64 = base64.b64encode(buf.getvalue()).decode()
# GitHub drops very long log lines: print it in numbered chunks
for i in range(0, len(b64), 8000):
    print("@@SHEET %03d %s" % (i // 8000, b64[i:i + 8000]))
