# Koofy-Reader

Koofy Reader Flutter app (Android first, iOS later).

## AdMob policy in this repository

- Public repository: do not commit production AdMob IDs.
- Development uses Google test ad IDs by default.
- Production IDs are injected only at release build time.

## Ad-related files

- `lib/features/ads/config/admob_ids.dart`
- `lib/features/ads/presentation/banner_ad_widget.dart`
- `lib/features/ads/data/rewarded_ad_service.dart`
- `lib/features/ads/presentation/ad_footer_widget.dart`

## Local secret file

1. Copy `.env.admob.example` to `.env.admob`
2. Fill real production values in `.env.admob`
3. Keep `.env.admob` private (`.gitignore` already configured)

## Android build script (auto test/prod split)

`scripts/android_ads_build.sh` handles branching automatically:

- `debug` mode => test IDs
- `release` mode => production IDs from `.env.admob`

Examples:

```bash
./scripts/android_ads_build.sh debug apk
./scripts/android_ads_build.sh release aab
```

## GitHub Actions release build

Manual workflow:

- `.github/workflows/android-release.yml`

Required repository secrets:

- `ADMOB_APP_ID_ANDROID`
- `ADMOB_BANNER_ANDROID`
- `ADMOB_REWARDED_ANDROID`

Execution:

1. GitHub repository -> `Actions`
2. Run `Android Release (AdMob Prod)` workflow
3. Download artifact `app-release-aab`

## Android manifest App ID injection

- Manifest key uses `${ADMOB_APP_ID}`
- Value is injected by Gradle `manifestPlaceholders`
- Default is Google test App ID
- Release script overrides with `ORG_GRADLE_PROJECT_ADMOB_APP_ID`

## Quick release checklist

1. Ensure `.env.admob` is present locally/CI secrets.
2. Run `./scripts/android_ads_build.sh release aab`.
3. Verify ads in internal test track before store submission.
