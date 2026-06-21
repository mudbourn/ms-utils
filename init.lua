-- mudscript bootstrap — do not modify.
-- All logic lives in ms_core.lua, verified by MsGuardian.spoon before loading.
--
-- For the strongest tamper resistance, make this file read-only after install:
--   chmod 444 ~/.hammerspoon/init.lua

-- Tear down any watchers/timers left over from the previous load generation
-- before the Spoon runs its hash check.  This mirrors the guard that used to
-- live at the top of init.lua itself.
if _G.__ms_appWatcher then pcall(function() _G.__ms_appWatcher:stop() end) end

hs.loadSpoon("MsGuardian")
