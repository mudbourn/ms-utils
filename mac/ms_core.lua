-- Core System ---- PLEASE EDIT CAREFULLY --
    -- Hammerspoon mudscript Utility Library --
        -- 0. Pre-Load --
            -- hs.reload() leaves stale objects. Stop the prior generation before
            -- this load creates a new one. The primary guard is in init.lua.
                if _G.__ms_appWatcher then pcall(function() _G.__ms_appWatcher:stop() end) end
-- END 0. Pre-Load --

            -- Guardian moved to MsGuardian.spoon/init.lua --
-- END Guardian moved to MsGuardian.spoon/init.lua --

            -- One-time migration: move settings/hash files from root into data/ --
                do
                    local _h = os.getenv("HOME") .. "/.hammerspoon"
                    os.execute("mkdir -p '" .. _h .. "/data'")
                    local function _mvToData(name)
                        local src = _h .. "/" .. name
                        local dst = _h .. "/data/" .. name
                        if hs.fs.attributes(dst) then return end
                        if not hs.fs.attributes(src) then return end
                        local f = io.open(src, "rb"); if not f then return end
                        local c = f:read("*all"); f:close()
                        local g = io.open(dst, "wb"); if not g then return end
                        g:write(c); g:close(); os.remove(src)
                    end
                    _mvToData("ms_settings.json")
                    _mvToData("ms_settings_default.json")
                    _mvToData(".ms_trusted_hash")
                end
-- END One-time migration: move settings/hash files from root into data/ --

            -- Font installation --
                do
                    local _h       = os.getenv("HOME") .. "/.hammerspoon"
                    local _srcDir  = _h .. "/ui/fonts/"
                    local _dstDir  = os.getenv("HOME") .. "/Library/Fonts/"
                    local _installed = false
                    hs.fs.mkdir(_dstDir)
                    if hs.fs.attributes(_srcDir) then
                        for _file in hs.fs.dir(_srcDir) do
                            if _file ~= "." and _file ~= ".." then
                                local _ext = _file:match("%.([^%.]+)$")
                                if _ext == "ttf" or _ext == "otf" or _ext == "woff" or _ext == "woff2" then
                                    local _dst = _dstDir .. _file
                                    if not hs.fs.attributes(_dst) then
                                        local _f = io.open(_srcDir .. _file, "rb")
                                        if _f then
                                            local _c = _f:read("*all"); _f:close()
                                            local _g = io.open(_dst, "wb")
                                            if _g then _g:write(_c); _g:close(); _installed = true end
                                        end
                                    end
                                end
                            end
                        end
                    end
                    if _installed then
                        hs.reload(); return
                    end
                end
-- END Font installation --
-- END Hammerspoon mudscript Utility Library --

        -- 1. Prefix Variables & State Tracking --
            ms = {}
            ms.vars = {}
            ms.keytrack = {}
            ms._keyBindings = {}
            ms.bindConfig = {}
            ms.bindHandles = {}
            ms._activeSub = nil
            ms.systemBinds             = { _config = {}, _handles = {} }
            ms.modConfig             = {}
            ms.subBinds              = {}
            ms.independentBindsEnabled = false
            ms.trackpadMode          = false
            ms.trackpadHoldKeys      = { left = "n", right = "j" }
            ms.socdMode              = "lastWins"
            ms.socdEnabled           = false
            ms.trackpadBindOverrides = {
                superJump     = {type="key", mods={}, key="k"},
            }
            ms.binds                 = {}
            ms.running   = {}  -- { [groupId] = timerHandle } — populated on fire, cleared on expiry
            ms.cooldowns = {}  -- user cooldown overrides: { [id] = N ms }
            ms._robloxActive = false  -- kept current by the app watcher; no OS call needed on keypress
            ms._menuOpen     = false  -- persistent-session flag: set on open, cleared by Alt+P close only
            ms._menuVisible  = false  -- true only while popupMenu is blocking; cleared on every return
            ms._menuFnFired  = false  -- true when an item fn ran during the current popupMenu session
            ms._menuHoverWatcher = nil   -- AX accessibility observer for mouse-hover sounds
            ms._playSlotTimes    = {}    -- per-slot last-play timestamps for duplicate suppression
            ms._slotHandles      = {}    -- per-slot last sound handle; stopped before each new play
            ms._currentFlags     = {}    -- modifier flags at last keyDown dispatch
            ms._pendingReopenToSound = false  -- set by Import Sound Files to reopen directly at the sound submenu
            ms._inputOpen    = false  -- true while a Hammerspoon dialog has focus (suppress state toasts)
            ms._macroHeldKeys    = {}  -- keyCode → {mods, hidinject}  keys held by macro presses
            ms._macroHeldButtons = {}  -- btn-number → {upT, pos, app}  buttons held by macro presses
            ms._coroContext      = {}  -- coroutine → cancel-context
            ms._activeContexts   = {}  -- cancel-context → true
            ms.registry              = { _defs = {}, _defList = {} }
            ms.bind                  = { _wires = {}, _autoCount = 0 }
            roblox = hs.application.get("Roblox")
            -- ms._targetHandle is refreshed on every reload via the target app lookup.

            ms._targetApp     = "Roblox"                   -- target application name; change via ms.setTargetApp()
            ms._targetHandle  = hs.application.get(ms._targetApp)  -- cached handle, refreshed on reload
            ms._robloxActive  = false  -- true while target app is focused
            ms._qrOptions = { macros = true, theme = true, settings = true, ui = true }
            ms.getTargetWin = function()
                local app = hs.application.get(ms._targetApp)
                if not app then return nil end
                local ok, win = pcall(function() return app:mainWindow() end)
                return (ok and win) or nil
            end

            -- Change the target application at runtime. Refreshes the cached handle
            -- and forces a watcher re-check. Pass nil to disable target-specific behavior.
            ms.setTargetApp = function(name)
                ms._targetApp    = name or nil
                ms._targetHandle = name and hs.application.get(name) or nil
                if ms._targetHandle then
                    ms._robloxActive = true
                end
            end
            notice = 0
            loadfinish = 0
            REF_W = 1680
            REF_H = 1044
            REF_SENS = 1.5
            -- ms.Mouse named constants — operations, buttons, references.
            -- Plain string globals; accessible from ms_macros.lua via the sandbox fallback.
            -- Typos error immediately at ms.Mouse call time rather than silently misfiring.
            Move        = "Move";    Click       = "Click";    DoubleClick = "DoubleClick"
            TripleClick = "TripleClick";   Drag   = "Drag";    Press       = "Press";    Release     = "Release"
            Left        = "Left";    Right       = "Right";   Center      = "Center"
            Button4     = "Button4"; Button5     = "Button5"
            Unscaled    = true   -- pass between reference and x1 in ms.Mouse for raw pixel window offsets
            Absolute     = "Absolute";  Mouse        = "Mouse"
            WindowTL     = "WindowTL";  WindowTR     = "WindowTR"
            WindowBL     = "WindowBL";  WindowBR     = "WindowBR";  WindowCenter = "WindowCenter"
            ScreenTL     = "ScreenTL";  ScreenTR     = "ScreenTR"
            ScreenBL     = "ScreenBL";  ScreenBR     = "ScreenBR";  ScreenCenter = "ScreenCenter"
            BindValidity = 1
            SoundLib = os.getenv("HOME") .. "/.hammerspoon/sounds/"
            ms.sounds          = {}     -- name → path; populated by _discoverSounds
            ms.importedSounds  = {}     -- name → filename; persisted in settings — source of truth for the menu
            ms.soundEnabled    = true   -- master on/off
            ms.soundVolume     = 100    -- 0–100
            ms.soundAssign     = {}     -- per-slot overrides: { slotId = soundName }
            ms._docsURL           = "https://docs-ms.mudbourn.info"  -- opened by Settings › Documentation
            ms._updateManifestURL = "https://raw.githubusercontent.com/mudbourn/ms-utils/main/MANIFEST.json"
            ms._updateChannel     = "stable"  -- "stable" (MANIFEST.json) or "testing" (GitHub Actions)
            ms._branchTrace       = true
            ms._testingWorkflow   = "testing" -- workflow filename (without .yml) for the testing channel
            ms._testingRepo       = "mudbourn/ms-utils"  -- GitHub owner/repo for Actions API

            -- RSA-2048 public key for MANIFEST.json signature verification.
            -- Matching private key: GitHub Secrets (MS_SIGNING_KEY).
            ms._updatePublicKey = [[
            -----BEGIN PUBLIC KEY-----
            MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA3pyxWISHUScKsmK0fyqA
            QWUU0nzYEVpRYD+kRkZsL5AGqpjfNqfOky5bacE1jPXgu9LGz+b1pq1tuyZotvK/
            FrMeQDCmGWiu5RXAqsyg0iN1c1CHSvWAT40xi6g54u9ot9LMfzmBETlwWd4QoXOA
            OnT3KW0aia1EoyUjjNIRk6iv6pxi+BjHnGKoID6pAl9de+WASt/DETgCuKhQ7o/Y
            iGn43A9ZutKUfkV+Muu1RcTy62zbXcQrzK3cyLl0M7gfTm0YWPzaf+d3ATNnq/9j
            /952QfmXjVSGhU3EBxlEM6NWstNSNuaTWSMCcbcH+va/AMOHK1rRKQ3IOdzjYcQm
            YQIDAQAB
            -----END PUBLIC KEY-----
            ]]

            -- User Settings & Menu API State --
                ms.settings          = {}  -- user settings API namespace
                ms.menu              = {}  -- custom section API namespace (ms.menu.define)
                ms._menubar          = nil  -- hs.menubar instance (menu-bar icon); set in Section 7
                ms.features          = {}  -- feature visibility API namespace
                ms._userSettingDefs  = {}  -- ordered list of all setting/item definitions
                ms._userSettingIndex = {}  -- key → def, for O(1) lookup
                ms._userSettingVals  = {}  -- key → current live value
                ms._userMenuDefs     = {}  -- ordered list of ms.menu.define() entries
                ms._hiddenFeatures   = {}  -- set: name → true (from ms.features.hide())
                -- Theme defaults — matches the shipped data/ms_theme.json baseline.
                -- ms.loadTheme() overrides these with the user's file at startup.
                ms._themeDefaults = {
                    bg       = "#060402",
                    surface  = "#100806",
                    surface2 = "#1c100c",
                    hover    = "#301610",
                    accent   = "#c41a1a",
                    accentHi = "#e52424",
                    success  = "#4a7820",
                    dangerBg = "#1e0608",
                    danger   = "#d42020",
                    warning  = "#c47820",
                    text     = "#f0ddb0",
                    radius   = 3,
                    font     = "Almendra",
                    fadeMs   = 150,
                }
                ms._theme = {}
                for k, v in pairs(ms._themeDefaults) do ms._theme[k] = v end
                ms._themeLoaded = false  -- set true by ms.loadTheme() when a file loads successfully

                require("hs.eventtap")
                require("hs.mouse")
                require("hs.uielement")
                require("hs.timer")
                require("hs.hotkey")
                require("hs.json")
                require("hs.keycodes")
                require("hs.canvas")
                require("hs.window")
                require("hs.screen")
                require("hs.menubar")
                require("hs.application")

                -- Developer Tools — MsDevTools.spoon --
                local _msDevOk, _msDevErr = pcall(function()
                    hs.loadSpoon("MsDevTools")
                    spoon.MsDevTools:init()
                end)

                if not _msDevOk then
                    print("MsDevTools: load failed — " .. tostring(_msDevErr))
                end

                -- Developer Tools — populated by MsDevTools:start() --
                if spoon.MsDevTools then
                    spoon.MsDevTools:start()
                else
                    ms.dev = {
                        _consolePanel    = nil,
                        _watcherPanel    = nil,
                        _keysPanel       = nil,
                        _consolePanelPos = nil,
                        _watcherPanelPos = nil,
                        _keysPanelPos    = nil,
                        _activeKeys      = {},
                        _activeButtons   = {},
                        _coordMode       = "screen",
                        _keysReady       = false,
                    }

                    ms.dev.log = function() end
                    ms.dev._onMacroFire  = function() end
                    ms.dev._onKeyEvent   = function() end
                    ms.dev._onMouseEvent = function() end

                    ms.dev.console = { show = function() end, hide = function() end, toggle = function() end }
                    ms.dev.watcher = { show = function() end, hide = function() end, toggle = function() end }
                    ms.dev.keys    = { show = function() end, hide = function() end, toggle = function() end }
                    ms.dev.window  = { show = function() end, hide = function() end, toggle = function() end }

                    ms.dev.prewarm     = function() end
                    ms.dev.prewarmStep = function() end
                    ms.dev.step        = function() end
                    ms.dev._pushMouseState = function() end

                    -- Stub so spoon.MsDevTools:* calls don't crash.
                    spoon.MsDevTools = {
                        flushAll         = function() end,
                        flushCam         = function() end,
                        flushWait        = function() end,
                        watcherStep      = function() end,
                        macroLog         = function() end,
                        accCamMove       = function() end,
                        accWait          = function() end,
                        startTrace       = function() end,
                        stopTrace        = function() end,
                        flushTraceBuffer = function() end,
                        setTraceSuppress = function() end,
                        getTraceSuppress = function() return false end,
                    }

                    print("MsDevTools: running without dev panels (spoon not loaded)")
                end

                hs.timer.doAfter(0.3, function()
                    local roblox = hs.application.get("Roblox")
                    if roblox then
                        -- Seed _robloxActive now so the Hammerspoon step of the bounce
                        -- correctly triggers ms._inputOpen via the app watcher.
                        -- Without this the watcher sees _robloxActive=false and skips
                        -- setting _inputOpen, causing a spurious ENABLED toast on return.
                        ms._robloxActive = true

                        -- Bounce through Hammerspoon so macOS registers a genuine fresh
                        -- Roblox activation. A direct roblox:activate() is a no-op when
                        -- Roblox is already frontmost (common after a reload from the
                        -- Hammerspoon console) and never fires the app watcher, leaving
                        -- ms._inputOpen stuck true for the rest of the session.
                        local hs_app = hs.application.get("Hammerspoon")
                        if hs_app then hs_app:activate() end

                        hs.timer.doAfter(0.25, function()
                            -- Re-fetch the app handle; the captured reference can become
                            -- stale between the outer and inner timer callbacks.
                            local app = hs.application.get("Roblox") or roblox
                            local ok, win = pcall(function() return app:mainWindow() end)
                            if ok and win then pcall(function() win:focus() end) end
                            pcall(function() app:activate() end)
                        end)
                    end
                end)
-- END Developer Tools — populated by MsDevTools:start() --
-- END Developer Tools — MsDevTools.spoon --

        -- 2. Conditions, States, and UI Elements--
            ms.app = function() return hs.application.frontmostApplication():name() end

            -- Alerts — MsAlert.spoon --
                local _msAlertOk, _msAlertErr = pcall(function()
                    hs.loadSpoon("MsAlert")
                end)

                if not _msAlertOk then
                    print("MsAlert: load failed — " .. tostring(_msAlertErr))
                end

                if spoon.MsAlert then
                    ms.alert = spoon.MsAlert
                else
                    ms.alert = setmetatable({
                        dismissAll   = function() end,
                        dismissById  = function() end,
                        updateById   = function() return false end,
                    }, {
                        __call = function(_, msg) print("MsAlert stub: " .. tostring(msg)) end,
                    })

                    print("MsAlert: running without toast system (spoon not loaded)")
                end
            -- END Alerts --

            -- Settings Menu --
                local settingsPath    = os.getenv("HOME") .. "/.hammerspoon/ms_settings.txt"
                local jsonPath        = os.getenv("HOME") .. "/.hammerspoon/data/ms_settings.json"
                local defaultPath     = os.getenv("HOME") .. "/.hammerspoon/data/ms_settings_default.json"
                local archivePath     = os.getenv("HOME") .. "/.hammerspoon/backups/"
                local macrosPath      = os.getenv("HOME") .. "/.hammerspoon/ms_macros.lua"
                local profilesPath    = os.getenv("HOME") .. "/.hammerspoon/profiles/"
                local corePath        = os.getenv("HOME") .. "/.hammerspoon/ms_core.lua"
                local trustedHashPath = os.getenv("HOME") .. "/.hammerspoon/data/.ms_trusted_hash"
                local themePath       = os.getenv("HOME") .. "/.hammerspoon/data/ms_theme.json"

                ms.bindConfig = {}
                ms.bindHandles = {}

                ms.parseBind = function(str)
                    local btn = str:match("^mouse:(%d+)$")
                    if btn then return {type="mouse", button=tonumber(btn)} end
                    local mods = {}
                    local parts = {}
                    for part in str:gmatch("[^+]+") do
                        table.insert(parts, part:lower())
                    end
                    local modkeys = {cmd=true, alt=true, ctrl=true, shift=true}
                    local key = nil
                    for _, part in ipairs(parts) do
                        if modkeys[part] then
                            table.insert(mods, part)
                        else
                            key = part
                        end
                    end
                    if key then return {type="key", mods=mods, key=key} end
                    return nil
                end

                -- User Settings — validation helpers --
                    local _SETTING_TYPES = {
                        toggle = true, sl

... [OUTPUT TRUNCATED - 414110 chars omitted out of 464110 total] ...

             rawset(ms, k, v)
                        else
                            error("ms_macros.lua: unauthorized write to ms." .. tostring(k)
                                .. "  —  only ms.macroMeta and ms.bind.define are permitted.", 2)
                        end
                    end,
                })

                -- Globals that are explicitly blocked and will error on access.
                local BLOCKED = {
                    hs=true, require=true, os=true, io=true,
                    _G=true, load=true, loadfile=true, loadstring=true,
                    dofile=true, rawget=true, rawset=true,
                    debug=true, package=true, collectgarbage=true,
                    setfenv=true, getfenv=true,
                    setmetatable=true, getmetatable=true,
                    -- Live globals reachable via the _G fallthrough that macro code
                    -- must not touch.  These are the runtime counterparts of the
                    -- scanner-only checks (:activate, :launch, etc.): even if the
                    -- lexer pass above is somehow confused, access is still denied here.
                    roblox=true,               -- hs.application handle; :activate() risk
                    -- _G-scoped handles that carry dangerous methods (:stop() etc.).
                    -- Macro code must not be able to halt the integrity timer, kill the
                    -- app watcher, or otherwise manipulate Hammerspoon's own internals.
                    __ms_appWatcher=true,        -- hs.eventtap: :stop() kills app monitoring
                    _integrityPollTimer=true,    -- hs.timer: :stop() disables integrity poll
                    _initTimer=true,             -- hs.timer: deferred init timer
                }

                local sandbox = {
                    ms        = frozenMs,
                    -- Safe Lua builtins
                    math      = math,
                    string    = string,
                    table     = table,
                    coroutine = coroutine,  -- needed until ms.fn replaces direct coroutine use
                    ipairs    = ipairs,
                    pairs     = pairs,
                    next      = next,
                    select    = select,
                    pcall     = pcall,
                    xpcall    = xpcall,
                    tostring  = tostring,
                    tonumber  = tonumber,
                    type      = type,
                    unpack    = table.unpack or unpack,
                    error     = error,
                    assert    = assert,
                    print     = print,
                    -- ms.Mouse operation constants (seeded explicitly so the sandbox
                    -- __newindex cannot overwrite them in _G via the fallthrough).
                    Move        = Move,        Click       = Click,       DoubleClick  = DoubleClick,
                    TripleClick = TripleClick, Drag        = Drag,        Press        = Press,
                    Release     = Release,
                    -- ms.Mouse button constants
                    Left        = Left,        Right       = Right,       Center       = Center,
                    Button4     = Button4,     Button5     = Button5,
                    -- ms.Mouse reference constants
                    Unscaled     = Unscaled,
                    Absolute     = Absolute,   Mouse        = Mouse,
                    WindowTL     = WindowTL,   WindowTR     = WindowTR,
                    WindowBL     = WindowBL,   WindowBR     = WindowBR,   WindowCenter = WindowCenter,
                    ScreenTL     = ScreenTL,   ScreenTR     = ScreenTR,
                    ScreenBL     = ScreenBL,   ScreenBR     = ScreenBR,   ScreenCenter = ScreenCenter,
                }

                setmetatable(sandbox, {
                    __index = function(t, k)
                        if BLOCKED[k] then
                            error("ms_macros.lua: access to '" .. tostring(k)
                                .. "' is not permitted.", 2)
                        end
                        -- Primitive-only bridge to _G: allows string/number/boolean
                        -- constants that the macro author may define in init.lua to
                        -- remain accessible, while blocking every non-primitive type
                        -- (functions, tables, userdata, threads).  This closes the
                        -- open-ended _G fallthrough without breaking the init.lua
                        -- custom-constant pattern.  Once §1.2 (ms.fn) lands and all
                        -- coroutine use is wrapped, this can be tightened further to
                        -- error on any unlisted global regardless of type.
                        local v = rawget(_G, k)
                        local vt = type(v)
                        if vt == "string" or vt == "number" or vt == "boolean" or v == nil then
                            return v
                        end
                        error("ms_macros.lua: access to '" .. tostring(k)
                            .. "' is not permitted (non-primitive globals are not accessible from macros).", 2)
                    end,
                    -- All global writes from ms_macros.lua are forbidden.
                    -- Previously this fell through to rawset(_G, k, v), which let macro
                    -- code silently overwrite init.lua globals such as BindValidity and
                    -- REF_W. Now any bare global assignment is a hard error; macro
                    -- authors must use 'local' for all variables.
                    __newindex = function(t, k, v)
                        error("ms_macros.lua: cannot write global '" .. tostring(k)
                            .. "' — use 'local' for all variables.", 2)
                    end,
                })

                -- Store sandbox reference so ms.quickReload() can reuse it.
                ms._macroSandbox = sandbox

                -- Security audit: scan the raw source before any code is executed.
                -- Hard-errors on policy violations so a tampered file never reaches load().
                -- rawSrc is declared outside the do-block so the load() call below can
                -- compile the exact same bytes the auditor read, closing the TOCTOU window.
                local rawSrc
                do
                    local af = io.open(macrosPath, "r")
                    if not af then
                        error("ms_macros.lua: cannot open file for security audit: " .. macrosPath)
                    end
                    rawSrc = af:read("*all"); af:close()
                    local auditErrs = auditMacros(rawSrc)
                    if #auditErrs > 0 then
                        local msg = "ms_macros.lua failed security audit ("
                            .. #auditErrs .. " violation"
                            .. (#auditErrs > 1 and "s" or "") .. "):\n"
                        for _, e in ipairs(auditErrs) do
                            msg = msg .. "  \xe2\x80\xa2 " .. e .. "\n"
                        end
                        error(msg, 0)
                    end
                end

                -- Load the file with the sandbox as its environment.
                -- Lua 5.2+: loadfile accepts an env parameter directly.
                -- Lua 5.1 fallback: use setfenv if available.
                local chunk, loadErr
                if _VERSION and _VERSION >= "Lua 5.2" or not setfenv then
                    -- Use load() on the already-read source bytes rather than re-opening
                    -- the file with loadfile().  This closes the TOCTOU window: auditMacros
                    -- ran on rawSrc; load() compiles those exact same bytes, so there is no
                    -- opportunity for another process to swap the file between the audit
                    -- read and the load step.
                    chunk, loadErr = load(rawSrc, "@ms_macros.lua", "bt", sandbox)
                else
                    -- Lua 5.1 fallback (LuaJIT should never reach here).
                    chunk, loadErr = loadstring(rawSrc, "@ms_macros.lua")
                    if chunk then setfenv(chunk, sandbox) end
                end
                if not chunk then
                    error("ms_macros.lua: failed to load: " .. tostring(loadErr))
                end
                local ok, runErr = pcall(chunk)
                if not ok then
                    error("ms_macros.lua: error during execution: " .. tostring(runErr))
                end

                -- Validation pass
                if not ms.macroMeta then
                    print("Warning: ms_macros.lua did not set ms.macroMeta.")
                    hs.timer.doAfter(0.5, function()
                        ms.alert("Warning: ms_macros.lua did not declare ms.macroMeta.", 6)
                    end)
                end
                if not next(ms.registry._defs) then
                    error("ms_macros.lua: no ms.bind.define calls found — file may be malformed.")
                end
            end

            -- Macro pack preferred defaults — seeded into ms_settings_default.json on first run.
            -- Defined here (not in ms_macros.lua) so they cannot be accidentally removed by the user.
            -- Values already saved in ms_settings.json always take priority and are never overwritten.
            ms.macroDefaults = {
                sensitivity  = 1.5,
                trackpadMode = false,
                socdEnabled  = false,
                socdMode     = "lastWins",
                macros = {
                    spawnAlt = { enabled = false },
                },
            }
-- END User Settings — validation helpers --
    -- END Hammerspoon mudscript Utility Library --

    -- Startup Executions --
        -- Privileged system actions: registered here (outside the sandbox) so
        -- macros cannot set or spoof them.  Each entry is keyed by the setting
        -- key it belongs to and called by userSettingAction after the sandboxed
        -- onAction has run.
        ms._systemActions = {}
        if ms._userSettingIndex["showTamperWarning"] then
            ms._systemActions["showTamperWarning"] = function()
                ms.showGuardian()
            end
        end

        -- Seed ms.binds from registry defaults for any id not set by the settings file.
        for _, id in ipairs(ms.registry._defList) do
            local def = ms.registry._defs[id]
            if def and not def.sub and ms.binds[id] == nil then
                ms.binds[id] = def.enabled
            end
        end
        ms._skipDevPrewarm   = false  -- overridden by loadSettings() if previously saved
        ms._devArchiveLimit   = 15     -- overridden by loadSettings() if previously saved
        ms._loadComplete   = false  -- gates macro activation; set to true by _announceLoad
        ms._discoverSounds()
        ms.loadSettings()
        ms.loadTheme()
        ms.cam.updateMultiplier()
        -- Clean up any stale update sentinel from a previous session.
        os.remove(os.getenv("HOME") .. "/.hammerspoon/data/.ms_update_pending")
        ms.bind._registerSystemBinds()
        ms.bind.rebind()
        ms.socdApply()
        BindValidity = 0  -- block macros during loading; _announceLoad re-enables when toasts fire
        ms._startupSoundDone = false  -- suppresses all non-load sounds until _announceLoad runs
        -- Startup Loading Indicator --
            -- Lightweight hs.canvas panel that shows progress while WebViews initialise
            -- in the background.  Each WebView creation is pushed into its own timer tick
            -- so the main thread never blocks for more than ~300 ms at a stretch.
            local _lCanvas, _lBarMax, _lBarY, _lFadingOut, _lFadeTimer
            local _lUpdate, _lFadeOut, _loadAnnounced, _announceLoad
            local _needsIntegrityWarning = false  -- set by the integrity timer; shown after announce toasts
            do
                local sf  = hs.screen.mainScreen():frame()
                local lw, lh = 300, 104
                local lx  = sf.x + math.floor((sf.w - lw) / 2)
                local ly  = sf.y + sf.h - 150 - lh  -- bottom edge aligns with toast baseline
                _lBarMax  = lw - 32
                _lBarY    = 62
                -- Derive palette from the loaded theme so the canvas respects the active profile.
                -- Falls back to the original dark crimson defaults when a key is absent.
                local function _themeColor(hex, fallR, fallG, fallB, alpha)
                    local r, g, b = (hex or ""):match("^#?(%x%x)(%x%x)(%x%x)$")
                    if r then
                        return {
                            red   = tonumber(r, 16) / 255,
                            green = tonumber(g, 16) / 255,
                            blue  = tonumber(b, 16) / 255,
                            alpha = alpha or 1.0,
                        }
                    end
                    return { red = fallR, green = fallG, blue = fallB, alpha = alpha or 1.0 }
                end
                local _t = ms._theme or {}
                local clrBg     = _themeColor(_t.bg,       0.024, 0.016, 0.008, 0.95)
                local clrAccent = _themeColor(_t.accent,   0.769, 0.102, 0.102, 1.0)
                local clrText   = _themeColor(_t.text,     0.941, 0.867, 0.690, 1.0)
                local clrText2  = _themeColor(_t.warning,  0.824, 0.647, 0.392, 0.72)
                local clrTrack  = _themeColor(_t.surface2, 0.063, 0.039, 0.024, 1.0)
                local clrBorder = _themeColor(_t.hover,    0.510, 0.196, 0.086, 0.55)
                -- Derive font: accept any plain name (no path separators), fall back to Almendra.
                local _titleFont = (type(_t.font) == "string" and #_t.font > 0
                    and not _t.font:find("[/\\]"))
                    and _t.font or "Almendra"
                _lCanvas = hs.canvas.new({ x=lx, y=ly, w=lw, h=lh })
                _lCanvas:level(hs.canvas.windowLevels.popUpMenu or 25)
                _lCanvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
                _lCanvas:alpha(0)
                _lCanvas:appendElements(
                    -- 1: background
                    { type="rectangle", action="strokeAndFill",
                      fillColor=clrBg, strokeColor=clrBorder, strokeWidth=1,
                      roundedRectRadii={ xRadius=5, yRadius=5 } },
                    -- 2: top accent strip
                    { type="rectangle", action="fill", fillColor=clrAccent,
                      frame={ x=0, y=0, w=lw, h=2 },
                      roundedRectRadii={ xRadius=5, yRadius=5 } },
                    -- 3: title (static)
                    { type="text", text="mudscript",
                      frame={ x=16, y=13, w=lw-32, h=22 },
                      textFont=_titleFont, textSize=15,
                      textColor=clrText, textAlignment="left" },
                    -- 4: status line (updated by _lUpdate)
                    { type="text", text="Starting up\xe2\x80\xa6",
                      frame={ x=16, y=37, w=lw-32, h=16 },
                      textFont="Helvetica Neue", textSize=11,
                      textColor=clrText2, textAlignment="left" },
                    -- 5: progress track
                    { type="rectangle", action="fill", fillColor=clrTrack,
                      frame={ x=16, y=_lBarY, w=_lBarMax, h=3 },
                      roundedRectRadii={ xRadius=1.5, yRadius=1.5 } },
                    -- 6: progress fill (frame.w updated by _lUpdate)
                    { type="rectangle", action="fill", fillColor=clrAccent,
                      frame={ x=16, y=_lBarY, w=0, h=3 },
                      roundedRectRadii={ xRadius=1.5, yRadius=1.5 } },
                    -- 7: separator above checkbox row
                    { type="rectangle", action="fill", fillColor=clrBorder,
                      frame={ x=16, y=75, w=_lBarMax, h=1 } },
                    -- 8: hit area — transparent full-width row, trackMouseDown for click detection
                    { type="rectangle", action="fill",
                      fillColor={ red=0, green=0, blue=0, alpha=0 },
                      frame={ x=16, y=80, w=_lBarMax, h=18 },
                      trackMouseDown=true },
                    -- 9: checkbox glyph (☐ / ☑) — updated on toggle
                    { type="text",
                      text=(ms._skipDevPrewarm and "\xe2\x98\x91" or "\xe2\x98\x90"),
                      frame={ x=17, y=80, w=18, h=18 },
                      textFont="Helvetica Neue", textSize=13,
                      textColor=clrText2, textAlignment="left" },
                    -- 10: label
                    { type="text", text="Skip dev tool preloading",
                      frame={ x=36, y=83, w=_lBarMax-22, h=14 },
                      textFont="Helvetica Neue", textSize=11,
                      textColor=(ms._skipDevPrewarm and clrText or clrText2),
                      textAlignment="left" },
                    -- 11: active profile name (right-aligned in the title row)
                    { type="text",
                      text=(ms.macroMeta and ms.macroMeta.name) or "",
                      frame={ x=16, y=15, w=lw-32, h=18 },
                      textFont="Helvetica Neue", textSize=10,
                      textColor=clrText2, textAlignment="right" }
                )
                _lCanvas:show()
                ms.playSlot("startup")  -- loading sequence start sound
                local function _lfade()
                    local step, steps = 0, 6
                    local t = hs.timer.doEvery((ms._theme.fadeMs or 150) / 1000 / steps, function()
                        step = step + 1
                        if _lCanvas then _lCanvas:alpha(step / steps) end
                        if step >= steps and t then t:stop() end
                    end)
                end
                _lfade()
                _lCanvas:mouseCallback(function(canvas, event, id, x, y)
                    if event ~= "mouseDown" or id ~= 8 then return end
                    ms._skipDevPrewarm = not ms._skipDevPrewarm
                    pcall(ms.saveSettings)
                    canvas[9].text       = ms._skipDevPrewarm and "\xe2\x98\x91" or "\xe2\x98\x90"
                    canvas[10].textColor = ms._skipDevPrewarm and clrText or clrText2
                    if ms._skipDevPrewarm and not _lFadingOut then
                        _lUpdate(100, "Developer tools skipped.")
                        hs.timer.doAfter(0.8, _lFadeOut)
                    end
                end)
            end

            _lUpdate = function(pct, msg)
                if not _lCanvas then return end
                _lCanvas[4].text  = msg
                _lCanvas[6].frame = {
                    x=16, y=_lBarY,
                    w=math.max(4, math.floor(_lBarMax * pct / 100)), h=3,
                }
            end

            -- Plays the load-complete sounds and shows the startup toasts.  Fires once
            -- (guarded by _loadAnnounced) — triggered from the canvas delete callback
            -- so it runs immediately after the loading screen is gone.
            -- doAfter(7.0) below acts as a fallback in case the canvas never fades.
            _announceLoad = function()
                if _loadAnnounced then return end
                _loadAnnounced = true
                -- Load-end sound fires the instant the canvas disappears.
                pcall(function() ms.playSlot("load") end)
                -- Brief pause before opening the gate so the load-end sound
                -- has a moment before any subsequent sounds can play.
                hs.timer.doAfter(0.4, function()
                    -- Open the sound gate for all future sounds.
                    ms._startupSoundDone = true
                    -- Launch sound plays with the first toast.
                    pcall(function() ms.playSlot("launch") end)
                    -- 1. Settings notice (immediate)
                    ms.alert("Macros loaded. Press \xe2\x8c\xa5 and P to open settings.", 3, true)
                    -- 2. Library creator \xe2\x80\x94 after first toast fades
                    hs.timer.doAfter(3, function()
                        ms.alert("Hammerspoon mudscript Utility Library\nBy: mudbourn \xe2\x80\x94 https://mudbourn.info", 3, true)
                    end)
                    -- 3. Macro pack creator \xe2\x80\x94 after second toast fades
                    hs.timer.doAfter(6, function()
                        if ms.macroMeta then
                            local msg = "\"" .. (ms.macroMeta.name or "Unknown Macro Pack") .. "\"\n"
                            if ms.macroMeta.author  then msg = msg .. "By: " .. ms.macroMeta.author end
                            if ms.macroMeta.website then msg = msg .. " \xe2\x80\x94 " .. ms.macroMeta.website end
                            ms.alert(msg, 3, true)
                        end
                    end)
                    -- Loading complete: allow macros to run and activate them if Roblox is already focused.
                    ms._loadComplete = true
                    ms.dev.log({ type = "system", event = "startup_complete" })
                    if ms._robloxActive then ms.setMacros(1, true) end
                    -- 4. Integrity warning / update check — after all three announce toasts
                    -- have faded (3 x 3 s = 9 s total) plus a 1 s gap.
                    hs.timer.doAfter(10, function()
                        if _needsIntegrityWarning then
                            ms.alert("\xe2\x9a\xa0 No trusted hash on record.\nSettings \xe2\x86\x92 Developer \xe2\x86\x92 Trust Current Version.", 10)
                        else
                            local _checkFn = (ms._updateChannel == "testing")
                                and ms.integrity.checkForUpdateBeta
                                or  ms.integrity.checkForUpdate
                            _checkFn(function(u)
                                if u then
                                    ms.playSlot("updateAvailable")
                                    ms.alert("Update " .. u.version .. " available.\nSettings \xe2\x86\x92 Help \xe2\x86\x92 Check for Update to install.", 8, true)
                                end
                            end)
                        end
                    end)
                end)
            end

            _lFadeOut = function()
                if not _lCanvas or _lFadingOut then return end
                _lFadingOut = true
                local step, steps = 0, 6
                _lFadeTimer = hs.timer.doEvery((ms._theme.fadeMs or 150) / 1000 / steps, function()
                    step = step + 1
                    if _lCanvas then _lCanvas:alpha(1 - (step / steps)) end
                    if step >= steps then
                        if _lFadeTimer then _lFadeTimer:stop(); _lFadeTimer = nil end
                        if _lCanvas then _lCanvas:delete(); _lCanvas = nil end
                        hs.timer.doAfter(0.1, _announceLoad)
                    end
                end)
            end

            -- Stagger each WebView creation into its own timer tick so startup
            -- never freezes for more than one build at a time.
            hs.timer.doAfter(0, function()
                ms.ui.prebuild()
                _lUpdate(18, "Building UI state cache\xe2\x80\xa6")
            end)
            hs.timer.doAfter(0.3, function()
                ms.ui.prewarm()
                _lUpdate(32, "Loading settings panel\xe2\x80\xa6")
            end)
            -- Each dev-panel step is split across two ticks:
            --   tick 1 (doAfter N): update the progress label and bar, then return so
            --                       Core Animation can flush the redraw to the screen.
            --   tick 2 (doAfter 0): create the WebView (potentially slow) in the next
            --                       run-loop iteration so the user sees the label update
            --                       before any brief block.
            hs.timer.doAfter(2.0, function()
                if ms._skipDevPrewarm then return end
                _lUpdate(50, "Loading console\xe2\x80\xa6")
                hs.timer.doAfter(0, function()
                    if not ms._skipDevPrewarm then pcall(function() ms.dev.prewarmStep("console") end) end
                end)
            end)
            hs.timer.doAfter(2.6, function()
                if ms._skipDevPrewarm then return end
                _lUpdate(62, "Loading macro monitor\xe2\x80\xa6")
                hs.timer.doAfter(0, function()
                    if not ms._skipDevPrewarm then pcall(function() ms.dev.prewarmStep("watcher") end) end
                end)
            end)
            hs.timer.doAfter(3.2, function()
                if ms._skipDevPrewarm then return end
                _lUpdate(75, "Loading input monitor\xe2\x80\xa6")
                hs.timer.doAfter(0, function()
                    if not ms._skipDevPrewarm then pcall(function() ms.dev.prewarmStep("keys") end) end
                end)
            end)
            hs.timer.doAfter(3.8, function()
                if ms._skipDevPrewarm then return end
                _lUpdate(88, "Loading window monitor\xe2\x80\xa6")
                hs.timer.doAfter(0, function()
                    if not ms._skipDevPrewarm then pcall(function() ms.dev.prewarmStep("window") end) end
                end)
            end)
            hs.timer.doAfter(4.6, function()
                if not _lFadingOut then
                    _lUpdate(100, "Ready.")
                    hs.timer.doAfter(0.8, _lFadeOut)
                end
            end)
            -- Failsafe: if any prewarm step stalls and the normal fade never fires,
            -- force-dismiss the loading screen after 8 s so startup always completes.
            hs.timer.doAfter(8, function()
                if _lCanvas and not _lFadingOut then _lFadeOut() end
                -- Also open the sound gate so sounds are never permanently suppressed.
                ms._startupSoundDone = true
            end)
            -- System integrity: mismatch is impossible here — the guardian blocked it at
            -- load time before any ms code ran.  If no trusted hash exists yet, try to
            -- auto-seed from MANIFEST.json before showing the manual-trust reminder.
            -- This means a clean install cloned from GitHub is trusted silently on first
            -- run — no "Trust Current Version" needed — as long as the developer kept
            -- MANIFEST.json in sync (via bin/make_release.sh) before pushing.
            hs.timer.doAfter(3, function()
                if ms.integrity.check() ~= "uninitialized" then return end
                -- Attempt bootstrap: read sha256 from MANIFEST.json and compare to
                -- the live file.  Only trust if they match exactly — this prevents
                -- a stale or tampered MANIFEST from silently seeding the wrong hash.
                local _mPath = os.getenv("HOME") .. "/.hammerspoon/MANIFEST.json"
                local _mf    = io.open(_mPath, "r")
                if _mf then
                    local _ok, _manifest = pcall(hs.json.decode, _mf:read("*all")); _mf:close()
                    if _ok and type(_manifest) == "table"
                        and type(_manifest.sha256) == "string"
                        and #_manifest.sha256 == 64 then
                        local _cur = ms.integrity.hashFile(corePath)
                        if _cur and _cur:lower() == _manifest.sha256:lower() then
                            ms.integrity.writeTrustedHash(_cur)
                            return  -- clean install — seeded silently, no alert needed
                        end
                    end
                end
                -- Bootstrap failed: flag the warning so _announceLoad shows it after
                -- the startup toasts have had time to display and fade.
                _needsIntegrityWarning = true
            end)

        -- Activate Roblox so the app watcher can seed _robloxActive correctly
        -- on first launch.

            if roblox then roblox:activate() end

            notice = 0
            loadfinish = 0

            _G._loadfinishTimer = hs.timer.doAfter(3000 / 1000, function()
                _G._loadfinishTimer = nil
                loadfinish = 1
            end)

            -- Periodic system integrity check — runs every 60 s once macros are fully loaded.
            -- If ms_core.lua has been tampered with since it was trusted, the guardian seizes
            -- control immediately without requiring a manual check.
            _G._integrityPollTimer = hs.timer.doEvery(5, function()
                if loadfinish ~= 1 then return end  -- skip startup grace period
                if ms._updateInProgress then return end  -- skip during updates
                -- Non-blocking: returns the cached value immediately and kicks off a
                -- background hs.task hash when the 60-second window expires.
                -- hs.reload() on mismatch is called inside the task callback.
                ms.integrity.check()
            end)

            if notice ~= 1 then
                -- Primary path: _announceLoad fires from the canvas delete callback (see _lFadeOut)
                -- so toasts appear immediately after the loading screen is gone.
                -- This doAfter(7.0) is a belt-and-suspenders fallback for edge cases where
                -- the canvas never fades (e.g., Hammerspoon is killed mid-load and relaunched).
                hs.timer.doAfter(7.0, _announceLoad)
                notice = 1
            end
-- END Startup Loading Indicator --
    -- END Startup Executions --
-- END Core System --