# Changelog

All notable changes to this project are documented here. The release workflow
(`.github/workflows/release.yml`) publishes a GitHub Release whenever the
version in `pubspec.yaml` is bumped on `main`, and uses the matching `## x.y.z`
section of this file as the release notes.

## 0.2.0

- Localization scaffolding: all 177 user-facing strings extracted to ARB
  (`lib/l10n/app_en.arb`) via `gen_l10n`; adding a language is now just a new
  `app_<locale>.arb`. Rendered English text is unchanged.
- In-app text viewer: text-like files (txt/md/json/code/…) now open in a
  selectable monospace preview with Details and "Open with…" in the app bar.
  Files over 1 MiB aren't fetched — the viewer offers the open-with hand-off.
- Accessibility: tooltips on all icon-only controls, semantic labels on media
  grid tiles, screen-reader values on transfer progress bars, theme-aware
  hint/error colors (fixed greys failed contrast in dark mode), scrims behind
  play-badges over thumbnails, and full-size touch targets in the details
  sheet.
- App branding: adaptive launcher icon (with Android 13+ themed/monochrome
  variant), legacy icon for API 23–25, launcher label "Quantum Files", and a
  branded splash screen (native Android 12+ splash attributes; drawable-based
  splash on older versions). SVG masters + render script live in `tool/brand/`.
- Resumable chunked uploads for files over 10 MiB (quantum's offset-header
  scheme): graceful pause/resume mid-file, automatic retry of transient
  failures, exact progress. Small files still go out as a single background
  POST that survives the app being closed.
- Allow `http://` server URLs for loopback hosts only (`localhost`,
  `127.0.0.1`, emulator `10.0.2.2`) — fixes the integration suite, which the
  blanket HTTPS enforcement had broken; remote servers still require HTTPS.
- Automated release pipeline: bumping the version on `main` builds a signed
  APK and publishes a GitHub Release with notes from this file.

## 0.1.0

Initial release.

- Direct login behind a biometric gate; credentials in the Android Keystore,
  JWT keep-alive via renew + 401 replay.
- Multi-source browsing with breadcrumbs, persisted sort, multiselect batch
  copy / move / delete / download, destination picker, new folder, rename.
- Search, file details with on-demand checksum, server status with disk usage.
- Share links (create / list / delete, optional password and expiry).
- In-app image gallery and video player streaming with Bearer auth.
- Background uploads/downloads via a foreground service, upload conflict
  handling (overwrite / skip / keep-both), transfers screen, share-into-app,
  download save-location picking, open-with hand-off.
- HTTPS enforced app-wide; backup and device-to-device transfer disabled.
