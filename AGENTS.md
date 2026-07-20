# Marionette MCP

The Marionette MCP server should be used for UI tasks.

The `take_screenshots` tool is great for visual analysis—just remember to remove any saved image files once you're done with them.

## Example (Windows)

Check whether the app is running:

```powershell
Get-CimInstance Win32_Process -Filter "Name='dart.exe'" | ForEach-Object {
  $cl = $_.CommandLine
  if (-not $cl) { return }
  if ($cl -notlike "*Package: tic_tac_go*") { return }
  if ($cl -notmatch '--vm-service-uri=(https?://\S+)') { return }

  $http = $Matches[1].TrimEnd('/')
  $ws = $http -replace '^https://', 'wss://' -replace '^http://', 'ws://'
  if ($ws -notmatch '/ws$') { $ws = "$ws/ws" }

  [pscustomobject]@{
    Pid     = $_.ProcessId
    Http    = $http
    Ws      = $ws
  }
}
```

Connect to the app if it was found; if not, use `flutter run -d windows` to start it.

# Dart MCP

When using the Dart MCP `analyze_files` tool, analyze the entire project instead of using `paths`.

# Dart coding

`.dart` files in this repo can be found in the `lib/` directory or one of its subdirectories.

When in doubt, read more.
- Seek out a thorough understanding of this codebase and its dependencies before making changes.
- Assume that your previous changes may have been tweaked or refactored since you last saw them, and re-read before making further edits.

## Coding style

Use [dot shorthands](https://dart.dev/language/dot-shorthands) to improve readability, for instance when passing arguments to named parameters. (Avoid shortening unnamed constructors to `.new()`).

Avoid defining global or `static` fields that are only used once, if they can just be inlined.

Avoid writing comments when it's possible to write self-documenting code instead. Don't use comments as headers to split a file into multiple sections.

Avoid using 1 or 2-letter variable names. Prefer [destructuring class instances](https://dart.dev/language/patterns#destructuring-class-instances) when using a single object to assign multiple local variables.

```dart
void foo(Rect rect) {
  // BAD
  final Offset a1 = rect.topLeft;
  final Offset a2 = rect.bottomRight;
  final Offset b1 = rect.topRight;
  final Offset b2 = rect.bottomLeft;

  // GOOD
  final Rect(:topLeft, :topRight, :bottomLeft, :bottomRight) = rect;
}
```

## get_hooked package

This project uses **get_hooked** for reactive state management; it's declared as a local path dependency in `pubspec.yaml`.

# Firebase

To update the [web release](https://play.tic-tac-go.app/), run:

```powershell
flutter build web --wasm --release
firebase deploy --only hosting
```