# Species Check app - handoff to Claude Code

## 1. Goal

The tallest-tree exercise found that about 4% of tree species in the database are wrong. Most errors are cherry, birch and aspen. They look the same when planted as whips.

We need a very simple Android app for volunteers to check every tree in the database. This app is separate from BTM. BTM is too complex for this job.

Volunteer workflow:
1. Scan a tree barcode with the hardware scanner.
2. The app shows the species now in the database.
3. The volunteer taps CORRECT (most trees), or taps CHANGE SPECIES and picks the right species from a list.
4. The app saves the result and goes back to scan mode.
5. The app syncs the results to Airtable.

## 2. Status

- First draft of the full app code is written. It was NOT compiled or run. Claude.ai could not build Flutter in its environment.
- Charles made the Airtable table `Species Check` and checked `lib/config.dart`. He says it looks good.
- Charles made an empty GitHub repo: `Charlesmnicholls/SpeciesType`.
- The source is in `species_check.zip` (sent in the earlier chat). Unzip it into the repo root.

## 3. Decisions already made

- Separate Flutter app. Do not change BTM.
- Species source: the app downloads barcode and species from table `Basal Dia & DBH` on first sync, then works offline.
- Results go to a NEW table `Species Check` in the BTM base. The original data does not change. This gives an audit trail and allows undo.
- Same Airtable key (PAT) as BTM. The user types it in Settings.
- Re-scan of a checked tree: the new result replaces the old one (PATCH the same Airtable record). It does not add a second row.
- Plot = first two digits of the barcode.
- Drop-down species: Birch, Alder, Aspen, Rowan, Cherry, Oak, Sitka Spruce, Goat Willow.
- Target device: Nautiz X41 rugged handset (Android 10-11), sideloaded APK. About 200 volunteers may use the app.

## 4. Airtable

- Base: `apptsFPTXHY0on83K` (BTM base).
- Read table: `Basal Dia & DBH`. Fields used: `Barcode`, `Species`. These names are a guess. Verify them.
- Write table: `Species Check`. Fields:

| Field | Type |
|---|---|
| Barcode | Single line text (primary) |
| Plot | Single line text |
| Recorded Species | Single line text |
| Confirmed Species | Single line text |
| Status | Single line text (`Confirmed` or `Changed`) |
| Checked At | Date with time |
| Checked By | Single line text (handset name) |

Rules from earlier BTM work:
- Batch limit is 10 records per request.
- On HTTP 429, wait 31 seconds, then retry.
- A "Barcode" type field needs `{"text": "value"}`. A text field needs a plain string. Check which type the new `Barcode` field has.
- Strip all whitespace and carriage returns from the pasted key before use. The code does this.
- Do not send null fields.

## 5. Code layout

```
pubspec.yaml
README.md
lib/
  main.dart             App start, theme
  config.dart           Base ID, table names, field names, species list
  db.dart               SQLite: trees, checks (synced flag, airtable_id)
  airtable_sync.dart    Settings (PAT, handset), download trees, upload checks
  scan_screen.dart      Main screen: scan, show species, CORRECT / CHANGE
  settings_screen.dart  Handset name, PAT, Download trees, Send results, version
```

Behaviour in the code:
- Scan field keeps focus. The scanner types the barcode and presses Enter.
- First launch asks for a handset name.
- Auto-upload starts when 20 or more records are waiting. The cloud icon in the app bar uploads on demand and shows the waiting count.
- Footer shows "Checked X of Y, Changed Z".
- Vibration uses the `vibration` package (not HapticFeedback).

## 6. First tasks for Claude Code

1. Unzip the source into the repo. Run `git status`. Make sure no stray files are in the repo root.
2. Run `flutter create --org uk.org.tcc --project-name species_check --platforms android .` Check that it did not overwrite `pubspec.yaml` or `lib/main.dart`. Delete the generated `test/widget_test.dart` (it refers to `MyApp` and will fail).
3. Apply the BTM Android build settings (section 7).
4. Run `flutter pub get` and `flutter analyze`. Fix all errors.
5. Verify the Airtable names in `lib/config.dart` against the real base. Use a test call or ask Charles.
6. Add a GitHub Actions workflow for a signed arm64 APK (as in the other TCC repos).
7. Commit `pubspec.lock` after the first good build.
8. Charles tests on one handset first. Then deploy to the fleet.

## 7. Build rules (hard-won, do not change)

The Nautiz X41 shows a silent crash on start if these are wrong:
- AGP 8.3.0, Gradle 8.4-all, Kotlin 1.9.22.
- Java `VERSION_1_8` for source and target, and `jvmTarget = "1.8"`.
- `compileSdk 36` set directly (not through `flutter.compileSdkVersion`).
- Build arm64 only: `flutter build apk --release --target-platform android-arm64`. Add `ndk { abiFilters "arm64-v8a" }`. A fat APK crashes on this device.
- Force androidx.datastore 1.1.7 (all four artifacts) and include the prebuilt `libdatastore_shared_counter.so` in `jniLibs`.
- `gradle.properties`: `Xmx2g`, `MaxMetaspaceSize=512m`, `daemon=false`, `parallel=false`, `workers.max=1`, `enableJetifier=false`.
- Use a fixed keystore stored as a base64 GitHub secret. The debug keystore changes on each runner.
- Do not set `android:enableOnBackInvokedCallback` (silent install failure on Android 10).
- Copy the working `build.gradle` files from the `Regen-census` repo (`charlesmnicholls/Regen-census`).

## 8. Known risks to check

- The draft code was not compiled. Expect small compile errors.
- If `Species` in `Basal Dia & DBH` is a linked record or lookup field, the app may show a record ID or a list. The `_text()` helper takes the first value of a list. Confirm the real field type.
- The download reads the whole `Basal Dia & DBH` table (about 6,400 trees, 100 per page). Check the speed and the rate limit.
- `Uri.replace(queryParameters: {'fields[]': [..]})` must produce repeated `fields[]=` keys. Check this with a real call.
- The PAT is stored in SharedPreferences (as in the other TCC apps). Scope the PAT to the minimum: read `Basal Dia & DBH`, read/write `Species Check`.
- Goat Willow was excluded from the tallest-tree work. It is in the drop-down here so volunteers can correct a tree to or from Goat Willow. Confirm with Charles.
- Duplicate barcodes in the source table would be collapsed to one row (primary key). Check if this happens.

## 9. Ways of working with Charles

- Charles has no traditional software background. He uses the GitHub web UI and a GitHub Codespace terminal.
- Give complete replacement files, not diffs.
- Files go in through Codespace: `git add`, `git commit`, `git push`. Uploads through the web UI do not start Actions builds. Use `git commit --allow-empty` to start a build.
- Always run `git status` before a commit. Files written without the `lib/` prefix create stray files in the repo root.
- After each edit of a Dart file, check for curly quotes (U+2018 and U+2019). The Edit tool sometimes inserts them. Check:
  `python3 -c "c=open('lib/foo.dart','rb').read(); print('OK' if b'\xe2\x80\x98' not in c and b'\xe2\x80\x99' not in c else 'CURLY QUOTES FOUND')"`
- Any `setState()` after an `await` needs `if (!mounted) return;` before it.
- Cloud sessions cannot download the Dart SDK (`storage.googleapis.com` is blocked). Build in Codespace or GitHub Actions.
- Charles prefers short, simple answers (ASD-STE100 Simplified Technical English).
- Add the app version to the Settings screen (done through `package_info_plus`).
