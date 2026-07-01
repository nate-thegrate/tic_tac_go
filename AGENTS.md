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

# Dart coding

## Accessing files

Every `.dart` file can be found in the `lib/` directory or one of its subdirectories.

## Coding style

Use [dot shorthands](https://dart.dev/language/dot-shorthands) when passing arguments to named parameters (but avoid shortening an unnamed constructor to `.new()`).

Prefer [destructuring class instances](https://dart.dev/language/patterns#destructuring-class-instances) when using a single object to assign multiple local variables. Avoid using 1 or 2-letter variable names.

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

When awaiting multiple independent futures, use a record of futures with [`.wait`](https://api.dart.dev/dart-async/FutureRecord2/wait.html) and destructure the results.

```dart
// BAD
final programs = await Future.wait([
  ui.FragmentProgram.fromAsset('shaders/paper.frag'),
  ui.FragmentProgram.fromAsset('shaders/pencil.frag'),
]);
paperShader = programs[0].fragmentShader();
pencilShader = programs[1].fragmentShader();

// GOOD
final (paper, pencil) = await (
  ui.FragmentProgram.fromAsset('shaders/paper.frag'),
  ui.FragmentProgram.fromAsset('shaders/pencil.frag'),
).wait;
paperShader = paper.fragmentShader();
pencilShader = pencil.fragmentShader();
```
