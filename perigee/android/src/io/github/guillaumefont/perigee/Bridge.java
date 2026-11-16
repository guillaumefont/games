package io.github.guillaumefont.perigee;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.webkit.JavascriptInterface;
import android.webkit.WebView;

import org.json.JSONException;
import org.json.JSONObject;

/**
 * What the page sees as window.PerigeeAndroid (the browser build has no such object, so it has no ads,
 * purchase or analytics). Calls from JavaScript arrive on a background thread and are moved to the UI
 * thread. Answers go back as window.perigeeNative.onEvent(name, data).
 */
final class Bridge implements Ads.Listener, Store.Listener {
    static final String PRIVACY_URL = "https://guillaumefont.github.io/games/perigee/privacy.html";

    private final Activity act;
    private final WebView web;
    private final Ads ads;
    private final Store store;
    private final Stats stats;
    private volatile String price = "";

    Bridge(Activity act, WebView web, Stats stats, android.content.SharedPreferences prefs) {
        this.act = act;
        this.web = web;
        this.stats = stats;
        ads = new Ads(act, stats, this);
        store = new Store(act, prefs, this);
        ads.removed = store.owned();
    }

    void start() {
        store.start();
        ads.start();
    }

    void stop() {
        store.stop();
    }

    // ---------- JavaScript -> app ----------

    @JavascriptInterface
    public String state() {
        JSONObject o = new JSONObject();
        try {
            o.put("adsRemoved", store.owned());
            o.put("canContinue", store.owned() || ads.rewardedReady());
            o.put("price", price);
        } catch (JSONException ignored) { }
        return o.toString();
    }

    @JavascriptInterface
    public void runStart() {
        stats.log("run_start", null);
    }

    @JavascriptInterface
    public void runEnd(int score, int moons, boolean continued) {
        Bundle b = new Bundle();
        b.putLong("score", score);
        b.putLong("moons", moons);
        b.putLong("continued", continued ? 1 : 0);
        stats.log("run_end", b);
    }

    @JavascriptInterface
    public void restart() {
        act.runOnUiThread(ads::onRestart);
    }

    @JavascriptInterface
    public void continueRun() {
        act.runOnUiThread(() -> {
            if (store.owned()) { send("continue", "{\"ok\":true}"); stats.log("continue_free", null); }
            else ads.showRewarded();
        });
    }

    @JavascriptInterface
    public void buyRemoveAds() {
        act.runOnUiThread(store::buy);
    }

    @JavascriptInterface
    public void privacy() {
        act.runOnUiThread(() -> {
            if (ads.privacyOptionsRequired()) ads.showPrivacyOptions(() -> { });
            else act.startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(PRIVACY_URL)));
        });
    }

    // ---------- app -> JavaScript ----------

    private void send(String name, String json) {
        act.runOnUiThread(() -> web.evaluateJavascript(
                "window.perigeeNative&&window.perigeeNative.onEvent('" + name + "'," + json + ")", null));
    }

    private void sendState() {
        send("state", state());
    }

    @Override public void onRewardedReady(boolean ready) { sendState(); }
    @Override public void onContinueResult(boolean rewarded) { send("continue", rewarded ? "{\"ok\":true}" : "{\"ok\":false}"); }
    @Override public void onConsentReady() { sendState(); }

    @Override public void onAdsRemoved() {
        ads.removed = true;
        Bundle b = new Bundle();
        b.putString("product", Store.REMOVE_ADS);
        stats.log("remove_ads", b);
        sendState();
    }

    @Override public void onPrice(String p) { price = p; sendState(); }
    @Override public void onPurchaseFailed(String why) { send("purchaseFailed", JSONObject.quote(why)); }
}
