# Launcher polish and installer cleanup

Approved direction: favorites cards + compact results, same workspace and theme.
Implementation stays on private branch; no public upload.

- [x] Restyle QuickLauncherView with centered max-width content, search, add menu, horizontal favorites cards, compact rows, selected/hover shortcut entry and keyboard hints. Preserve controller selection/search and global bindings.
- [x] Keep existing inline shortcut editor and URL form. Check keyboard navigation, empty results and light/dark appearance.
- [x] Run Tests/LauncherChecks/run.sh, Tests/AppShortcutChecks/run.sh and native build; package build 14 for both architectures.
- [x] Inspect native launcher and actual shortcut editor, verify final ZIP/signature.
- [x] Inventory archives using Spotlight plus home-folder scan excluding source dependencies and private user media. Move only confirmed old SnapNest/拾图/轻屿 installer archives to Trash after latest ZIP validates; retain installed apps and user data. Record exact moved paths. Keep newest archive.
