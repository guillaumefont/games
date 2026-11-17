# Launching Perigee on Google Play

What has to happen, in order. Steps marked **you** need Guillaume's accounts; the rest is in the repository.

## 1. Accounts (you)

1. **Play Console developer account** ($25 one-time, identity check): https://play.google.com/console/signup.
   A personal account created after November 2023 must run a **closed test with at least 12 testers opted in
   for 14 days in a row** before it can apply for production. An organization account (needs a free D-U-N-S
   number) doesn't. Start this first: it's the longest wait.
2. **Payments profile** (Play Console > Setup > Payments profile): only needed once the shop (spark packs) is
   added in a later phase. The game has no ads, analytics or purchases for now.

## 2. Upload key (you)

Play re-signs the app with its own key (Play App Signing); you keep an **upload key** that CI signs with.
Generate it once, keep a backup of the file and the password somewhere safe (a password manager), then add
it to the repository's secrets:

```
keytool -genkeypair -v -keystore perigee-upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
gh secret set PERIGEE_UPLOAD_KEYSTORE_BASE64 --repo guillaumefont/games < <(base64 -w0 perigee-upload.jks)
gh secret set PERIGEE_UPLOAD_STORE_PASSWORD --repo guillaumefont/games   # the password you chose
gh secret set PERIGEE_UPLOAD_KEY_ALIAS --repo guillaumefont/games --body upload
gh secret set PERIGEE_UPLOAD_KEY_PASSWORD --repo guillaumefont/games     # the same password: Godot signs with one
```

(On macOS, use `base64 -i perigee-upload.jks` instead of `base64 -w0 …`.) Then re-run the **Perigee builds**
workflow on `main` (Actions > Perigee builds > Run workflow): its run has a `perigee-aab` artifact,
`perigee.aab`, signed with that key. It is the Godot game, exported with Godot's Gradle build template
(target SDK 36).

## 3. Create the app in Play Console (you)

1. Create app: name "Perigee: Orbit Hop", Game, Free.
2. Paste the listing and answer the App content forms from [listing.md](listing.md).
3. Testing > Internal testing: create a release and upload `perigee.aab` from step 2 by hand (Play needs the
   first bundle that way). Keep Play App Signing on (the default).
4. In-app products wait for the shop phase (listing.md).

## 4. Automatic uploads (optional, you)

To have every `main` build land in internal testing as a draft: create a Google Cloud service account, give
it a JSON key, invite its email in Play Console > Users and permissions with "Release to testing tracks" on
Perigee, and save the JSON as the `PLAY_SERVICE_ACCOUNT_JSON` secret.

## 5. Closed test, then soft launch

1. Testing > Closed testing: add 12+ testers (a Google Group is easiest), roll out, keep them opted in for 14 days.
2. Apply for production, then release to a few countries only (Production > Countries) for the soft launch.
3. Gate (from the Star Breaker plan): 1,000 installs, day-1 retention ≥ 30%, day-7 ≥ 10%, ≥ 1% paying. Installs
   and purchases are in Play Console; retention needs the opt-in analytics planned for the content phase. 1,000 installs needs a push: a small Google Ads app campaign or a friends drive.
