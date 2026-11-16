package io.github.guillaumefont.perigee;

import android.app.Activity;
import android.content.SharedPreferences;
import android.util.Log;

import androidx.annotation.NonNull;

import com.android.billingclient.api.AcknowledgePurchaseParams;
import com.android.billingclient.api.BillingClient;
import com.android.billingclient.api.BillingClientStateListener;
import com.android.billingclient.api.BillingFlowParams;
import com.android.billingclient.api.BillingResult;
import com.android.billingclient.api.PendingPurchasesParams;
import com.android.billingclient.api.ProductDetails;
import com.android.billingclient.api.Purchase;
import com.android.billingclient.api.QueryProductDetailsParams;
import com.android.billingclient.api.QueryPurchasesParams;

import java.util.Collections;
import java.util.List;

/**
 * Google Play Billing for the one product, "remove_ads" (one-time). The purchase is checked against
 * Google Play at every launch (and cached in preferences so the game knows it offline). There is no
 * server: the purchase is trusted as Play reports it on the device.
 */
final class Store implements BillingClientStateListener {
    interface Listener {
        void onAdsRemoved();
        void onPrice(String price);
        void onPurchaseFailed(String why);
    }

    static final String REMOVE_ADS = "remove_ads";
    private static final String TAG = "PerigeeStore";
    private static final String PREF = "ads_removed";

    private final Activity act;
    private final Listener listener;
    private final SharedPreferences prefs;
    private final BillingClient client;
    private ProductDetails product;

    Store(Activity act, SharedPreferences prefs, Listener listener) {
        this.act = act;
        this.prefs = prefs;
        this.listener = listener;
        client = BillingClient.newBuilder(act)
                .setListener(this::onPurchases)
                .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
                .enableAutoServiceReconnection()
                .build();
    }

    boolean owned() {
        return prefs.getBoolean(PREF, false);
    }

    void start() {
        client.startConnection(this);
    }

    void stop() {
        client.endConnection();
    }

    @Override
    public void onBillingSetupFinished(@NonNull BillingResult r) {
        if (r.getResponseCode() != BillingClient.BillingResponseCode.OK) { Log.i(TAG, "billing setup: " + r.getDebugMessage()); return; }
        client.queryPurchasesAsync(QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build(),
                (res, purchases) -> { if (res.getResponseCode() == BillingClient.BillingResponseCode.OK) handle(purchases); });
        QueryProductDetailsParams q = QueryProductDetailsParams.newBuilder().setProductList(Collections.singletonList(
                QueryProductDetailsParams.Product.newBuilder().setProductId(REMOVE_ADS).setProductType(BillingClient.ProductType.INAPP).build())).build();
        client.queryProductDetailsAsync(q, (res, result) -> {
            List<ProductDetails> list = result.getProductDetailsList();
            if (res.getResponseCode() != BillingClient.BillingResponseCode.OK || list.isEmpty()) {
                Log.i(TAG, "no product " + REMOVE_ADS + ": " + res.getDebugMessage());
                return;
            }
            product = list.get(0);
            ProductDetails.OneTimePurchaseOfferDetails offer = product.getOneTimePurchaseOfferDetails();
            if (offer != null) act.runOnUiThread(() -> listener.onPrice(offer.getFormattedPrice()));
        });
    }

    @Override
    public void onBillingServiceDisconnected() { /* auto reconnection is on */ }

    boolean available() {
        return product != null;
    }

    void buy() {
        if (product == null) { listener.onPurchaseFailed("unavailable"); return; }
        BillingFlowParams p = BillingFlowParams.newBuilder().setProductDetailsParamsList(Collections.singletonList(
                BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(product).build())).build();
        BillingResult r = client.launchBillingFlow(act, p);
        if (r.getResponseCode() != BillingClient.BillingResponseCode.OK) listener.onPurchaseFailed("error");
    }

    private void onPurchases(@NonNull BillingResult r, List<Purchase> purchases) {
        int code = r.getResponseCode();
        if (code == BillingClient.BillingResponseCode.OK && purchases != null) handle(purchases);
        else if (code == BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED) grant();
        else if (code == BillingClient.BillingResponseCode.USER_CANCELED) act.runOnUiThread(() -> listener.onPurchaseFailed("cancelled"));
        else act.runOnUiThread(() -> listener.onPurchaseFailed("error"));
    }

    private void handle(List<Purchase> purchases) {
        for (Purchase p : purchases) {
            if (!p.getProducts().contains(REMOVE_ADS) || p.getPurchaseState() != Purchase.PurchaseState.PURCHASED) continue;
            if (!p.isAcknowledged()) { // unacknowledged purchases are refunded by Play after 3 days
                client.acknowledgePurchase(AcknowledgePurchaseParams.newBuilder().setPurchaseToken(p.getPurchaseToken()).build(),
                        res -> Log.i(TAG, "acknowledge: " + res.getResponseCode()));
            }
            grant();
        }
    }

    private void grant() {
        boolean was = owned();
        prefs.edit().putBoolean(PREF, true).apply();
        if (!was) act.runOnUiThread(listener::onAdsRemoved);
    }
}
