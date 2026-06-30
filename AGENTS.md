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

# Accessing Dart files

Every `.dart` file can be found in the `lib/` directory or one of its subdirectories.
