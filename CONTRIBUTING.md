# Contributing to Be@Mandaluyong

## Getting set up

```
flutter pub get
flutter run
```

See `README.md` for an overview of the app and `CLAUDE.md` for detailed
architecture notes (project structure, state management, persistence
patterns, etc.) before making non-trivial changes.

## Making a change

`main` is protected — changes go through a pull request, not a direct push.

1. Create a branch off `main`:
   ```
   git checkout -b your-branch-name
   ```
2. Make your changes, following the existing conventions in `CLAUDE.md`
   (flat `lib/` structure — one file per feature, no nested folders;
   build on the shared tokens in `theme.dart` rather than hardcoding
   spacing/colors; use `shared_preferences` for local persistence).
3. Verify before opening a PR:
   ```
   flutter analyze
   flutter test
   ```
4. Push your branch and open a pull request against `main`.

## Reporting issues

Open a GitHub issue with steps to reproduce, expected vs. actual
behavior, and your device/OS if it's a runtime bug.
