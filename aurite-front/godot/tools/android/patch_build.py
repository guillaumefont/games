#!/usr/bin/env python3
"""Adds the story-stage launcher icons to Godot's Android gradle build (CI runs it after
--install-android-build-template, before the export).

Usage (from godot/): python3 tools/android/patch_build.py android/build
- Stage 1 is Godot's own launcher alias (GodotAppLauncher, icon = the project icon).
- Stage 2 and 3 become disabled launcher aliases with their own adaptive icons from store/icons/.
- IconSwap.java (called from main.gd) turns one alias on and the others off.
"""
import os, shutil, sys

build = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
icons = os.path.join(here, '..', '..', 'store', 'icons')

man = os.path.join(build, 'src', 'main', 'AndroidManifest.xml')
xml = open(man).read()
assert '.GodotAppLauncher' in xml, 'template has no GodotAppLauncher alias'
if 'com.godot.game.Stage2' not in xml:
    alias = ''
    for n in (2, 3):
        alias += f'''        <activity-alias
            android:name="com.godot.game.Stage{n}"
            android:targetActivity=".GodotApp"
            android:icon="@mipmap/icon_stage{n}"
            android:enabled="false"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity-alias>
'''
    xml = xml.replace('    </application>', alias + '    </application>', 1)
    open(man, 'w').write(xml)

res = os.path.join(build, 'res')
xx = os.path.join(res, 'mipmap-xxxhdpi'); os.makedirs(xx, exist_ok=True)
av = os.path.join(res, 'mipmap-anydpi-v26'); os.makedirs(av, exist_ok=True)
from PIL import Image
for n in (2, 3):
    shutil.copy(os.path.join(icons, f'stage-{n}-fg.png'), os.path.join(xx, f'icon_stage{n}_fg.png'))
    shutil.copy(os.path.join(icons, f'stage-{n}-bg.png'), os.path.join(xx, f'icon_stage{n}_bg.png'))
    Image.open(os.path.join(icons, f'stage-{n}-1024.png')).resize((192, 192), Image.LANCZOS).save(os.path.join(xx, f'icon_stage{n}.png'))
    open(os.path.join(av, f'icon_stage{n}.xml'), 'w').write(f'''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/icon_stage{n}_bg" />
    <foreground android:drawable="@mipmap/icon_stage{n}_fg" />
    <monochrome android:drawable="@mipmap/icon_stage{n}_fg" />
</adaptive-icon>
''')

dst = os.path.join(build, 'src', 'main', 'java', 'com', 'godot', 'game')
shutil.copy(os.path.join(here, 'IconSwap.java'), dst)
print('stage icons added to', build)
