#!/usr/bin/env pwsh
# Pre-flight check for the "Update NeoCade Theme subtree" task.
# Aborts with a clear actionable message if addons/neocade_theme/ has
# uncommitted changes — common cause is a stale IDE buffer auto-saving
# older content over the freshly-pulled file.

$dirty = git status --porcelain addons/neocade_theme/
if ($dirty) {
    Write-Host ""
    Write-Host "ERROR: addons/neocade_theme has uncommitted changes:" -ForegroundColor Red
    Write-Host $dirty
    Write-Host ""
    Write-Host "Common cause: a stale IDE buffer auto-saved its older content over the freshly-pulled file." -ForegroundColor Yellow
    Write-Host "Fix: close the file(s) in your editor (or Ctrl+Shift+P > Revert File to discard the buffer and reload from disk)," -ForegroundColor Yellow
    Write-Host "     then re-run this task."
    exit 1
}
