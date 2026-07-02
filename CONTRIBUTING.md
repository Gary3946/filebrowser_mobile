# Contributing

Thanks for helping improve the Filebrowser Quantum Android client.

## Setup

Flutter 3.44.4 / Dart 3.12 (the version CI pins). The `Makefile` prepends
`$HOME/flutter/bin` to `PATH` when `flutter` isn't already resolvable.

```bash
make get       # flutter pub get
make analyze   # static analysis (must be clean)
make test      # unit + widget tests (no server needed)
make ci        # get + analyze + test — mirrors the PR gate
```

## Integration tests

`test/integration/quantum_api_test.dart` runs a real `FileBrowserClient`
against a live Filebrowser Quantum server. They are skip-by-default so plain
`make test` needs no server.

```bash
make serve     # boot the official quantum test server on :8080
make e2e       # serve + run integration-tagged tests + stop the server
```

## Pull requests

- Keep `flutter analyze` clean; lints are intentionally strict
  (`analysis_options.yaml`).
- Add or update tests for behavior you change. UI logic is widget-tested;
  API-contract changes belong in the integration suite too.
- CI runs both a `unit` job and an `integration` job against a real quantum
  server; both must pass.
- Update `CHANGELOG.md` under the upcoming version's section when your change
  is user-visible.

## Releases (maintainers)

Bump `version:` in `pubspec.yaml` on `main` and add a matching `## x.y.z`
section to `CHANGELOG.md`. The release workflow builds a signed APK, tags
`vx.y.z`, and publishes a GitHub Release with the changelog section as notes.
Bumping only the build number (after `+`) does not trigger a release.
