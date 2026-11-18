package com.godot.game;

import android.app.Activity;
import android.content.ComponentName;
import android.content.pm.PackageManager;

/**
 * Home-screen icon per story stage (pulpy, cracked, grim). The manifest has one launcher alias per stage
 * (Godot's GodotAppLauncher for stage 1, Stage2 and Stage3 added by tools/android/patch_build.py); this enables the stage's alias and disables the
 * others. Called from GDScript through JavaClassWrapper (main.gd, set_app_icon).
 */
public class IconSwap {
	public static boolean apply(Activity a, int stage) {
		try {
			PackageManager pm = a.getPackageManager();
			String pkg = a.getPackageName();
			// enable the new icon first so the app never has no launcher entry
			for (int pass = 0; pass < 2; pass++) {
				for (int i = 1; i <= 3; i++) {
					boolean want = i == stage;
					if (want != (pass == 0)) continue;
					ComponentName c = new ComponentName(pkg, i == 1 ? "com.godot.game.GodotAppLauncher" : "com.godot.game.Stage" + i);
					int st = pm.getComponentEnabledSetting(c);
					boolean on = st == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT ? i == 1 : st == PackageManager.COMPONENT_ENABLED_STATE_ENABLED;
					if (on != want) {
						pm.setComponentEnabledSetting(c, want ? PackageManager.COMPONENT_ENABLED_STATE_ENABLED
								: PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP);
					}
				}
			}
			return true;
		} catch (Exception e) {
			return false;
		}
	}
}
