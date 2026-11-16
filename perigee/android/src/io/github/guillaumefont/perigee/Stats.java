package io.github.guillaumefont.perigee;

import android.content.Context;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.preference.PreferenceManager;
import android.util.Log;

import com.google.firebase.FirebaseApp;
import com.google.firebase.analytics.FirebaseAnalytics;

import java.util.EnumMap;
import java.util.Map;

/**
 * Google Analytics for Firebase: day-1/day-7 retention and paying users come from its automatic events
 * (first_open, session_start, in_app_purchase); the game adds run_start, run_end and ad events.
 * Without google-services.json (no Firebase project yet) FirebaseApp isn't set up and every call is a no-op.
 */
final class Stats {
    private static final String TAG = "PerigeeStats";
    private final FirebaseAnalytics fa;

    Stats(Context ctx) {
        FirebaseAnalytics a = null;
        try {
            if (!FirebaseApp.getApps(ctx).isEmpty()) a = FirebaseAnalytics.getInstance(ctx);
            else Log.i(TAG, "No Firebase config (google-services.json): analytics off");
        } catch (RuntimeException e) {
            Log.w(TAG, "Firebase Analytics unavailable", e);
        }
        fa = a;
    }

    void log(String event, Bundle params) {
        if (fa != null) fa.logEvent(event, params);
    }

    /**
     * Consent mode, from the IAB TCF answers the consent form (UMP) stores in the default preferences.
     * Where GDPR applies, analytics and ad storage follow purpose 1 ("store and access information on a
     * device"); elsewhere everything is granted. The manifest makes all four denied until this runs.
     */
    @SuppressWarnings("deprecation")
    void applyConsent(Context ctx) {
        if (fa == null) return;
        SharedPreferences p = PreferenceManager.getDefaultSharedPreferences(ctx);
        boolean gdpr = readInt(p, "IABTCF_gdprApplies") == 1;
        String purposes = p.getString("IABTCF_PurposeConsents", "");
        boolean storage = !gdpr || (purposes.length() > 0 && purposes.charAt(0) == '1');
        boolean personalised = !gdpr || (storage && purposes.length() > 3 && purposes.charAt(3) == '1'); // purpose 4
        FirebaseAnalytics.ConsentStatus yes = FirebaseAnalytics.ConsentStatus.GRANTED;
        FirebaseAnalytics.ConsentStatus no = FirebaseAnalytics.ConsentStatus.DENIED;
        Map<FirebaseAnalytics.ConsentType, FirebaseAnalytics.ConsentStatus> m = new EnumMap<>(FirebaseAnalytics.ConsentType.class);
        m.put(FirebaseAnalytics.ConsentType.ANALYTICS_STORAGE, storage ? yes : no);
        m.put(FirebaseAnalytics.ConsentType.AD_STORAGE, storage ? yes : no);
        m.put(FirebaseAnalytics.ConsentType.AD_USER_DATA, storage ? yes : no);
        m.put(FirebaseAnalytics.ConsentType.AD_PERSONALIZATION, personalised ? yes : no);
        fa.setConsent(m);
    }

    private static int readInt(SharedPreferences p, String key) {
        try { return p.getInt(key, -1); } catch (ClassCastException e) {
            try { return Integer.parseInt(p.getString(key, "-1")); } catch (Exception e2) { return -1; }
        }
    }
}
