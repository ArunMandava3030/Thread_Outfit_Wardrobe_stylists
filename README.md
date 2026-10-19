# Thread

A Flutter outfit companion for a men's wardrobe. Start with the shirt or pants you are already wearing, choose a complementary color, then dress the pairing for your occasion. Compare three finishing options, favorite a look, or rate an outfit you are wearing with an explained 0–5 styling estimate. Personalize recommendations with likes and dislikes, explore style guides and headlines, dress for current weather, and organize your wardrobe and outfit plans.

[Try the web preview](https://arunmandava3030.github.io/Thread_Outfit_Wardrobe_stylists/) · [Android downloads](https://github.com/ArunMandava3030/Thread_Outfit_Wardrobe_stylists/releases) · [Mobile build guide](docs/mobile-builds.md)

The public preview offers the same shirt-first or pants-first guided flow, occasions, optional height, style directions, pants, shoes and layers, plus recent style headlines. It works without an account or browser storage; choices reset on reload. The Android app adds outfit ratings, persistent favorites, a local profile, adaptive learning, photo analysis, weather, wardrobe and planner. iPhone users can use the preview in Safari and add it to the Home Screen while Apple signing is arranged.

## Run locally

This workspace includes a local Flutter SDK in the ignored `.tools` directory. In PowerShell, from the project folder:

```powershell
. .\.tools\env.ps1
flutter.bat pub get
flutter.bat run -d edge
```

With an existing Flutter installation, use `flutter pub get` and `flutter run -d chrome`. For a browser-independent preview:

```powershell
flutter.bat run -d web-server --web-hostname 127.0.0.1 --web-port 8080
```

Then open http://127.0.0.1:8080. Flutter 3.35.7 / Dart 3.9.2 was used here. Commit `pubspec.lock` for reproducible application dependencies. The local SDK and tooling are not part of the application source.

## Using the app

1. In **Outfits**, choose **Shirt first** or **Pants first**, then choose its color or **Use a photo**. Shirt photos retain automatic torso sampling with manual correction. Pants photos use an explicit tap on the pants.
2. A suggested matching color is already selected. Keep it, tap another suggestion, or open **More colors**, then continue. Back retains your choices; changing the starting item selects a fresh recommendation the next time you continue.
3. Choose your occasion and whether to include a layer, then **Show my outfit**. One suggested look appears first; **Show 2 more outfits** reveals alternatives. Both chosen colors and the starting garment remain fixed.
4. **Favorite outfit** saves the look under **Saved**. **Outfit details** groups rating, planning, feedback and explanations. Your existing profile, favorites, votes, wardrobe and plans remain compatible.
5. Tap **Rate outfit**, or **Rate this outfit** inside outfit details. Review four compact garment summaries and the occasion. **Edit** opens one garment's type, color and photo controls; **Done** applies the changes and **Cancel** discards them. Optional fit observations, style and trend controls are under **More options**. Rating shows the score and suggestions directly; **Edit outfit** returns to the same choices.
6. **More** groups **My profile**, **Wardrobe** and **Planner**. Profile tools still support height in centimeters or inches, skin-tone sampling, undertone, and shoulder/waist/hip proportions. Skipping the profile during generation uses a disclosed 175 cm default.
7. Open **More options** in the outfit builder for styles, current weather, learning and dated fashion headlines. In the public preview, optional style, height and headlines are under **Style and fit (optional)** on the occasion step.
8. In **Wardrobe**, **Wear this shirt** or **Wear these pants** starts from an owned item. **Plan look** stores an outfit for a date and optional note; **Planner** manages these snapshots. Android Back returns to the previous outfit step or the More menu before leaving the app.

## Outfit ratings

The 0–5 result is a subjective styling estimate, not a validated prediction or an assessment of appearance or body quality. It scores selected color coordination and occasion/dress-code suitability. Optional comfort, hem clearance and preferred-silhouette observations add a fit component; measurements alone cannot establish whether a garment fits. Garment types must be confirmed by the user—photo color sampling does not recognize every item or its fit.

The rule score uses color coordination (45%), occasion (40%) and observed fit (15%); when fit is unknown, the first two weights are renormalized. The existing local preference model can adjust the result by at most ±0.25 points, with reduced influence when there are few votes. Top garment words are now included in its clothing features. Skin tone, shoulder proportions and height provide optional, constructive palette/fit advice and do not lower the numeric score.

If enabled, a snapshot refreshed within 48 hours can contribute +0.10 for a headline from the last 30 days whose keyword style matches the selected direction and compatible garment categories. The source and date are shown. This is a small discovery signal, not a popularity measure or recognition of the pictured clothing. Missing, stale or unrelated headlines cause no penalty. Every result shows its components and practical changes; changing an input invalidates the old result before another rating is made.

## Recent trends and the public preview

GitHub Actions refreshes a small feed of fashion headlines daily and on each Pages deployment. Sources are [GQ](https://www.gq.com/feed/rss), [Esquire](https://www.esquire.com/rss/style.xml/) and [FashionBeans](https://www.fashionbeans.com/feed/). Only headline metadata, publication dates and links are published; article text and images are not copied. Articles remain the property of their publishers.

The panel displays its refresh time, partial-source failures and stale data. Headlines older than 90 days and invalid links/dates are excluded. A failed refresh keeps the previous published site available. GitHub's scheduled runs can be delayed; the panel marks feeds older than 48 hours as stale. Simple keyword matches offer style shortcuts. These are editorial discovery hints, not measured popularity, personalized web training or proof that a trend suits everyone. Your explicit votes train the separate local preference model.

The guest build uses a separate entry point and temporary package manifest. It excludes the photo models, vision runtime, image-picker, shared-preferences and native TFLite dependencies. Its only app data request is the optional same-site headline feed. Browser networking still uses ordinary caches and connection metadata; Thread does not save guest choices.

Build the Pages artifact with Python 3 and Flutter on your PATH:

```sh
python tool/update_trends.py --output web/data/trends.json
python tool/build_guest.py --base-href /Thread_Outfit_Wardrobe_stylists/
```

Publish `build/guest`. For a site served at the domain root, use `--base-href /`. `.github/workflows/pages.yml` validates the app, refreshes the feed, builds this artifact and deploys it to GitHub Pages. Set repository **Settings → Pages → Source** to **GitHub Actions**. The full browser app remains available locally through `lib/main.dart`.

## Adaptive recommendations

`AdaptiveStylist` is a local content-based preference model: logistic regression trained with deterministic stochastic gradient descent and L2 regularization. It learns from the latest **200 distinct outfits with explicit likes or dislikes**. Features describe garment words, RGB/chroma/lightness, color contrasts and layer presence, with shared and occasion-specific weights. Skin tone, body shape, height, outfit IDs and editorial descriptions are not learning features.

Each ranking is fitted from the latest votes. Repeating the same vote does not count twice; changing or undoing a vote removes its previous contribution. **Reset learning** clears feedback while retaining the wardrobe, planner and saved looks. With no feedback, the curated recommendation order is preserved. Learned scores are relative preferences, not validated probabilities or outfit-quality percentages.

The pipeline generates outfit palettes, applies the selected style direction, adjusts garments for fresh current weather, then ranks by learned preference. If **Prioritize my wardrobe colors** is enabled, wardrobe coverage takes precedence, with learned ranking retained among equally covered outfits. Wardrobe matching compares categories and similar colors; it does not verify that you own the exact recommended cut, fabric, product or riding certification.

## Open APIs and attribution

The full app uses public services without embedding API keys. Weather and Wikipedia requests happen when you choose/search/refresh a city or select **Explore styles**. The headline panel loads a snapshot from this project's GitHub Pages site on request. None of these requests includes photos, skin tone, body measurements, wardrobe items or feedback. Providers receive the request and normal connection metadata, such as an IP address.

| Integration | Requests and use | Attribution and terms |
| --- | --- | --- |
| Open-Meteo location search | `https://geocoding-api.open-meteo.com/v1/search` with a typed city query; returns up to five city choices. | [Geocoding API](https://open-meteo.com/en/docs/geocoding-api), location data from [GeoNames](https://www.geonames.org/). |
| Open-Meteo current weather | `https://api.open-meteo.com/v1/forecast` with the selected city coordinates. Requests current temperature, feels-like temperature, precipitation, weather code and wind, with explicit Celsius/km/h/mm units and UTC timestamps. | Weather by [Open-Meteo](https://open-meteo.com/), data under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). App guidance adapts the supplied values into garment suggestions. |
| Wikipedia style guides | `https://en.wikipedia.org/w/api.php` batches plain-text introductions for *Casual wear*, *Smart casual*, *Streetwear*, *Athleisure* and *Preppy*, using `action=query`, `prop=extracts`, `exintro`, `explaintext`, and `origin=*`. | Shortened excerpts by Wikipedia contributors under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/), with an article link next to each source. [TextExtracts API](https://www.mediawiki.org/wiki/Extension:TextExtracts). |

Open-Meteo's server code is [open source under AGPLv3 or later](https://github.com/open-meteo/open-meteo); the hosted free endpoint has separate [non-commercial terms](https://open-meteo.com/en/terms), including fewer than 10,000 calls/day, 5,000/hour and 600/minute. A commercial release needs an appropriate hosted plan or deployment arrangement. Wikipedia API requests identify Thread using `Api-User-Agent` and, on native platforms, `User-Agent`; deployments can supply contact details with `--dart-define=WIKIMEDIA_USER_AGENT="ThreadStyle/1.0 (your contact URL)"`. See [MediaWiki API etiquette](https://www.mediawiki.org/wiki/API:Etiquette).

Wikipedia style guides supply readable context for choosing a direction; current headlines use the separate RSS pipeline described above. Neither trains a neural network. The garment recipes are explicit app rules; the adaptive model learns from your own votes. Missing articles and connection failures are shown honestly, while local style choices remain available.

Weather is current modeled data, not a forecast for the date of a planned outfit. Cached weather stops affecting new recommendations after one hour, aged from the provider's timestamp; refresh failures retain the saved weather with its age. The planner stores the selected outfit as a snapshot and does not automatically rewrite it when weather or preferences change. Calendar dates are stored without a time zone so travel does not move a plan onto a different day.

## Analysis and privacy

- Photo analysis runs real, bundled pose models on-device. Browsers use **MediaPipe Tasks Vision 0.10.32** and **Pose Landmarker Lite float16 v1** in a web worker. Android and iOS use **MoveNet SinglePose Lightning INT8 v4** through **tflite_flutter 0.12.1** in a Dart isolate. There are no model API keys, photo uploads or runtime model-CDN requests.
- The pose model locates joints; it does not classify garments. The app samples an inset torso region and takes the median color of its dominant RGB bucket. An optional face sample uses a small patch near the detected nose. Manual taps use median RGB sampling. Actual RGB is retained; a nearby preset only supplies the color name.
- Automatic proportions compare shoulder and hip **joint spacing** using broad heuristic bands. They are rough styling suggestions, not measured body dimensions. No waist or fuller-midsection classification is inferred by the pose model. Six guided points let the user supply shoulder, waist and hip outer edges instead. Low visibility, unsuitable geometry or angled poses fall back to guided input; these gates do not guarantee accuracy for every photo.
- Use a clear photo of one person with shoulders and hips visible. Automatic results are marked as estimates and require confirmation. Manual corrections stay available while the model loads and take priority over late results. Browser startup/inference failures and unsupported desktop runtimes show a manual fallback.
- Lighting, clothing and camera perspective affect these estimates. The profile is editable. Undertone is self-selected, not inferred from the image.
- Outfit construction uses explainable local rules, followed by a local preference model. No hosted AI service or API key is required. Skin tone is optional and never excludes a clothing color.
- Photos stay in memory for the current flow and are not written to Thread's persistent storage or uploaded. Camera/gallery providers may maintain their own original/cache files. Profile values, feedback, wardrobe entries, plans, style direction, selected city/weather and bookmarked outfits are stored locally using shared preferences. **Clear all my Thread data** removes these records; browser data belongs to the current browser/origin.
- Bike ride currently means **motorcycle riding**. Suggestions retain protective riding equipment even when fashion layering is disabled. Outfit illustrations show colors and generic garment categories, not exact products or certified equipment.

The vision runtimes and models use **Apache 2.0** licenses, included in `web/vision/LICENSE.txt` and `assets/models/LICENSE.txt`. Pinned sources and model hashes are recorded in `web/vision/PROVENANCE.json`. Browser vision assets total about 28 MB before HTTP compression; the native MoveNet model is 2.9 MB. See the official [MediaPipe guide](https://ai.google.dev/edge/mediapipe/solutions/vision/pose_landmarker), [BlazePose model card](https://storage.googleapis.com/mediapipe-assets/Model%20Card%20BlazePose%20GHUM%203D.pdf), [MoveNet model card](https://storage.googleapis.com/movenet/MoveNet.SinglePose%20Model%20Card.pdf), and [MoveNet preprocessing tutorial](https://www.tensorflow.org/hub/tutorials/movenet).

## Mobile builds

Android and iOS projects and permission descriptions are included. Android needs an Android SDK, compatible JDK and a device/emulator; use `flutter doctor` to check the environment and `flutter run` to start. iOS builds require macOS, Xcode, CocoaPods and a simulator/device. The configured minimum targets are Android API **26** (required by the TFLite integration) and iOS 13.

```text
flutter build apk --release
flutter build ios --release --no-codesign
```

Camera access works through the platform image picker. Browser camera capture depends on browser/device support and may show a file chooser. Android interrupted photo-picking recovery asks which analysis mode to resume. Validate camera permissions and picking on physical devices before store distribution. Without a private `android/key.properties`, Android release builds use a development certificate and are labeled demo APKs. Preserve that certificate for compatible updates. Production signing is supported; see the [mobile build guide](docs/mobile-builds.md).

The native inference implementation has not been run on Android/iPhone hardware in this Windows workspace. TFLite may not work in an iOS simulator; use a physical device. The iOS project includes the package's release symbol-stripping setting. The mobile workflow checks unsigned iOS compilation on macOS; an unsigned `.app` archive cannot be installed on an iPhone. An installable IPA requires Apple signing and provisioning. Desktop native inference is not bundled; the full browser app supports local inference on Windows.

## Checks and structure

Automated checks cover photo sampling, recommendation learning, storage recovery, weather/style APIs, wardrobe/planner flows, headline validation and the storage-free guest preview. Headless Chromium checks also cover desktop/phone rendering, bookmark persistence, gallery decoding and local browser pose inference, and live Wikipedia/Open-Meteo requests. Native model inference and physical camera permissions still need testing on real phones. Build and test results are available in the repository's Actions runs.

```text
flutter analyze
flutter test
python -m unittest discover -s tool -p "test_*.py"
flutter build web --release --no-web-resources-cdn --pwa-strategy=none
```

- `lib/main.dart`: responsive studio, navigation, photo import and application state.
- `lib/main_guest.dart` and `guest_app.dart`: session-only public preview.
- `lib/services/trend_service.dart` and `tool/update_trends.py`: validated headline snapshots and RSS ingestion.
- `lib/screens/profile_screen.dart`: height, proportions and optional color profile.
- `lib/services/photo_analyzer.dart`: pixel sampling, coordinate mapping and proportion classification.
- `lib/services/auto_photo_analyzer.dart` and `auto_pose_*`: platform inference, confidence/geometry gates, aspect-preserving model input and pose-guided sampling.
- `web/vision/`: pinned local MediaPipe runtime, WASM, pose model, worker, licenses and model provenance.
- `lib/services/style_engine.dart`: shirt palettes, occasions, personalized fit and accent choices.
- `lib/services/adaptive_stylist.dart`: local preference learning and deterministic ranking from explicit votes.
- `lib/services/style_discovery_service.dart` and `style_direction_stylist.dart`: attributed Wikipedia excerpts and occasion-aware style recipes.
- `lib/services/weather_service.dart` and `weather_stylist.dart`: validated city/current-weather requests, stale-cache handling and garment adjustments.
- `lib/services/wardrobe_stylist.dart`: category/color coverage and optional wardrobe ranking.
- `lib/screens/wardrobe_screen.dart` and `planner_screen.dart`: clothing inventory and dated outfit snapshots.
- `lib/services/style_store.dart`: versioned local persistence and data recovery.
- `lib/widgets/`: guided photo editor, weather and style-guide panels, outfit feedback cards and original vector garment illustrations.
- `test/`: image/ratio edge cases, learned preference transfer, mocked API failures, source attribution, weather/occasion safeguards, planner and wardrobe behavior, storage recovery and widget flows.

Roboto fonts and their license are bundled under `assets/fonts/` and registered as both `ThreadSans` and the browser engine's default `Roboto`. Flutter may fetch a static fallback font for an unsupported symbol; this does not send photos or profile data.

A garment-segmentation model would further distinguish a shirt from an open jacket or patterned background. Current pose-guided sampling exposes its estimate and correction controls so the user can verify the chosen clothing region.

References: [Flutter setup](https://docs.flutter.dev/install), [image_picker platform setup](https://pub.dev/packages/image_picker), [shared preferences](https://pub.dev/packages/shared_preferences), [web initialization](https://docs.flutter.dev/platform-integration/web/initialization).
