# Perigee: Google Play listing

Text and answers to paste into Play Console. Graphics are in this folder, captured from the real game by
`node perigee/tools/store_assets.cjs` (re-run it after a visual change).

## Store listing (Grow > Store presence > Main store listing)

**App name** (30 max): `Perigee: Orbit Hop`

**Short description** (80 max):
`Hop from moon to moon with one finger. Don't drift into the dark.`

**Full description** (4,000 max):

```
Fling, catch, repeat. Perigee is a one-button arcade game about hopping from moon to moon across an endless sky.

Release to fling off along your orbit. Hold while you cross a dotted ring to get caught by the next moon. Miss, and you drift off into the dark.

• One finger, no tutorial screens: you learn it in three hops
• Every flight follows your orbit, so every hop is your own
• Grab the sparks between moons for bonus points
• Moons drift and rings shrink the further you get
• Short runs, endless sky: one more go is always two seconds away
• Plays offline, no account needed

How far can you get before the dark gets you?
```

**Graphics**

| Asset | File | Play's rule |
| --- | --- | --- |
| App icon | `../web/icon.png` | 512 x 512 PNG |
| Feature graphic | `feature-graphic.png` | 1024 x 500 |
| Phone screenshots | `screenshot-1-start.png` … `screenshot-4-over.png` | 2 to 8, 1080 x 1920 |

**Category:** Games > Arcade. **Tags:** Arcade, Casual, One-tap, Space.
**Contact email:** required, shown publicly. **Privacy policy:** https://guillaumefont.github.io/games/perigee/privacy.html

## App content (Policy > App content)

- **Privacy policy:** the URL above (`web/privacy.html`; fill in its contact email first).
- **Ads:** Yes, the app contains ads.
- **App access:** All functionality is available without special access.
- **Target audience:** 13 and over only (13-15, 16-17, 18+). Not under 13: it keeps the game out of the
  Families policy, which restricts ads and analytics SDKs.
- **Content rating (IARC questionnaire):** category "Game". No violence, fear, sex, language, drugs, gambling
  or user interaction. Answer yes to "in-app purchases" and "ads". Expected rating: Everyone / PEGI 3.
- **Government app / financial features / health:** No.
- **Data safety:**

  | Data type | Collected | Shared | Why | Optional |
  | --- | --- | --- | --- | --- |
  | Device or other IDs (advertising ID, app instance ID) | Yes | Yes (Google AdMob) | Advertising, Analytics, Fraud prevention | No |
  | Approximate location (from IP, by AdMob) | Yes | Yes (Google AdMob) | Advertising, Fraud prevention | No |
  | App interactions (runs, scores, ad views) | Yes | No | Analytics | No |
  | Purchase history (Remove ads) | Yes | No | App functionality, Analytics | No |

  Data is encrypted in transit: Yes. Users can request deletion: Yes (by email; there are no accounts).
  Collected data is processed ephemerally: No.

## In-app product (Monetize > Products > In-app products)

- Product ID `remove_ads`, one-time, name "Remove ads", price $1.99 (let Play convert for other countries).
  Description: "No more ads between runs, and continue a run without watching an ad."
