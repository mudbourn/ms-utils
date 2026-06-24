-- mudscript bootstrap — see DOCS_MAC.md § 20 for the tamper-protection model.
-- Read-only after install (chmod 444) for the strongest tamper resistance.

if _G.__ms_appWatcher then pcall(function() _G.__ms_appWatcher:stop() end) end

hs.loadSpoon("MsGuardian")
