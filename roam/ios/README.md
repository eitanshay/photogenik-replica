# roam for iOS (ES-11)

Lives in roam/ios of this repo; built by the "roam iOS to TestFlight" Codemagic workflow.

A travel companion for one person (or each family member on their own phone). It nudges you near places you saved or should see, finds the best coffee, the best food and the nearest restroom, and reads you a two-minute story about where you are standing. Built to be easy on the battery.

## What it does

| Feature | How |
| --- | --- |
| **Alerts near saved places** | Your Google Maps lists (Takeout import), anything you share to roam, places pulled from trip docs. Geofences of 130 to 200 m. |
| **Alerts for things worth seeing** | On trips: Wikipedia articles about places within 10 km (long articles only, no streets, stations or districts), plus scenic spots. At most 3 a day, none in quiet hours, none while driving. |
| **Scenic and photogenic spots** | OpenStreetMap viewpoints, waterfalls, lighthouses, named beaches, notable gardens and attractions. Alerts mention golden hour when it is under 90 minutes away. Flag any saved place as photogenic. |
| **Coffee** | Always the best within a 20-minute walk: Google rating weighted by review count (Bayesian), a boost for specialty roasters, chains last, closed places hidden. |
| **Food** | Michelin Guide first (bundled, about 20,000 restaurants): Bib Gourmand leads for $ and $$, stars lead for $$$. Then places with strong Google ratings. Budget ($, $$, $$$) and cuisine chips. Open-now from Google. |
| **Restroom** | The nearest: OpenStreetMap public toilets, Refuge Restrooms, Apple Maps. If none is mapped, places that usually have one (libraries, stations, cafes). |
| **Two-minute audio guide** | Wikipedia text rewritten for the ear by Claude (230 to 280 words), read by the best on-device iOS voice. Free and offline once written. Without a Claude key it reads the start of the article. |
| **Trips** | Calendar events more than 100 km from home are grouped into trips. With Google connected, roam finds the Docs that mention each destination and can pull every place in a doc onto your map ("Add places"). |
| **Map** | All your places on Google Maps (saved orange, sights dark, scenic amber); tap a pin, then its label, to open it. Needs "Maps SDK for iOS" enabled on the same Google key; falls back to Apple Maps without a key. |
| **Navigation** | Hands off to Apple Maps or Google Maps for walking directions. |

## Battery

No continuous GPS at any point.

- **Significant-change updates** (cell and Wi-Fi, roughly every 500 m) wake the app to re-plan, even after it was swiped away.
- **Geofences** are watched by iOS in low-power hardware. iOS allows 20 per app: roam arms the 19 most relevant places near you (saved places weighted ahead of discoveries) and uses the 20th as a boundary around you; leaving it re-plans.
- **The buttons** take one location fix and stop.
- **Overnight prep** (charging and online): refreshes the Michelin data monthly, places imported saves on the map, writes stories for places near you or your next trip.

## Keys and accounts (Settings)

| | Needed for | Without it |
| --- | --- | --- |
| Google Maps Platform key (Places API (New) enabled) | Coffee and food ratings, open now, accurate import | Apple Maps results with no ratings; coffee is weak |
| Anthropic key | Stories written for the ear, reading trip docs | Stories are the start of the Wikipedia article; no doc import |
| Google sign-in (iOS OAuth client ID) | Finding trip docs in your Drive | Trips tab shows calendar trips only |

All keys live in the Keychain. The Google refresh token too.

### Google sign-in setup (one time)

1. Google Cloud console, your project: **APIs and Services, Library**: enable **Google Drive API**.
2. **OAuth consent screen**: External, add yourself as a test user, add the scope `.../auth/drive.readonly`. Then **Publish app** (to "In production"). Leave it unverified: you will see an "unverified app" screen when signing in, which is expected for a personal app. Staying in Testing would make Google expire the sign-in every 7 days.
3. **Credentials, Create credentials, OAuth client ID**, type **iOS**, bundle ID `com.eitanshay.roam`. Copy the client ID.
4. In roam: Settings, paste the client ID, **Sign in with Google**.

### Google Maps key

Google Cloud console: enable **Places API (New)**, create an API key, restrict it to the Places API (New). Paste it in Settings.

## Getting your Google Maps saved places in

Google has no API for saved places, so:

1. **Once:** takeout.google.com, select only **Saved** (one CSV per list) and **Maps (your places)** (starred places, `Saved Places.json`). Unzip in the Files app, then Places, +, Import, select the files. roam finds each place on the map (Takeout strips coordinates from list CSVs, so this uses Google Places, or Apple Maps without a key). Chains and ambiguous names can land on the wrong branch: check the "not on map" ones.
2. **From then on:** in Google Maps, open a place, Share, **roam**. The share extension resolves the link and saves it; the app picks it up the next time it wakes.

## Layout

| Path | What |
| --- | --- |
| `Roam.xcodeproj` | Generated project: app target `Roam`, share extension `RoamShare`, shared scheme `Roam` |
| `Roam/App` | App entry and delegate, background tasks, the model (location reactions, alerts, discovery, import, stories, trips), settings |
| `Roam/Platform` | Location engine, Places/Michelin/OSM/Refuge/Wikipedia lookups, narrator, notifications, Google OAuth and Drive, calendar, Keychain |
| `Roam/UI` | Now, results, places, place page, trips, settings, onboarding, Eitan Shay design system |
| `RoamShare` | Share extension (Google Maps, Apple Maps, any link) |
| `RoamCore` | Geo math, geofence planner, alert policy, ranking, Takeout and link parsing, Michelin data, all API parsers, story and doc prompts, sun. Compiled into both targets and unit-tested with `swift test` (58 tests, runs on Linux) |
| `scripts/generate_project.rb` | Regenerates the Xcode project (`gem install xcodeproj && ruby scripts/generate_project.rb`) |
| `scripts/build_michelin.py` | Rebuilds the bundled `michelin.tsv` from the michelin-my-maps dataset |

## First build (Codemagic to TestFlight)

Same setup as frame, polish and BloomTrack, plus one extra identifier for the share extension and an App Group.

1. **App Group.** Apple Developer, Identifiers, App Groups: register `group.com.eitanshay.roam`.
2. **App IDs.** Register `com.eitanshay.roam` and `com.eitanshay.roam.share`, each with the **App Groups** capability set to that group.
3. **Profiles.** An App Store distribution profile for each ID, with the distribution certificate Codemagic already holds.
4. **Codemagic.** Team settings, codemagic.yaml settings, Code signing identities, iOS provisioning profiles, Fetch profiles: pick both.
5. **App record.** App Store Connect, + New App, bundle ID `com.eitanshay.roam`, name like "roam ES-11". Copy the Apple ID into `APP_STORE_APPLE_ID` in `codemagic.yaml`.
6. **Build.** Add the repo to Codemagic and push to `main` (or start "roam iOS to TestFlight").
7. **First launch.** Allow location (While Using, then Always), notifications, set home. Add keys in Settings. For a natural voice, download a Premium English voice: iOS Settings, Accessibility, Spoken Content, Voices.

## Known limits

- Built without a Mac in the loop: the core logic is tested, but the app and extension compile for the first time on Codemagic. Expect one or two fix-up builds.
- iOS decides when geofence and significant-change events arrive. In dense cities an entry can come 30 to 90 seconds late, sometimes after you walked past. Radii are tuned for walking, not driving.
- The Listen button in an alert opens the app (iOS will not reliably start audio from the background). With AirPods in, unlock and it plays.
- "Best coffee" is only as good as Google ratings plus the specialty heuristics. It is strong in big cities and noisier in small towns.
- Discovery uses English Wikipedia by default; switch to the local language in Settings for better coverage abroad.
- Michelin data comes from the open michelin-my-maps dataset (scraped from the guide), refreshed monthly.

