# TCC Species Check

Small app for volunteers. Scan a tree barcode. See the species in the database. Tap CORRECT, or tap CHANGE SPECIES and pick the right one. Results go to Airtable.

## 1. Make the Airtable table

In base `apptsFPTXHY0on83K` (same base as BTM), make a new table called `Species Check` with these fields:

| Field | Type |
|---|---|
| Barcode | Single line text (primary field) |
| Plot | Single line text |
| Recorded Species | Single line text |
| Confirmed Species | Single line text |
| Status | Single line text |
| Checked At | Date, with time field turned on |
| Checked By | Single line text |

The existing BTM key must have write access to this new table.

## 2. Check the names in lib/config.dart

The app reads species from table `Basal Dia & DBH`, fields `Barcode` and `Species`. These names are a guess. If they are different, change them in `lib/config.dart`.

If `Species` is a linked record field, the app shows the linked record ID and not the name. Use a lookup field in that table instead.

## 3. Build (Codespace)

```
flutter create --org uk.org.tcc --project-name species_check --platforms android .
```

This keeps the files in `lib/` and `pubspec.yaml`. Then copy the working Android settings from the BTM repo:

- AGP 8.3.0, Gradle 8.4-all, Kotlin 1.9.22
- Java 1.8 (`VERSION_1_8` and `jvmTarget = "1.8"`)
- `compileSdk 36`
- `ndk { abiFilters "arm64-v8a" }`
- datastore 1.1.7 force block and the prebuilt `libdatastore_shared_counter.so`
- gradle.properties as in BTM

Build:

```
flutter pub get
flutter build apk --release --target-platform android-arm64
```

Commit `pubspec.lock` after the first good build.

## 4. Use

1. Open Settings. Enter handset name and Airtable key.
2. Tap Download trees. Do this once with Wi-Fi.
3. Go to the main screen. Scan barcodes.
4. Tap the cloud icon to send results. The app also sends after 20 saved records.

## Notes

- The app expects the hardware scanner to type the barcode and press Enter (same as BTM).
- If a tree is scanned again, the old result is shown. The new result replaces it in Airtable.
- Species in the drop down are in `lib/config.dart`.
