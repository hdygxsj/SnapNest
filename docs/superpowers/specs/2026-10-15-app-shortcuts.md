# Per-application shortcuts and on-demand island

Each installed application can have one persistent global shortcut. The launcher row opens an inline editor in the existing panel. Users choose modifiers and a physical key, save, replace or clear. Require Command, Control or Option so ordinary typing is not intercepted. Reject built-in shortcuts, common system combinations, duplicates and failed OS registrations. A failed replacement keeps the previous binding active. Saved bindings are restored at startup and remain available even when the panel is hidden. Successful activation opens or focuses the target application; moved/deleted apps report an actionable error without dropping their binding.

The island defaults to hidden when collapsed. Use a new preference key so the old default-on setting does not keep older installations permanently floating. Users may explicitly enable persistent task count. Menu-bar and global panel shortcuts remain available. Capture suppression still hides the panel. No external publication; retain private version 2.0.0 with incremented internal build.

Verify with fake shortcut registration: persistence/reload, duplicate and reserved combinations, rollback on failure, replacement/removal releasing registrations, restore failures. Verify hidden-default preference, compile, native inline editor and universal packaging.
