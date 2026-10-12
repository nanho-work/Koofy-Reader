# App UI languages

The app supports Korean (`ko`), English (`en`), and Japanese (`ja`). The globe
button in the main library offers these languages and “Device language”.
An explicit selection is stored in SharedPreferences (`app_language_v1`). With
no selection, the first supported device locale is used; English is the fallback.
Returning to device language removes the saved override. OS locale changes are
observed while automatic selection is active.

## Message maintenance

`lib/core/localization/messages.json` is the shared message catalog. Korean
source strings are stable keys, with English and Japanese values. Use numbered
placeholders (`{0}`, `{1}`), preserving the same placeholders in each language.
Flutter uses `tr(key, arguments)`; native readers use `L(key, arguments...)`.
Regenerate all three platform tables after edits:

```sh
python3 tool/generate_localizations.py
dart format lib/core/localization/messages.g.dart
```

`AppLanguage` controls Flutter's locale. `ReaderLaunchRequest.uiLanguage` carries
the selected language into each native reader launch. Native font labels resolve
at presentation time, so switching language does not leave old cached labels.

Book titles, authors, book contents, downloaded font names, persistent category
identifiers, reading positions and TTS voice selections are not translated or
changed. Ordinary bundled books remain their original content. The app-owned getting-started guide is available in all three languages. Store listings and administrator-authored remote notices remain original content.
iOS photo-library and tracking permission descriptions have ko/en/ja
InfoPlist.strings resources. These system dialogs follow the OS-selected app
language, independently of the in-app language override.

## Validation

- Locale resolution, persistence, restart, system-language restoration, and
  placeholder parity: `test/app_language_test.dart`.
- Compact library layouts in all three languages: `test/library_page_test.dart`.
- Android native English/Japanese reader settings and unchanged book title:
  `ReaderRenderingTest.englishReaderLabelsPreserveBookText` and
  `ReaderRenderingTest.japaneseReaderLabelsPreserveBookText`.
- Full Flutter suite: 291 tests passed after the localization audit and guide translations.
- Android debug and unsigned iOS release builds were verified; this change does
  not publish either app or change the app version.

## Follow-up audit

The audit corrected untranslated backup/import/font errors, privacy consent
errors, the episode number label, support email templates, legacy-record empty
labels, and iOS permission descriptions. `localizedError` translates known
application messages while preserving unknown diagnostic text. Dynamic book
names and excerpts remain untouched. Regression tests cover localized exception
messages and episode rows containing an original Korean episode title.

## Localized getting-started guide

`ReaderGuide` selects the bundled guide source, title, description and cover from
`AppLanguage`. The library ID (`sample_2`) and canonical asset identity remain
stable, including serialization and backups. Korean uses `sample_2.txt`; English
and Japanese use `reader_guide_en.txt` and `reader_guide_ja.txt`. All are offline
assets. Each version has the same topics and a localized cover and table of
contents. Regenerate translated typographic covers from the existing vector
brand mark with `python3 tool/generate_guide_cover.py --language en` (or `ja`).

Each source generates a different content revision under the same publication
ID. Existing storage keeps positions and bookmarks by revision, so switching
back restores that language version's saved position. Opening another language
for the first time may display the normal content-change notice. No locator is
copied across translated text. Ordinary books keep their original revision.

`test/reader_guide_localization_test.dart` verifies all three EPUBs, chapter count,
metadata, stable serialization, independent positions and unchanged story content.
