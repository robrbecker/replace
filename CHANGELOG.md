## [1.2.3] - 2026-05-26
### Added
- Added `pm set-asdf-dart` to read `environment.sdk` from `pubspec.yaml` and run `asdf set dart` for Dart 2 (`2.19.6`) or Dart 3.
- Added `--dart-3-version` to `pm set-asdf-dart` so the Dart 3 version can be overridden (default: `3.11.6`).
- Added global `--pub-get` to run `dart pub get` in directories where a command modified `pubspec.yaml`.

### Updated
- Updated `pm` tests to cover `set-asdf-dart` behavior for Dart 2, Dart 3, and custom `--dart-3-version` values.
- Updated README command docs and examples for `set-asdf-dart` and `--dart-3-version`.
- Updated `pm` tests and docs for `--pub-get` behavior on changed and unchanged pubspecs.
- Updated `set-asdf-dart` to support recursive mode (`-r`) across discovered `pubspec.yaml` files.
- Updated `tighten -r` to use each pubspec directory's `pubspec.lock` by default.

## [1.2.0] - 2026-04-13
### Added
- Added `pm remove` to remove one or more packages from `dependencies` and `dev_dependencies`.
- Added global `pm --version` / `pm -v` output using generated package metadata.
- Added pubspec code generation with `pubspec_generator` and `build_runner`.

### Updated
- Updated CI to run `dart run build_runner build --delete-conflicting-outputs` and fail when generated files are out of date.
- Updated `pm` tests and fixtures for multi-package remove behavior across single-line, hosted, and git dependency declarations.
- Updated README documentation for `pm remove` and version flag usage.

## [1.1.0] - 2026-03-20
### Added
- Added the new `pm` CLI for editing pubspec dependency and SDK constraints.
- Added the `tighten` command to raise dependency minimums to lockfile-resolved versions.
- Added the `--[no-]tighten` option (enabled by default) for range-tightening behavior.

### Updated
- Updated tests and naming around the new `pm` functionality.
- Updated CI usage and formatting-related maintenance.

## [1.0.4] - 2022-05-11
- bug fix

## [1.0.3] - 2022-05-11
- bug fix

## [1.0.2] - 2022-05-04
### Updated
- support multiple filenames
- support ALL files under a directory easily
- better examples in the readme
- replacement errors doesn't end the whole program
- ignore dotfiles

## [1.0.1] - 2021-10-13
### Updated
- Updated readme

## [1.0.0] - 2021-10-13
### Added
- Initial Version

[1.0.0]: https://github.com/robrbecker/replace/releases/tag/1.0.0
