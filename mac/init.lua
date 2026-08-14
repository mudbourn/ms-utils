-- mudscript bootstrap — see DOCS_MAC.md § 20 for the integrity-protection model.
-- Read-only after install (chmod 444) for the strongest tamper resistance.

if _G.__ms_appWatcher then pcall(function() _G.__ms_appWatcher:stop() end) end

-- Disarm the restart hard-kill backstop (ms_settings _armExternalHardKill):
-- reaching here means a reload actually booted, so the external watchdog must
-- not kill this healthy instance. Cleared first thing, before any heavy boot
-- work, to keep the false-kill window as small as possible.
pcall(function() os.remove(hs.configdir .. "/data/.ms_restart_pending") end)

-- Guardian verifies hashes, then dofile's ms_core.lua itself.
require("lib.ms_guardian")()
