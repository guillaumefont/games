package io.github.guillaumefont.perigee;

import android.app.Activity;
import android.os.SystemClock;
import android.util.Log;

import androidx.annotation.NonNull;

import com.google.android.gms.ads.AdError;
import com.google.android.gms.ads.AdRequest;
import com.google.android.gms.ads.FullScreenContentCallback;
import com.google.android.gms.ads.LoadAdError;
import com.google.android.gms.ads.MobileAds;
import com.google.android.gms.ads.interstitial.InterstitialAd;
import com.google.android.gms.ads.interstitial.InterstitialAdLoadCallback;
import com.google.android.gms.ads.rewarded.RewardedAd;
import com.google.android.gms.ads.rewarded.RewardedAdLoadCallback;
import com.google.android.ump.ConsentInformation;
import com.google.android.ump.ConsentRequestParameters;
import com.google.android.ump.UserMessagingPlatform;

import java.util.concurrent.atomic.AtomicBoolean;

/**
 * AdMob, behind Google's consent form (UMP):
 * - an interstitial on every 3rd "fly again", at most once every 90 s, never after a rewarded continue
 *   and never once "Remove ads" is bought;
 * - a rewarded ad to continue a run (offered by the game-over card, once per run).
 * Ad unit ids come from BuildConfig (Google's test units until real ones are set in gradle.properties).
 * All methods run on the UI thread.
 */
final class Ads {
    interface Listener {
        void onRewardedReady(boolean ready);
        void onContinueResult(boolean rewarded);
        void onConsentReady();
    }

    private static final String TAG = "PerigeeAds";
    private static final int RESTARTS_PER_INTERSTITIAL = 3;
    private static final long MIN_GAP_MS = 90_000;

    private final Activity act;
    private final Listener listener;
    private final Stats stats;
    private final ConsentInformation consent;
    private final AtomicBoolean started = new AtomicBoolean(false);
    private InterstitialAd interstitial;
    private RewardedAd rewarded;
    private boolean loadingInterstitial, loadingRewarded;
    private int restarts;
    private long lastAdAt = -MIN_GAP_MS;
    boolean removed;

    Ads(Activity act, Stats stats, Listener listener) {
        this.act = act;
        this.stats = stats;
        this.listener = listener;
        consent = UserMessagingPlatform.getConsentInformation(act);
    }

    /** Asks for consent where needed (EEA, UK, Switzerland), then starts the ads SDK. */
    void start() {
        ConsentRequestParameters params = new ConsentRequestParameters.Builder().build();
        consent.requestConsentInfoUpdate(act, params,
                () -> UserMessagingPlatform.loadAndShowConsentFormIfRequired(act, formError -> {
                    if (formError != null) Log.w(TAG, "consent form: " + formError.getMessage());
                    afterConsent();
                }),
                requestError -> {
                    Log.w(TAG, "consent info: " + requestError.getMessage());
                    afterConsent();
                });
        if (consent.canRequestAds()) afterConsent(); // consent from an earlier launch: no need to wait
    }

    private void afterConsent() {
        stats.applyConsent(act);
        listener.onConsentReady();
        if (!consent.canRequestAds() || !started.compareAndSet(false, true)) return;
        new Thread(() -> {
            MobileAds.initialize(act, status -> { });
            act.runOnUiThread(this::preload);
        }, "ads-init").start();
    }

    boolean privacyOptionsRequired() {
        return consent.getPrivacyOptionsRequirementStatus() == ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED;
    }

    void showPrivacyOptions(Runnable done) {
        UserMessagingPlatform.showPrivacyOptionsForm(act, formError -> {
            stats.applyConsent(act);
            if (consent.canRequestAds() && started.compareAndSet(false, true)) {
                MobileAds.initialize(act, status -> { });
                preload();
            }
            done.run();
        });
    }

    private void preload() {
        if (!started.get()) return;
        if (!removed && interstitial == null && !loadingInterstitial) {
            loadingInterstitial = true;
            InterstitialAd.load(act, BuildConfig.ADMOB_INTERSTITIAL, new AdRequest.Builder().build(), new InterstitialAdLoadCallback() {
                @Override public void onAdLoaded(@NonNull InterstitialAd ad) { interstitial = ad; loadingInterstitial = false; }
                @Override public void onAdFailedToLoad(@NonNull LoadAdError e) { loadingInterstitial = false; Log.i(TAG, "interstitial: " + e.getMessage()); }
            });
        }
        if (!removed && rewarded == null && !loadingRewarded) {
            loadingRewarded = true;
            RewardedAd.load(act, BuildConfig.ADMOB_REWARDED, new AdRequest.Builder().build(), new RewardedAdLoadCallback() {
                @Override public void onAdLoaded(@NonNull RewardedAd ad) { rewarded = ad; loadingRewarded = false; listener.onRewardedReady(true); }
                @Override public void onAdFailedToLoad(@NonNull LoadAdError e) { loadingRewarded = false; Log.i(TAG, "rewarded: " + e.getMessage()); }
            });
        }
    }

    boolean rewardedReady() {
        return rewarded != null;
    }

    /** "Fly again" was tapped: maybe show an interstitial over the fresh run (the WebView pauses under it). */
    void onRestart() {
        restarts++;
        if (removed || restarts < RESTARTS_PER_INTERSTITIAL || interstitial == null) { preload(); return; }
        if (SystemClock.elapsedRealtime() - lastAdAt < MIN_GAP_MS) return;
        InterstitialAd ad = interstitial;
        interstitial = null;
        restarts = 0;
        lastAdAt = SystemClock.elapsedRealtime();
        ad.setFullScreenContentCallback(new FullScreenContentCallback() {
            @Override public void onAdDismissedFullScreenContent() { preload(); }
            @Override public void onAdFailedToShowFullScreenContent(@NonNull AdError e) { preload(); }
        });
        ad.show(act);
        stats.log("ad_interstitial", null);
    }

    /** Shows the rewarded ad; the run continues only if the reward was earned. */
    void showRewarded() {
        RewardedAd ad = rewarded;
        if (ad == null) { listener.onContinueResult(false); return; }
        rewarded = null;
        listener.onRewardedReady(false);
        final boolean[] earned = {false};
        ad.setFullScreenContentCallback(new FullScreenContentCallback() {
            @Override public void onAdDismissedFullScreenContent() { done(); }
            @Override public void onAdFailedToShowFullScreenContent(@NonNull AdError e) { done(); }
            private void done() {
                listener.onContinueResult(earned[0]);
                // a rewarded view counts as this cycle's ad: no interstitial right after it
                restarts = 0;
                lastAdAt = SystemClock.elapsedRealtime();
                preload();
            }
        });
        ad.show(act, reward -> earned[0] = true);
        stats.log("ad_rewarded", null);
    }
}
