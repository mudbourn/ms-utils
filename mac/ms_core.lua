-- Core System ---- PLEASE EDIT CAREFULLY --
    -- Hammerspoon mudscript Utility Library --
        -- 0. Bootstrap & Spoons --
            if _G.__ms_core_running then return end
            _G.__ms_core_running = true
            ms = {}
            if _G.__ms_appWatcher then pcall(function() _G.__ms_appWatcher:stop() end) end

            -- Loading Screen boot-completion locals --
                local _loadAnnounced, _announceLoad
                local _needsIntegrityWarning = false
            -- END Loading Screen boot-completion locals --

            -- Loading Screen (webview mechanism) --
                package.loaded["lib.ms_loading"] = nil
                require("lib.ms_loading")(ms)
            -- END Loading Screen --

            -- Guardian (moved to MsGuardian.spoon) --
            -- END Guardian --

            -- One-time migration (move settings/hash to data/) --
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
            -- END One-time migration --

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

            -- MsGuardian (integrity check) --
                ms.loading.update(3, "Configuring Guardian\u{2026}")
                pcall(function() hs.loadSpoon("MsGuardian"); spoon.MsGuardian:check() end)
                -- Guardian tether: all spoons check this flag
                ms.checkGuardian = function(name)
                    if _G._guardianPassed then return true end
                    print("INTEGRITY ERROR: " .. (name or "spoon") .. " halted — Guardian did not pass.")
                    ms.alert("\u{26a0} Integrity Error\n" .. (name or "Module") .. " refused to start.\nGuardian check did not pass.", 10)
                    return false
                end
            -- END MsGuardian (integrity check) --

            -- Event Bus (ms.bus) — created before spoons so handlers register
                do
                    local _busSubs = {}

                    ms.bus = {}

                    ms.bus.on = function(topic, fn)
                        assert(type(topic) == "string", "ms.bus.on: topic must be a string")
                        assert(type(fn) == "function", "ms.bus.on: fn must be a function")
                        if not _busSubs[topic] then _busSubs[topic] = {} end
                        _busSubs[topic][fn] = true
                    end

                    ms.bus.off = function(topic, fn)
                        assert(type(topic) == "string", "ms.bus.off: topic must be a string")
                        assert(type(fn) == "function", "ms.bus.off: fn must be a function")
                        if _busSubs[topic] then
                            _busSubs[topic][fn] = nil
                        end
                    end

                    ms.bus.emit = function(topic, payload)
                        assert(type(topic) == "string", "ms.bus.emit: topic must be a string")
                        -- Exact match
                        local subs = _busSubs[topic]
                        if subs then
                            for fn, _ in pairs(subs) do
                                local ok, err = pcall(fn, topic, payload)
                                if not ok then
                                    print("ms.bus handler error [" .. topic .. "]: " .. tostring(err))
                                end
                            end
                        end
                        -- Wildcard subscribers: "ui:settings:*" matches "ui:settings:ready"
                        for pattern, fns in pairs(_busSubs) do
                            local starPos = pattern:find("%*$")
                            if starPos then
                                local prefix = pattern:sub(1, starPos - 1)
                                if topic:sub(1, #prefix) == prefix then
                                    for fn, _ in pairs(fns) do
                                        local ok, err = pcall(fn, topic, payload)
                                        if not ok then
                                            print("ms.bus handler error [" .. pattern .. "]: " .. tostring(err))
                                        end
                                    end
                                end
                            end
                        end
                    end

                    ms.bus._subscribers = _busSubs
                end
            -- END Event Bus --

            -- MsDevTools (logging & dev panels) --
                ms.loading.update(6, "Configuring Dev Tools\u{2026}")
                local _msDevOk, _msDevErr = pcall(function()
                    hs.loadSpoon("MsDevTools")
                    spoon.MsDevTools:init()
                end)

                if not _msDevOk then
                    print("MsDevTools: load failed — " .. tostring(_msDevErr))
                end

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

                    ms.dev.log = setmetatable({
                        pause      = function() end,
                        resume     = function() end,
                        only       = function() end,
                        pauseAll   = function() end,
                        resumeAll  = function() end,
                        isEnabled  = function() return true end,
                    }, { __call = function() end })
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

                    spoon.MsDevTools = {
                        flushAll         = function() end,
                        flushCam         = function() end,
                        flushWait        = function() end,
                        flushKey         = function() end,
                        watcherStep      = function() end,
                        macroLog         = function() end,
                        accCamMove       = function() end,
                        accWait          = function() end,
                        accKey           = function() end,
                        startTrace       = function() end,
                        stopTrace        = function() end,
                        flushTraceBuffer = function() end,
                        setTraceSuppress = function() end,
                        getTraceSuppress = function() return false end,
                        stopAllPollers         = function() end,
                        restartPollersIfActive = function() end,
                    }

                    print("MsDevTools: running without dev panels (spoon not loaded)")
                end
            -- END MsDevTools (logging & dev panels) --

            -- MsAlert (toast notifications) --
                ms.loading.update(9, "Configuring Alerts\u{2026}")
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
                    }, {
                        __call = function(_, msg) print("MsAlert stub: " .. tostring(msg)) end,
                    })

                    print("MsAlert: running without toast system (spoon not loaded)")
                end
            -- END MsAlert (toast notifications) --

            -- MsCamera removed (ms.cam uses CGEvent directly) --

            -- MsSettings (settings menu & profiles) --
                ms.loading.update(15, "Configuring Settings\u{2026}")
                local _msSettingsOk, _msSettingsErr = pcall(function()
                    hs.loadSpoon("MsSettings")
                end)

                if not _msSettingsOk then
                    print("MsSettings: load failed — " .. tostring(_msSettingsErr))
                end

                if spoon.MsSettings then
                    ms.settings = ms.settings or {}
                    ms.menu     = ms.menu or {}
                    ms.features = ms.features or {}
                    spoon.MsSettings:start()
                else
                    ms.settings = ms.settings or {}
                    ms.menu     = ms.menu or {}
                    ms.features = ms.features or {}

                    ms.settings.define = function() end
                    ms.settings.get    = function() return nil end
                    ms.settings.set    = function() end
                    ms.menu.define     = function() end
                    ms.features.hide   = function() end

                    ms.saveSettings    = function() end
                    ms.loadSettings    = function() end
                    ms.saveDefault     = function() end
                    ms.resetToDefault  = function() return false end
                    ms.reloadSettings  = function() end
                    ms.reloadUI        = function() end
                    ms.quickReload     = function() end
                    ms.reload          = function() end
                    ms.loadTheme       = function() end
                    ms.has             = function() return false end
                    ms.parseBind       = function() return nil end
                    ms.effectiveBind   = function() return nil end
                    ms.showGuardian    = function() end

                    ms._applySettings       = function() end
                    ms._convertFlatSettings  = function() return {}, {} end
                    ms._buildDefaultSettings = function() end

                    ms.socdStart  = function() end
                    ms.socdStop   = function() end
                    ms.socdApply  = function() end

                    ms.integrity = {
                        check              = function() return "uninitialized" end,
                        trustCurrent       = function() return false end,
                        hashFile           = function() return nil end,
                        readTrustedHash    = function() return nil end,
                        writeTrustedHash   = function() return false end,
                        deleteTrustedHash  = function() return false end,
                        invalidateCache    = function() end,
                        update             = function() end,
                        updateBeta         = function() end,
                        checkForUpdate     = function() end,
                        checkForUpdateBeta = function() end,
                    }

                    ms._menubar = nil

                    print("MsSettings: running without settings menu (spoon not loaded)")
                end
            -- END MsSettings (settings menu & profiles) --

            -- MsUI (webview settings panel) --
                ms.loading.update(18, "Configuring UI\u{2026}")
                local _msUIOk, _msUIErr = pcall(function()
                    hs.loadSpoon("MsUI")
                end)

                if not _msUIOk then
                    print("MsUI: load failed — " .. tostring(_msUIErr))
                end

                if spoon.MsUI then
                    spoon.MsUI:start()
                else
                    ms.ui = {
                        _panel     = nil,
                        _open      = false,
                        _modalCallback = nil,
                        _panelPos  = nil,
                        _uiFadeTimer = nil,
                    }

                    ms.ui.show        = function() end
                    ms.ui.hide        = function() end
                    ms.ui.toggle      = function() end
                    ms.ui.refresh     = function() end
                    ms.ui.markDirty   = function() end
                    ms.ui.prebuild    = function() end
                    ms.ui.prewarm     = function() end
                    ms.ui.modal       = function(_, cb) if cb then pcall(cb, { confirmed = false }) end end
                    ms.ui.prompt      = function(_, cb) if cb then pcall(cb, { confirmed = false }) end end
                    ms.ui._actions    = {
                        ready        = function() end,
                        reloadMacros = function() end,
                        navigate     = function() end,
                        close        = function() end,
                        drag         = function() end,
                        resize       = function() end,
                    }

                    print("MsUI: running without webview panel (spoon not loaded)")
                end
            -- END MsUI (webview settings panel) --
        -- END 0. Bootstrap & Spoons --

        -- 0b. Startup Sanity Checks --
        -- After hs.reload(), OS-level key/button state from a previous session
        -- persists because the old Lua state never sent release events.
        -- Clean up before initializing fresh state. Uses raw keycodes to
        -- avoid string-lookup failures.
        do
            -- Modifier keycodes (left variants)
            local modKeys = { 55, 58, 59, 56, 63 }  -- cmd, alt, ctrl, shift, fn
            for _, kc in ipairs(modKeys) do
                pcall(function()
                    local ev = hs.eventtap.event.newKeyEvent({}, kc, false)
                    if ev then ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999); ev:post() end
                end)
            end

            -- Common macro-held keycodes
            local commonKeys = { 13, 0, 1, 2, 12, 14, 15, 3, 49 }  -- w, a, s, d, q, e, r, f, space
            for _, kc in ipairs(commonKeys) do
                pcall(function()
                    local ev = hs.eventtap.event.newKeyEvent({}, kc, false)
                    if ev then ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999); ev:post() end
                end)
            end

            -- Mouse button release (0=left, 1=right, 2+=other)
            for btn = 0, 5 do
                pcall(function()
                    local pos = {0, 0}
                    local ev
                    if btn == 0 then
                        ev = hs.eventtap.event.newMouseEvent(2, pos)   -- leftMouseUp
                    elseif btn == 1 then
                        ev = hs.eventtap.event.newMouseEvent(4, pos)   -- rightMouseUp
                    else
                        ev = hs.eventtap.event.newMouseEvent(26, pos)  -- otherMouseUp
                        ev:setProperty(hs.eventtap.event.properties.mouseEventButtonNumber, btn)
                    end
                    if ev then
                        ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                        ev:post()
                    end
                end)
            end

            -- Clear any stale global timers from a previous generation
            if _G._loadTimers then
                for _, t in pairs(_G._loadTimers) do pcall(function() t:stop() end) end
            end
            _G._loadTimers = {}

            -- Stop previous app watcher if still lingering
            if _G.__ms_appWatcher then pcall(function() _G.__ms_appWatcher:stop() end) end
        end
        -- END 0b. Startup Sanity Checks --

        -- 1. State & Config --
            ms.vars = {}
            ms.keytrack = {}
            ms._keyBindings = {}
            ms._keyBindingsByCode = {}   -- [keyCode] = { binding, ... } — derived index, synced at ms.key/delete
            ms.bindConfig = {}
            ms.bindHandles = {}
            ms.systemBinds             = { _config = {}, _handles = {} }

            ms.trackpadMode          = false
            ms.trackpadHoldKeys      = { left = "n", right = "j" }
            ms.socdMode              = "lastWins"
            ms.socdEnabled           = false
            ms.trackpadBindOverrides = {
                superJump     = {type="key", mods={}, key="k"},
            }
            ms.binds                 = {}
            ms.running   = {}
            ms.cooldowns = {}
            ms._robloxActive = false
            -- Safe zones: system binds fire here even without Roblox focus
            ms._safeApps = {
                ["Hammerspoon"]      = true,
                ["Activity Monitor"] = true,
            }
            ms._isSafeZone = function()
                local front = hs.application.frontmostApplication()
                return front and ms._safeApps[front:name()] or false
            end
            ms._menuOpen     = false
            ms._menuVisible  = false
            ms._menuFnFired  = false
            ms._menuHoverWatcher = nil
            ms._slotHandles      = {}
            ms._currentFlags     = {}
            ms._pendingReopenToSound = false
            ms._inputOpen    = false
            ms._macroHeldKeys    = {}
            ms._macroHeldButtons = {}
            ms._coroContext      = {}
            ms._activeContexts   = {}
            ms.registry              = { _defs = {}, _defList = {} }
            ms.bind                  = { _wires = {}, _autoCount = 0 }

            ms._targetApp     = "Roblox"
            ms._targetHandle  = hs.application.get(ms._targetApp)
            roblox = ms._targetHandle
            ms._robloxActive  = false
            ms._qrOptions = { macros = true, theme = true, settings = true, ui = true }
            ms.getTargetWin = function()
                local app = hs.application.get(ms._targetApp)
                if not app then return nil end
                local ok, win = pcall(function() return app:mainWindow() end)
                return (ok and win) or nil
            end

            ms.setTargetApp = function(name)
                ms._targetApp    = name or nil
                ms._targetHandle = name and hs.application.get(name) or nil
                if ms._targetHandle then
                    ms._robloxActive = true
                end
            end
            notice = 0
            loadfinish = 0
            REF_W = REF_W or 1680
            REF_H = REF_H or 1044
            REF_SENS = REF_SENS or 1.5
            Move        = "Move";    Click       = "Click";    DoubleClick = "DoubleClick"
            TripleClick = "TripleClick";   Drag   = "Drag";    Press       = "Press";    Release     = "Release"
            Left        = "Left";    Right       = "Right";   Center      = "Center"
            Button4     = "Button4"; Button5     = "Button5"
            Unscaled    = true
            Absolute     = "Absolute";  Mouse        = "Mouse"
            WindowTL     = "WindowTL";  WindowTR     = "WindowTR"
            WindowBL     = "WindowBL";  WindowBR     = "WindowBR";  WindowCenter = "WindowCenter"
            ScreenTL     = "ScreenTL";  ScreenTR     = "ScreenTR"
            ScreenBL     = "ScreenBL";  ScreenBR     = "ScreenBR";  ScreenCenter = "ScreenCenter"
            BindValidity = 1
            SoundLib = os.getenv("HOME") .. "/.hammerspoon/sounds/"
            SoundDefaultsDir = SoundLib .. "defaults/"
            SoundActiveDir   = SoundLib .. "active/"
            SoundMacroDir    = SoundLib .. "macro/"
            ms.sounds          = {}
            ms.macroSounds     = {}
            ms.importedSounds  = {}
            ms.soundEnabled    = true
            ms.soundVolume     = 100
            ms.soundAssign     = {}
            ms._docsURL           = "https://docs-ms.mudbourn.info"
            ms._updateManifestURL = "https://raw.githubusercontent.com/mudbourn/ms-utils/main/MANIFEST.json"
            ms._updateChannel     = "stable"
            ms._branchTrace       = true
            ms._testingWorkflow   = "testing"
            ms._testingRepo       = "mudbourn/ms-utils"

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
                ms.settings          = ms.settings or {}
                ms.menu              = ms.menu or {}
                ms._menubar          = nil
                ms.features          = ms.features or {}
                ms._userSettingDefs  = {}
                ms._userSettingIndex = {}
                ms._userSettingVals  = {}
                ms._userMenuDefs     = {}
                ms._hiddenFeatures   = {}
                -- Default palette mirrors the docs site (docs-ms.mudbourn.info):
                -- olive/moss green accent on warm near-black, parchment text.
                -- Supersedes the earlier grayscale default (see
                -- .hermes/plans/2026-06-30_default-theme-grayscale.md).
                ms._themeDefaults = {
                    bg       = "#0d0f09",
                    surface  = "#141810",
                    surface2 = "#1c2116",
                    hover    = "#2d3523",
                    accent   = "#6b8c3a",
                    accentHi = "#8db84e",
                    success  = "#7aa63c",
                    dangerBg = "#1c130f",
                    danger   = "#c0492e",
                    warning  = "#c4a030",
                    text     = "#d4cfb6",
                    radius       = 8,
                    windowRadius = 8,
                    font         = "Arial",
                    fadeMs       = 250,
                    alertAnimMs   = 250,  -- toast animation duration (ms)
                    alertAnimSteps = 30,  -- toast animation steps
                }
                ms._theme = {}
                for k, v in pairs(ms._themeDefaults) do ms._theme[k] = v end
                ms._themeLoaded = false

            -- Window Radius Helper [ms.theme] --
                ms.theme = ms.theme or {}

                --- Apply transparent window + CSS --ms-window-radius to a webview panel.
                --- Call AFTER hs.webview.new + windowStyle(0), BEFORE panel:html().
                ms.theme.applyWindowRadius = function(panel)
                    if not panel then return end
                    local r = (ms._theme and ms._theme.windowRadius)
                        or (ms._themeDefaults and ms._themeDefaults.windowRadius)
                        or 0
                    if r > 0 then
                        pcall(function() panel:transparent(true) end)
                        pcall(function() panel:shadow(false) end)
                    end
                    local js = string.format(
                        "document.documentElement.style.setProperty('--ms-window-radius', '%dpx');"
                        .. "document.documentElement.style.background='transparent';"
                        .. "document.body.style.background='transparent';",
                        r
                    )
                    -- Queue for after html() loads
                    hs.timer.doAfter(0.05, function()
                        pcall(function() panel:evaluateJavaScript(js) end)
                    end)
                end
            -- END Window Radius Helper --

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

                hs.timer.doAfter(0.3, function()
                    local targetApp = hs.application.get(ms._targetApp)
                    if targetApp then
                        ms._robloxActive = true

                        local hs_app = hs.application.get("Hammerspoon")
                        if hs_app then hs_app:activate() end

                        hs.timer.doAfter(0.25, function()
                            local app = hs.application.get(ms._targetApp) or targetApp
                            local ok, win = pcall(function() return app:mainWindow() end)
                            if ok and win then pcall(function() win:focus() end) end
                            pcall(function() app:activate() end)
                        end)
                    end
                end)
        -- END 1. State & Config --

        -- 2. Settings, Profiles & UI --
            ms.app = function() return hs.application.frontmostApplication():name() end

        -- END 2. Settings, Profiles & UI --

        -- 3. Keyboard Actions --
            local hskeymap = {
                left = 123, right = 124, down = 125, up = 126,
                shift = 56, lshift = 56, rshift = 62,
                ctrl = 59, lctrl = 59, rctrl = 61,
                alt = 58, lalt = 58, ralt = 61,
                cmd = 55, lcmd = 55, rcmd = 54,
                f1 = 122, f2 = 120, f3 = 99, f4 = 118,
                f5 = 96, f6 = 97, f7 = 98, f8 = 100,
                f9 = 101, f10 = 109, f11 = 103, f12 = 111,
                rightclick = 999
            }

            local function getCode(key)
                if type(key) == "number" then return key end
                local k = tostring(key):lower()
                return hskeymap[k] or hs.keycodes.map[k]
            end

            ms.keystate = function(...)
                local args = { ... }
                if args[2] == true then
                    local code = args[1]
                    return code and ms.keytrack[code] == true or false
                end
                for _, key in ipairs(args) do
                    local code = getCode(key)
                    if code and ms.keytrack[code] then
                        return true
                    end
                end
                return false
            end

            -- ms.held(id): true iff every identifier modifier of bind `id` is
            -- currently held. Used to route a shared trigger among its claimants.
            -- Binds with no identifier mods (the fallback) return false.
            ms.held = function(id)
                local c = ms.effectiveBind and ms.effectiveBind(id)
                if not c or not c.mods or #c.mods == 0 then return false end
                for _, m in ipairs(c.mods) do
                    if not ms.keystate(m) then return false end
                end
                return true
            end

            local _prevModFlags = { shift = false, alt = false, ctrl = false, cmd = false }

            ms._keyListener = hs.eventtap.new({
                hs.eventtap.event.types.keyDown,
                hs.eventtap.event.types.keyUp,
                hs.eventtap.event.types.flagsChanged
            }, function(event)
                local isSynthetic = event:getProperty(hs.eventtap.event.properties.eventSourceUserData) == 999
                if isSynthetic then return false end

                local type = event:getType()
                local keyCode = event:getKeyCode()
                local flags = event:getFlags()

                if type == hs.eventtap.event.types.flagsChanged then
                    ms.keytrack[56] = flags.shift
                    ms.keytrack[62] = flags.shift
                    ms.keytrack[58] = flags.alt
                    ms.keytrack[59] = flags.ctrl
                    ms.keytrack[61] = flags.ctrl
                    ms.keytrack[55] = flags.cmd
                    ms.keytrack[54] = flags.cmd
                    if ms.dev and ms.dev._wantsKeyEvents and ms.dev._wantsKeyEvents() then
                        local now = {
                            shift = flags.shift and true or false,
                            alt   = flags.alt   and true or false,
                            ctrl  = flags.ctrl  and true or false,
                            cmd   = flags.cmd   and true or false,
                        }
                        local modNames = {
                            { k="shift", code=56, name="shift" },
                            { k="alt",   code=58, name="alt"   },
                            { k="ctrl",  code=59, name="ctrl"  },
                            { k="cmd",   code=55, name="cmd"   },
                        }
                        for _, m in ipairs(modNames) do
                            if now[m.k] ~= _prevModFlags[m.k] then
                                pcall(ms.dev._onKeyEvent, m.code, m.name, now[m.k])
                            end
                        end
                        _prevModFlags = now
                    end
                    return false
                end

                if type == hs.eventtap.event.types.keyDown then
                    local isRepeat = ms.keytrack[keyCode] == true
                    ms.keytrack[keyCode] = true
                    if not isRepeat and ms.dev and ms.dev._wantsKeyEvents and ms.dev._wantsKeyEvents() then
                        pcall(ms.dev._onKeyEvent, keyCode, hs.keycodes.map[keyCode], true)
                    end
                    if not isRepeat and ms._keyBindingsByCode then
                        ms._currentFlags = flags
                        local bucket = ms._keyBindingsByCode[keyCode]
                        if bucket then
                        for _, binding in ipairs(bucket) do
                            if binding then
                                -- Exact-match: required mods held AND no extra mods held,
                                -- so bare-key binds don't swallow modified combos (alt+esc)
                                local modsMatch = true
                                if (not binding.mods.cmd)   ~= (not flags.cmd)   then modsMatch = false end
                                if (not binding.mods.alt)   ~= (not flags.alt)   then modsMatch = false end
                                if (not binding.mods.ctrl)  ~= (not flags.ctrl)  then modsMatch = false end
                                if (not binding.mods.shift) ~= (not flags.shift) then modsMatch = false end
                                if modsMatch then
                                    if BindValidity == 1 or binding.system then
                                        if binding.pressFn then
                                            local co = coroutine.create(binding.pressFn)
                                            local ok, err = coroutine.resume(co)
                                            if not ok then print("ms.key error: " .. tostring(err)) end
                                        end
                                        return binding.swallow
                                    else
                                        return false
                                    end
                                end
                            end
                        end
                        end -- bucket
                    end
                elseif type == hs.eventtap.event.types.keyUp then
                    ms.keytrack[keyCode] = false
                    if ms.dev and ms.dev._wantsKeyEvents and ms.dev._wantsKeyEvents() then
                        pcall(ms.dev._onKeyEvent, keyCode, hs.keycodes.map[keyCode], false)
                    end
                    local bucketUp = ms._keyBindingsByCode and ms._keyBindingsByCode[keyCode]
                    if bucketUp then
                        for _, binding in ipairs(bucketUp) do
                            if binding then
                                local modsMatch = true
                                if binding.mods.cmd   and not flags.cmd   then modsMatch = false end
                                if binding.mods.alt   and not flags.alt   then modsMatch = false end
                                if binding.mods.ctrl  and not flags.ctrl  then modsMatch = false end
                                if binding.mods.shift and not flags.shift then modsMatch = false end
                                if modsMatch then
                                    if BindValidity == 1 or binding.system then
                                        if binding.releaseFn then
                                            local co = coroutine.create(binding.releaseFn)
                                            local ok, err = coroutine.resume(co)
                                            if not ok then print("ms.key error: " .. tostring(err)) end
                                        end
                                        return binding.swallow
                                    else
                                        return false
                                    end
                                end
                            end
                        end
                    end
                end

                return false
            end):start()

            -- Tap-disable recovery watchdog: macOS silently disables eventtaps
            -- when their callback overruns (kCGEventTapDisabledByTimeout).
            -- Re-enable any dead taps every 2s so macros don't silently die.
            ms._resilientTaps = { ms._keyListener }

            -- Register mouse/scroll listeners as they're created (in ms.mouse/ms.scrollBind below)
            -- The watchdog starts lazily after all taps are registered.

            -- Key logging: immediate, one line each (bunching removed).
            local function _keyLog(msg)
                if ms.dev and spoon.MsDevTools then
                    local label = ms._getCallChain()
                    spoon.MsDevTools:macroLog(msg, label)
                    if ms.dev._watcherPanel then
                        spoon.MsDevTools:watcherStep(msg, label)
                    end
                end
            end
            local _keyFlush = function() end
            -- END Key logging --

                ms.press = function(key, mods, hidinject)
                    if ms.dev then spoon.MsDevTools:flushAll(); _keyFlush() end
                    local keyCode = getCode(key)
                    if not keyCode then
                        print("Error: Could not find keyCode for " .. tostring(key))
                        return
                    end
                    -- Track key hold start time, suppress repeated ↓ for same key
                    ms._keyHoldStarts = ms._keyHoldStarts or {}
                    local alreadyHeld = ms._macroHeldKeys[keyCode]
                    if not alreadyHeld then
                        ms._keyHoldStarts[keyCode] = hs.timer.absoluteTime()
                        if ms.dev and not spoon.MsDevTools:getTraceSuppress() then
                            local modsStr = (mods and #mods > 0) and (" [" .. table.concat(mods, "+") .. "]") or ""
                            local msg = "↓ " .. tostring(key) .. modsStr
                            _keyLog(msg)
                        end
                    end
                    ms._macroHeldKeys[keyCode] = { mods = mods or {}, hidinject = hidinject }
                    local ev = hs.eventtap.event.newKeyEvent(mods or {}, keyCode, true)
                    if hidinject then
                        local app = hs.application.get(ms._targetApp or "Roblox")
                        if app then ev:post(app); return end
                    end
                    ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                    ev:post()
                end

                ms.release = function(key, mods, hidinject)
                    if ms.dev then spoon.MsDevTools:flushAll(); _keyFlush() end
                    local keyCode = getCode(key)
                    if not keyCode then return end
                    -- Calculate hold duration
                    local durationStr = ""
                    ms._keyHoldStarts = ms._keyHoldStarts or {}
                    local startTime = ms._keyHoldStarts[keyCode]
                    if startTime then
                        local elapsedNs = hs.timer.absoluteTime() - startTime
                        local elapsedMs = math.floor(elapsedNs / 1000000)
                        if elapsedMs >= 1000 then
                            durationStr = string.format(" (%.1fs)", elapsedMs / 1000)
                        elseif elapsedMs > 0 then
                            durationStr = string.format(" (%dms)", elapsedMs)
                        end
                        ms._keyHoldStarts[keyCode] = nil
                    end
                    if ms.dev and not spoon.MsDevTools:getTraceSuppress() then
                        local msg = "↑ " .. tostring(key) .. durationStr
                        _keyLog(msg)
                    end
                    ms._macroHeldKeys[keyCode] = nil
                    local ev = hs.eventtap.event.newKeyEvent(mods or {}, keyCode, false)
                    if hidinject then
                        local app = hs.application.get(ms._targetApp or "Roblox")
                        if app then ev:post(app); return end
                    end
                    ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                    ev:post()
                end

                ms.type = function(key, mods, hidinject, holdMs)
                    if ms.dev then spoon.MsDevTools:flushAll(); _keyFlush() end
                    local _hold = holdMs or 15
                    if ms.dev then
                        local modsStr = (mods and #mods > 0) and (" [" .. table.concat(mods, "+") .. "]") or ""
                        local msg = "type " .. tostring(key) .. modsStr .. " (" .. _hold .. "ms)"
                        _keyLog(msg)
                    end
                    local _saved = spoon.MsDevTools:getTraceSuppress()
                    spoon.MsDevTools:setTraceSuppress(true)
                    ms.press(key, mods, hidinject)
                    ms.wait(_hold)
                    ms.release(key, mods, hidinject)
                    spoon.MsDevTools:setTraceSuppress(_saved)  -- restore rather than reset; safe across cancellation
                end

                ms.key = function(mods, key, swallow, pressFn, releaseFn, isSystem)
                    local keyCode = getCode(key)
                    if not keyCode then
                        print("Error: Could not find keyCode for " .. tostring(key))
                        return
                    end

                    local modSet = {}
                    for _, m in ipairs(mods or {}) do modSet[m] = true end

                    local binding = {
                        keyCode = keyCode,
                        mods = modSet,
                        swallow = swallow,
                        pressFn = pressFn,
                        releaseFn = releaseFn,
                        system = isSystem or false,
                    }

                    table.insert(ms._keyBindings, binding)
                    local bucket = ms._keyBindingsByCode[keyCode]
                    if not bucket then bucket = {}; ms._keyBindingsByCode[keyCode] = bucket end
                    bucket[#bucket + 1] = binding

                    return { delete = function()
                        for i, b in ipairs(ms._keyBindings) do
                            if b == binding then
                                table.remove(ms._keyBindings, i)
                                break
                            end
                        end
                        -- Remove from by-code index
                        local bcBucket = ms._keyBindingsByCode[keyCode]
                        if bcBucket then
                            for i, b in ipairs(bcBucket) do
                                if b == binding then
                                    table.remove(bcBucket, i)
                                    break
                                end
                            end
                            if #bcBucket == 0 then ms._keyBindingsByCode[keyCode] = nil end
                        end
                    end}
                end
        -- END 3. Keyboard Actions --

        -- 4. Mouse Actions --
            ms.scroll = function(direction, clicks)
                if ms.dev._watcherPanel then
                    spoon.MsDevTools:flushCam()
                    _keyFlush()
                    spoon.MsDevTools:watcherStep("scroll " .. tostring(direction)
                        .. (clicks and clicks > 1 and " \xc3\x97" .. clicks or ""))
                end
                clicks = clicks or 1
                local dx, dy = 0, 0
                if direction == "up" then dy = clicks
                elseif direction == "down" then dy = -clicks
                elseif direction == "left" then dx = -clicks
                elseif direction == "right" then dx = clicks
                end
                local ev = hs.eventtap.event.newScrollEvent({dx, dy}, {}, "pixel")
                ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                ev:post()
            end

            ms.mouse = function(button, swallow, clickFn, hidinject, isSystem)
                if not ms._mouseListener then
                    ms._mouseCallbacks = {}
                    local types = {
                        hs.eventtap.event.types.leftMouseDown,
                        hs.eventtap.event.types.leftMouseUp,
                        hs.eventtap.event.types.rightMouseDown,
                        hs.eventtap.event.types.rightMouseUp,
                        hs.eventtap.event.types.otherMouseDown,
                        hs.eventtap.event.types.otherMouseUp,
                    }
                    ms._mouseListener = hs.eventtap.new(types, function(event)
                        local type = event:getType()
                        local b
                        local isDown

                        if type == hs.eventtap.event.types.leftMouseDown then
                            b = 0; isDown = true
                        elseif type == hs.eventtap.event.types.leftMouseUp then
                            b = 0; isDown = false
                        elseif type == hs.eventtap.event.types.rightMouseDown then
                            b = 1; isDown = true
                            ms.keytrack[999] = true
                        elseif type == hs.eventtap.event.types.rightMouseUp then
                            b = 1; isDown = false
                            ms.keytrack[999] = false
                        elseif type == hs.eventtap.event.types.otherMouseDown then
                            b = event:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber)
                            isDown = true
                            if b == 2 then ms.keytrack[998] = true end
                        else -- otherMouseUp
                            b = event:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber)
                            isDown = false
                            if b == 2 then ms.keytrack[998] = false end
                        end

                        if ms.dev and ms.dev._wantsMouseEvents and ms.dev._wantsMouseEvents() then
                            local _mp = hs.mouse.absolutePosition()
                            pcall(ms.dev._onMouseEvent, b, isDown,
                                math.floor(_mp.x), math.floor(_mp.y))
                        end

                        if BindValidity ~= 1 then
                            if not (callbackData and callbackData.system) then return false end
                        end

                        if not isDown then return false end

                        local callbackData = ms._mouseCallbacks[b]
                        if callbackData then
                            if callbackData.swallow and callbackData.hidinject then
                                local app = hs.application.get(ms._targetApp or "Roblox")
                                if app then event:copy():post(app) end
                            end
                            local co = coroutine.create(callbackData.fn)
                            local ok, err = coroutine.resume(co)
                            if not ok then
                                print("ms.mouse callback error: " .. tostring(err))
                            end
                            return callbackData.swallow
                        end

                        return false
                    end):start()
                    ms._resilientTaps[#ms._resilientTaps+1] = ms._mouseListener
                end
                ms._mouseCallbacks[button] = { fn = clickFn, swallow = swallow, hidinject = hidinject, system = isSystem or false }
            end

            -- ms.scrollBind(direction, fn) — listen for scroll wheel up/down and fire callback
            ms._scrollCallbacks = ms._scrollCallbacks or {}
            ms.scrollBind = function(direction, fn)
                if not ms._scrollListener then
                    ms._scrollCallbacks = {}
                    ms._scrollListener = hs.eventtap.new({
                        hs.eventtap.event.types.scrollWheel,
                    }, function(event)
                        if BindValidity ~= 1 then return false end
                        local dy = event:getProperty(hs.eventtap.event.properties.scrollWheelEventDeltaAxis1)
                        local dir = dy > 0 and "up" or "down"
                        local cb = ms._scrollCallbacks[dir]
                        if cb then
                            local co = coroutine.create(cb)
                            local ok, err = coroutine.resume(co)
                            if not ok then print("ms.scrollBind callback error: " .. tostring(err)) end
                        end
                        return false
                    end):start()
                    ms._resilientTaps[#ms._resilientTaps+1] = ms._scrollListener
                end
                ms._scrollCallbacks[direction] = fn
                return {
                    delete = function()
                        ms._scrollCallbacks[direction] = nil
                    end,
                }
            end

            -- Gamepad reader — background process using ms_gc_read binary
            ms._gamepadTask = nil
            ms._gamepadCallbacks = {}  -- [buttonName] = fn
            ms._gamepadConnected = false

            ms.gamepadStart = function()
                if ms._gamepadTask then return end
                local bin = os.getenv("HOME") .. "/.local/bin/ms_gc_read"
                ms._gamepadCallbacks = {}
                ms._gamepadTask = hs.task.new(bin, function() end, function(task, stdOut, stdErr)
                    if not stdOut or stdOut == "" then return true end
                    -- Parse JSON line
                    local ok, ev = pcall(function() return hs.json.decode(stdOut) end)
                    if not ok or not ev or not ev.e then return true end
                    if ev.e == "connect" then
                        ms._gamepadConnected = true
                        if ms.dev and ms.dev._watcherPanel then
                            spoon.MsDevTools:watcherStep("gamepad connected: " .. (ev.c or "?"))
                        end
                    elseif ev.e == "disconnect" then
                        ms._gamepadConnected = false
                    elseif ev.e == "press" then
                        -- Route to rebind capture if active, otherwise to bound button
                        local rebindCb = ms._gamepadCallbacks._rebind
                        if rebindCb then
                            rebindCb(ev.b)
                        else
                            local cb = ms._gamepadCallbacks[ev.b]
                            if cb then
                                local co = coroutine.create(cb)
                                local ok2, err = coroutine.resume(co)
                                if not ok2 then print("ms.gamepad callback error: " .. tostring(err)) end
                            end
                        end
                    end
                    return true
                end)
                ms._gamepadTask:start()
            end

            ms.gamepadStop = function()
                if ms._gamepadTask then
                    ms._gamepadTask:terminate()
                    ms._gamepadTask = nil
                    ms._gamepadCallbacks = {}
                    ms._gamepadConnected = false
                end
            end

            -- ms.gamepadBind(buttonName, fn) — listen for a gamepad button press (requires gamepadEnabled)
            ms.gamepadBind = function(button, fn)
                if not ms.gamepadEnabled then
                    return { delete = function() end }
                end
                if not ms._gamepadTask then ms.gamepadStart() end
                ms._gamepadCallbacks[button] = fn
                return {
                    delete = function()
                        ms._gamepadCallbacks[button] = nil
                    end,
                }
            end


            ms.Mouse = function(operation, button, reference, ...)
                local OPS  = { Move=true, Click=true, DoubleClick=true,
                               TripleClick=true, Drag=true, Press=true, Release=true }
                local BTNS = { Left=0, Right=1, Center=2, Button4=3, Button5=4 }
                local REFS = {
                    Absolute=true,   Mouse=true,
                    WindowTL=true,   WindowTR=true,  WindowBL=true,
                    WindowBR=true,   WindowCenter=true,
                    ScreenTL=true,   ScreenTR=true,  ScreenBL=true,
                    ScreenBR=true,   ScreenCenter=true,
                }
                if ms.dev then spoon.MsDevTools:flushAll() end
                assert(OPS[operation],     "ms.Mouse: unknown operation '"  .. tostring(operation)  .. "'")
                assert(BTNS[button] ~= nil, "ms.Mouse: unknown button '"      .. tostring(button)     .. "'")
                assert(REFS[reference],    "ms.Mouse: unknown reference '"   .. tostring(reference)  .. "'")

                local unscaled, x1, y1, x2, y2, hidinject
                local _a, _b, _c, _d, _e, _f = ...
                if type(_a) == "boolean" then
                    unscaled                   = _a
                    x1, y1, x2, y2, hidinject = _b, _c, _d, _e, _f
                else
                    unscaled                   = false
                    x1, y1, x2, y2, hidinject = _a, _b, _c, _d, _e
                end

                -- Log with all available params
                do
                    local parts = { "Mouse ", tostring(operation), " ", tostring(button), " ", tostring(reference) }
                    if x1 then parts[#parts + 1] = " " .. tostring(x1) .. "," .. tostring(y1) end
                    if x2 then parts[#parts + 1] = " → " .. tostring(x2) .. "," .. tostring(y2) end
                    local msg = table.concat(parts)
                    if ms.dev and ms.dev._watcherPanel then
                        spoon.MsDevTools:watcherStep(msg)
                    end
                    if ms.dev then
                        spoon.MsDevTools:macroLog(msg)
                    end
                end

                local btn  = BTNS[button]
                local _app = hidinject and hs.application.get(ms._targetApp or "Roblox") or nil

                local function resolve(x, y) return ms.resolvePoint(x, y, reference, unscaled) end

                local ax1, ay1 = resolve(x1, y1)
                local ax2, ay2
                if x2 ~= nil and y2 ~= nil then
                    ax2, ay2 = resolve(x2, y2)
                else
                    ax2, ay2 = ax1, ay1
                end
                local pos1 = { x = ax1, y = ay1 }
                local pos2 = { x = ax2, y = ay2 }

                local downT, upT, dragT
                if btn == 0 then
                    downT = hs.eventtap.event.types.leftMouseDown
                    upT   = hs.eventtap.event.types.leftMouseUp
                    dragT = hs.eventtap.event.types.leftMouseDragged
                elseif btn == 1 then
                    downT = hs.eventtap.event.types.rightMouseDown
                    upT   = hs.eventtap.event.types.rightMouseUp
                    dragT = hs.eventtap.event.types.rightMouseDragged
                else
                    downT = hs.eventtap.event.types.otherMouseDown
                    upT   = hs.eventtap.event.types.otherMouseUp
                    dragT = hs.eventtap.event.types.otherMouseDragged
                end

                local function post(evType, pos)
                    local ev = hs.eventtap.event.newMouseEvent(evType, pos)
                    if btn >= 2 then
                        ev:setProperty(hs.eventtap.event.properties.mouseEventButtonNumber, btn)
                    end
                    if _app then ev:post(_app)
                    else
                        ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                        ev:post()
                    end
                end

                local function moveTo(pos)
                    local mv = hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.mouseMoved, pos)
                    if _app then mv:post(_app)
                    else
                        mv:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                        mv:post()
                    end
                    hs.mouse.absolutePosition(pos)
                end

                local function singleClick(pos)
                    post(downT, pos); ms.wait(50); post(upT, pos)
                end

                if     operation == "Move"        then moveTo(pos1)
                elseif operation == "Click"       then moveTo(pos1); ms.wait(50); singleClick(pos1)
                elseif operation == "DoubleClick" then
                    moveTo(pos1); ms.wait(50)
                    singleClick(pos1); ms.wait(50); singleClick(pos1)
                elseif operation == "TripleClick" then
                    moveTo(pos1); ms.wait(50)
                    for i = 1, 3 do singleClick(pos1); if i < 3 then ms.wait(50) end end
                elseif operation == "Drag"        then
                    moveTo(pos1); ms.wait(50)
                    post(downT, pos1); ms.wait(50)
                    post(dragT, pos2)
                    hs.mouse.absolutePosition(pos2)
                    ms.wait(50)
                    post(upT, pos2)
                elseif operation == "Press"       then
                    moveTo(pos1); post(downT, pos1)
                    ms._macroHeldButtons[btn] = { upT = upT, pos = pos1, app = _app }
                elseif operation == "Release"     then
                    post(upT, pos1)
                    ms._macroHeldButtons[btn] = nil
                end
            end

            -- ms.cam — camera drag via CGEvent --
            --

            local _camEvType  = hs.eventtap.event.types.otherMouseDragged
            local _camBtn     = hs.eventtap.event.properties.mouseEventButtonNumber
            local _camDx      = hs.eventtap.event.properties.mouseEventDeltaX
            local _camDy      = hs.eventtap.event.properties.mouseEventDeltaY
            local _camTotalX  = 0
            local _camTotalY  = 0
            local _camRebalancing = false
            local _camAnchor  = nil  -- Window center anchor for stable camera control
            local _camActivated = false  -- Track if camera has been activated

            -- Update anchor to window center (prevents shiftlock drift)
            local function _updateCamAnchor()
                local win = ms.getTargetWin()
                if win then
                    local f = win:frame()
                    _camAnchor = { x = f.x + (f.w / 2), y = f.y + (f.h / 2) }
                end
            end

            -- Activate camera control (post mouse down/up to register with Roblox)
            local function _activateCam()
                if _camActivated then return end
                -- Use current cursor position, not anchor
                local pos = hs.mouse.absolutePosition()
                local downEv = hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.otherMouseDown, pos)
                local upEv = hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.otherMouseUp, pos)
                downEv:setProperty(_camBtn, 5)
                upEv:setProperty(_camBtn, 5)
                -- Mark as synthetic events
                downEv:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                upEv:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                downEv:post()
                hs.timer.usleep(10000)  -- 10ms delay
                upEv:post()
                _camActivated = true
            end

            -- Expose for app watcher
            ms._updateCamAnchor = _updateCamAnchor
            ms._activateCam = _activateCam
            ms._resetCamActivated = function() _camActivated = false end

            ms.cam = setmetatable({}, {
                __call = function(_, dx, dy)
                    -- Activate camera on first use
                    if not _camActivated then _activateCam() end

                    -- Scale by sensitivity ratio so macros calibrated at refSens
                    -- produce the same rotation regardless of in-game sensitivity
                    local refSens = ms.settings and ms.settings.get("refSensitivity") or 1.5
                    local curSens = ms._camSens or 1.5
                    if refSens > 0 and curSens > 0 and refSens ~= curSens then
                        local scale = refSens / curSens
                        dx = dx * scale
                        dy = dy * scale
                    end

                    dx = math.floor(dx + 0.5)
                    dy = math.floor(dy + 0.5)

                    -- Use current cursor position for relative anchoring
                    local pos = hs.mouse.absolutePosition()
                    local ev  = hs.eventtap.event.newMouseEvent(_camEvType, pos)
                    ev:setProperty(_camBtn, 5)
                    ev:setProperty(_camDx, dx)
                    ev:setProperty(_camDy, dy)
                    -- Mark as synthetic event to prevent cursor movement
                    ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                    ev:post()

                    -- No need to restore cursor - we never moved it

                    if not _camRebalancing then
                        _camTotalX = _camTotalX + dx
                        _camTotalY = _camTotalY + dy
                    end
                end,
            })

            -- Update anchor when Roblox gains focus
            ms.bus.on("ui:_shell:navigate", function(data)
                if data and data.panel then
                    _updateCamAnchor()
                end
            end)
            -- Suppress wait logging inside ms.cam calls (cam loops are noisy)
            local _origCamCall = getmetatable(ms.cam).__call
            getmetatable(ms.cam).__call = function(self, dx, dy)
                dx = math.floor(dx + 0.5)
                dy = math.floor(dy + 0.5)
                -- Suppress internal wait logging
                local saved = ms.dev and spoon.MsDevTools and spoon.MsDevTools:getTraceSuppress()
                if saved ~= nil then spoon.MsDevTools:setTraceSuppress(true) end
                _origCamCall(self, dx, dy)
                if saved ~= nil then spoon.MsDevTools:setTraceSuppress(saved) end
                -- Accumulate (flushes on value change or before scroll/wait)
                if ms.dev and spoon.MsDevTools then
                    spoon.MsDevTools:accCamMove(dx, dy, ms._getCallChain())
                end
            end

            ms.cam.rebalance = function(granularity)
                if granularity == nil then
                    granularity = 4
                end
                if _camTotalX == 0 and _camTotalY == 0 then return end
                _camRebalancing = true
                div1 = 1/granularity
                div2 = div1/2
                for i = 1, granularity * 2 do
                    ms.cam(-_camTotalX * div2, -_camTotalY * div2)
                    ms.wait(2)
                end
                _camTotalX = 0
                _camTotalY = 0
                _camRebalancing = false
            end

            ms.cam.reset = function()
                _camTotalX = 0
                _camTotalY = 0
            end

            -- ms.flick(dx, dy, opts): deterministic tightly-bunched delta stream.
            -- Runs synchronously (no yield). count = number of deltas, gapUs = microsecond spacing.
            ms.flick = function(dx, dy, opts)
                opts = opts or {}
                local count = opts.count or math.max(1, math.floor(math.abs(dx) / 100 + 0.5))
                local gapUs = opts.gapUs or ms._flickGapUs or 1000
                -- Bresenham-style remainder so emitted sum == requested total exactly
                local perX, remX = math.floor(dx / count), dx % count
                local perY, remY = math.floor(dy / count), dy % count
                local accX, accY = 0, 0
                for i = 1, count do
                    local ex = perX; accX = accX + remX; if accX >= count then ex = ex + 1; accX = accX - count end
                    local ey = perY; accY = accY + remY; if accY >= count then ey = ey + 1; accY = accY - count end
                    ms.cam(ex, ey)
                    if i < count then hs.timer.usleep(gapUs) end
                end
            end

            -- ms.cam.sweep — async single doEvery pump (for throws)
            local _sweepQueue = {}
            local _sweepTimer = nil
            local _SWEEP_HZ   = 120

            local function _sweepTick()
                if #_sweepQueue == 0 then
                    if _sweepTimer then _sweepTimer:stop(); _sweepTimer = nil end
                    return
                end
                local job = _sweepQueue[1]
                if job.ticksLeft <= 0 then
                    table.remove(_sweepQueue, 1)
                    if #_sweepQueue == 0 then
                        if _sweepTimer then _sweepTimer:stop(); _sweepTimer = nil end
                    end
                    return
                end
                local perTickX = job.dx / job.totalTicks
                local perTickY = job.dy / job.totalTicks
                local ex = math.floor(perTickX * (job.totalTicks - job.ticksLeft + 1)) - math.floor(perTickX * (job.totalTicks - job.ticksLeft))
                local ey = math.floor(perTickY * (job.totalTicks - job.ticksLeft + 1)) - math.floor(perTickY * (job.totalTicks - job.ticksLeft))
                if ex == 0 and ey == 0 then ex = perTickX >= 0 and 1 or -1; ey = 0 end
                ms.cam(ex, ey)
                job.ticksLeft = job.ticksLeft - 1
            end

            ms.cam.sweep = function(dx, dy, durationMs)
                local ticks = math.max(1, math.floor((durationMs / 1000) * _SWEEP_HZ + 0.5))
                _sweepQueue[#_sweepQueue + 1] = { dx = dx, dy = dy, ticksLeft = ticks, totalTicks = ticks }
                if not _sweepTimer then
                    _sweepTimer = hs.timer.doEvery(1 / _SWEEP_HZ, _sweepTick)
                end
            end

            ms.cam.sweepBlocking = function(dx, dy, durationMs)
                ms.cam.sweep(dx, dy, durationMs)
                ms.wait(durationMs)
            end

            ms.cam.sweepCancel = function()
                _sweepQueue = {}
                if _sweepTimer then _sweepTimer:stop(); _sweepTimer = nil end
            end

            -- END ms.cam --

        -- END 4. Mouse Actions --

        -- 5. Timing --
            ms.after = function(ms_time, fn)
                -- Capture call stack for context propagation into async callbacks
                local capturedStack = nil
                local co = coroutine.running()
                if co then
                    local ctx = ms._coroContext[co]
                    if ctx and ctx.callStack then
                        capturedStack = { table.unpack(ctx.callStack) }
                    end
                elseif ms._capturedStack then
                    capturedStack = { table.unpack(ms._capturedStack) }
                end
                return hs.timer.doAfter(ms_time / 1000, function()
                    if capturedStack then
                        ms._capturedStack = capturedStack
                    end
                    fn()
                    ms._capturedStack = nil
                end)
            end

            ms.wait = function(ms_time)
                local co = coroutine.running()
                if co then
                    local ctx = ms._coroContext[co]
                    if ms.dev and not spoon.MsDevTools:getTraceSuppress() then
                        spoon.MsDevTools:flushCam()
                        _keyFlush()
                    end

                    if ms.dev then
                        spoon.MsDevTools:accWait(tonumber(ms_time) or 0, ms._getCallChain())
                    end
                    hs.timer.doAfter(ms_time / 1000, function()
                        if ctx and (ctx.cancelled or ctx.paused) then return end
                        local ok, err = coroutine.resume(co)
                        if not ok then
                            print("ms.wait resume error: " .. tostring(err))
                        end
                        if coroutine.status(co) == "dead" then
                            ms._coroContext[co] = nil
                            if ctx then ms._activeContexts[ctx] = nil end
                            if ms.dev then spoon.MsDevTools:stopTrace(co) end
                            if _keyFlushTimer then _keyFlushTimer:stop(); _keyFlushTimer = nil end
                            _keyFlush()
                            local flushLabel = ctx and ctx.callStack and ctx.callStack[1]
                            if ms.dev then spoon.MsDevTools:flushAll(flushLabel) end
                        end
                    end)
                    if ms._branchTrace then spoon.MsDevTools:flushTraceBuffer(co) end
                    coroutine.yield()
                else
                    hs.timer.usleep(ms_time * 1000)
                end
            end
        -- END 5. Timing --

        -- 6. Resolution & Window Scaling --
            ms.getRobloxWin = function()
                return ms.getTargetWin()
            end

            ms.winCenter = function()
                local win = ms.getTargetWin() or hs.window.focusedWindow()
                if not win then return 0, 0 end
                local f = win:frame()
                return f.x + (f.w / 2), f.y + (f.h / 2)
            end

            ms.getScaled = function(targetX, targetY)
                local win = ms.getTargetWin() or hs.window.focusedWindow()
                if not win then
                    local screen = hs.screen.mainScreen():frame()
                    return targetX * (screen.w / REF_W), targetY * (screen.h / REF_H)
                end
                local f = win:frame()
                local finalX = f.x + (targetX * (f.w / REF_W))
                local finalY = f.y + (targetY * (f.h / REF_H))
                return finalX, finalY
            end

            ms.resolvePoint = function(x, y, reference, unscaled)
                local win = ms.getTargetWin() or hs.window.focusedWindow()
                local f   = win and win:frame()
                local s   = hs.screen.mainScreen():frame()
                if     reference == "Absolute"     then return x, y
                elseif reference == "Mouse"        then
                    local p = hs.mouse.absolutePosition()
                    return p.x + x, p.y + y
                elseif reference == "WindowTL"     then
                    if not f then return x, y end
                    if unscaled then return f.x + x,         f.y + y         end
                    return f.x + (x * f.w / REF_W), f.y + (y * f.h / REF_H)
                elseif reference == "WindowTR"     then
                    if not f then return x, y end
                    if unscaled then return f.x + f.w + x,   f.y + y         end
                    return f.x + f.w + (x * f.w / REF_W), f.y + (y * f.h / REF_H)
                elseif reference == "WindowBL"     then
                    if not f then return x, y end
                    if unscaled then return f.x + x,         f.y + f.h + y   end
                    return f.x + (x * f.w / REF_W), f.y + f.h + (y * f.h / REF_H)
                elseif reference == "WindowBR"     then
                    if not f then return x, y end
                    if unscaled then return f.x + f.w + x,   f.y + f.h + y   end
                    return f.x + f.w + (x * f.w / REF_W), f.y + f.h + (y * f.h / REF_H)
                elseif reference == "WindowCenter" then
                    if not f then return x, y end
                    if unscaled then return f.x + f.w/2 + x, f.y + f.h/2 + y end
                    return f.x + f.w/2 + (x * f.w / REF_W), f.y + f.h/2 + (y * f.h / REF_H)
                elseif reference == "ScreenTL"     then return s.x + x,         s.y + y
                elseif reference == "ScreenTR"     then return s.x + s.w + x,   s.y + y
                elseif reference == "ScreenBL"     then return s.x + x,         s.y + s.h + y
                elseif reference == "ScreenBR"     then return s.x + s.w + x,   s.y + s.h + y
                elseif reference == "ScreenCenter" then return s.x + s.w/2 + x, s.y + s.h/2 + y
                end
                return x, y
            end

            ms.debugRoblox = function()
                local win = ms.getRobloxWin() or hs.window.find(ms._targetApp)
                if win then
                    local f = win:frame()
                    local screen = win:screen():frame()
                    local currentRatio = f.w / f.h
                    local currentSens = ms._camSens or 1.5
                    local output = {
                        "--- ROBLOX DEBUG INFO ---",
                        string.format("Window Title: %s", win:title()),
                        string.format("Resolution (Points): %.1f x %.1f", f.w, f.h),
                        string.format("Position: x=%.1f, y=%.1f", f.x, f.y),
                        string.format("Full Screen: %s", tostring(win:isFullScreen())),
                        "-------------------------",
                        string.format("Monitor Size: %.0f x %.0f", screen.w, screen.h),
                        string.format("Reference Target: %d x %d", REF_W or 1680, REF_H or 1044),
                        "-------------------------",
                        string.format("Aspect Ratio: %.2f", currentRatio),
                        string.format("Camera Sensitivity: %.2f", currentSens),
                        "-------------------------"
                    }
                    print(table.concat(output, "\n"))
                    ms.alert(string.format("Window: %.0f x %.0f | Ratio: %.2f", f.w, f.h, currentRatio), 4)
                    ms.alert("Camera Sensitivity: " .. string.format("%.2f", currentSens), 4)
                    if currentRatio < 4/3 then
                        ms.alert("Warning: Ratio too narrow.", 8)
                    end
                else
                    print("DEBUG ERROR: Roblox window not found.")
                    ms.alert("Roblox not found.", 2)
                end
            end
        -- END 6. Resolution & Window Scaling --

        -- 7. Macro Bind Controller --
            local _debounceTimer = nil
            local _stateSound    = nil  -- handle to the last state-change sound

            local function _doNotify(state)
                if loadfinish ~= 1 then return end
                if _debounceTimer then _debounceTimer:stop(); _debounceTimer = nil end
                _debounceTimer = hs.timer.doAfter(0.05, function()
                    _debounceTimer = nil
                    if _stateSound then pcall(function() _stateSound:stop() end); _stateSound = nil end
                    if state == 1 then
                        _stateSound = ms.playSlot("enabled")
                        ms.alert("Macros enabled!",  3, true, { id = "_state", source = "system" })
                    else
                        _stateSound = ms.playSlot("disabled")
                        ms.alert("Macros disabled.", 3, true, { id = "_state", source = "system" })
                    end
                end)
            end

            ms.setMacros = function(state, silent)
                if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
                if state == 1 and BindValidity ~= 1 then
                    BindValidity = 1
                    -- Update camera anchor when macros are enabled
                    if ms._updateCamAnchor then ms._updateCamAnchor() end
                    ms.dev.log({ type = "system", event = "macros_enabled" })
                    if not silent then _doNotify(1) end
                elseif state == 0 and BindValidity ~= 0 then
                    BindValidity = 0
                    ms.cancelMacros()
                    ms.keytrack = {}
                    for _, timer in pairs(ms.running) do
                        if timer and timer.stop then timer:stop() end
                    end
                    ms.running = {}
                    ms.dev.log({ type = "system", event = "macros_disabled" })
                    if not silent then _doNotify(0) end
                end
                if ms.ui and ms.ui._open then ms.ui.refresh() end
            end

            ms._appWatcher = hs.application.watcher.new(function(appName, eventType, app)
                if eventType == hs.application.watcher.activated then
                    if appName == (ms._targetApp or "Roblox") then
                        local fromDialog = ms._inputOpen
                        ms._inputOpen = false
                        ms._robloxActive = true
                        ms.dev.log({ type = "system", event = "target_focus", fromDialog = fromDialog or false })
                        -- Update camera anchor when target gains focus
                        if ms._updateCamAnchor then ms._updateCamAnchor() end
                        -- Reset cam activation so next ms.cam re-registers with target
                        if ms._resetCamActivated then ms._resetCamActivated() end
                        if not ms._loadComplete then return end
                        if fromDialog then
                            BindValidity = 1
                        else
                            ms.setMacros(1)
                        end
                    else
                        -- Don't disable macros if settings panel or shell is open
                        local shellOpen = ms._shellState and ms._shellState.visible
                        if (ms.ui._open or shellOpen) and appName == "Hammerspoon" then return end
                        ms._inputOpen    = (appName == "Hammerspoon") and ms._robloxActive
                        ms._robloxActive = false
                        ms.dev.log({ type = "system", event = "target_blur", to = appName })
                        -- Reset camera activation state when Roblox loses focus
                        if ms._camActivated ~= nil then ms._camActivated = false end
                        if BindValidity == 1 then
                            ms.setMacros(0, ms._inputOpen)
                        end
                    end
                end
            end):start()
            _G.__ms_appWatcher = ms._appWatcher  -- survives reload (lives outside the ms table) so next load's stop-guard can find this generation

            _G._initTimer = hs.timer.doAfter(0.3, function()
                local frontApp = hs.application.frontmostApplication()
                if ms._targetApp and frontApp and frontApp:name() == ms._targetApp then
                    ms._robloxActive = true
                end
            end)

            -- Octane Mode: low-overhead performance toggle
            -- Strips logging, animations, pollers, and sounds while macros run unchanged
            ms.octane = ms.octane or {}
            ms.octane.on = function()
                if ms._octaneMode then return end
                ms._octaneMode = true
                if ms.saveSettings then pcall(ms.saveSettings) end
                ms.octane._apply()
            end
            ms.octane.off = function()
                if not ms._octaneMode then return end
                ms._octaneMode = false
                if ms.saveSettings then pcall(ms.saveSettings) end
                ms.octane._remove()
            end
            ms.octane.toggle = function()
                if ms._octaneMode then ms.octane.off() else ms.octane.on() end
            end
            -- Internal: apply octane state (called on load if persisted on)
            ms.octane._apply = function()
                -- Logging gate: pause all channels
                if ms.dev and ms.dev.log and ms.dev.log.pauseAll then
                    pcall(ms.dev.log.pauseAll)
                end
                -- Stop all idle pollers (mouse, shell mouse, window spy)
                if spoon.MsDevTools and spoon.MsDevTools.stopAllPollers then
                    pcall(function() spoon.MsDevTools:stopAllPollers() end)
                end
                -- Stop menu hover watcher entirely under octane
                if ms._menuHoverWatcher then
                    ms._menuHoverWatcher:stop()
                    ms._menuHoverWatcher = nil
                end
                -- Force Window Monitor element-inspect off (expensive pixel + AX)
                if spoon.MsDevTools and spoon.MsDevTools.setWinElementInspect then
                    pcall(function() spoon.MsDevTools:setWinElementInspect(false) end)
                end
            end
            -- Internal: remove octane state (called on toggle off)
            ms.octane._remove = function()
                -- Re-enable all logging channels
                if ms.dev and ms.dev.log and ms.dev.log.resumeAll then
                    pcall(ms.dev.log.resumeAll)
                end
                -- Restart pollers for panels that are currently active
                if spoon.MsDevTools and spoon.MsDevTools.restartPollersIfActive then
                    pcall(function() spoon.MsDevTools:restartPollersIfActive() end)
                end
                -- Restart menu hover watcher if menu is visible
                if ms._menuVisible and ms._menuHoverStart then
                    pcall(ms._menuHoverStart)
                end
            end

            -- System hotkey bindings (configurable via shell)
            ms._hotkeys = {
                panic       = { mods = {"alt"}, key = "F10" },
                quickReload = { mods = {"alt"}, key = "[" },
                fullReload  = { mods = {"alt"}, key = "]" },
                openMenu    = { mods = {"alt"}, key = "p" },
                octane      = { mods = {"alt"}, key = "o" },
            }
            ms._hotkeyHandles = {}

            -- Keystate watcher: fires on key down, waits for key up + cooldown
            -- Does NOT swallow key inputs
            local _hotkeyCooldowns = {}
            local _hotkeyDown = {}

            ms._makeKeyWatcher = function(mods, key, onDown)
                local keyCode = hs.keycodes.map[key]
                if not keyCode then return nil end

                local modSet = {}
                for _, m in ipairs(mods or {}) do modSet[m] = true end

                local function modsMatch(flags)
                    for m, _ in pairs(modSet) do
                        if not flags[m] then return false end
                    end
                    return true
                end

                -- Exact-match for the fire gate: required mods held AND no extras,
                -- so bare-key watchers don't swallow modified combos (alt+esc).
                -- flagsChanged reset below stays subset-match on purpose: exact
                -- there would clear the cooldown when an extra mod is pressed
                -- mid-hold and re-fire on key repeat.
                local function modsExact(flags)
                    if not modsMatch(flags) then return false end
                    if flags.cmd   and not modSet.cmd   then return false end
                    if flags.alt   and not modSet.alt   then return false end
                    if flags.ctrl  and not modSet.ctrl  then return false end
                    if flags.shift and not modSet.shift then return false end
                    return true
                end

                local id = table.concat(mods or {}, ",") .. ":" .. key

                local tap = hs.eventtap.new({
                    hs.eventtap.event.types.keyDown,
                    hs.eventtap.event.types.keyUp,
                    hs.eventtap.event.types.flagsChanged,
                }, function(e)
                    local type = e:getType()
                    local flags = e:getFlags()
                    local kc = e:getKeyCode()

                    if type == hs.eventtap.event.types.flagsChanged then
                        -- Modifier released: reset state
                        if not modsMatch(flags) then
                            _hotkeyDown[id] = false
                            _hotkeyCooldowns[id] = false
                        end
                        return false
                    end

                    if type == hs.eventtap.event.types.keyDown then
                        if kc == keyCode and modsExact(flags) and not _hotkeyDown[id] and not _hotkeyCooldowns[id] then
                            _hotkeyDown[id] = true
                            onDown()
                        end
                        return ms._swallowHotkeys and true or false
                    end

                    if type == hs.eventtap.event.types.keyUp then
                        if kc == keyCode then
                            _hotkeyDown[id] = false
                            -- Cooldown: wait 0.15s after key up before allowing re-fire
                            _hotkeyCooldowns[id] = true
                            hs.timer.doAfter(0.15, function()
                                _hotkeyCooldowns[id] = false
                            end)
                            return ms._swallowHotkeys and true or false
                        end
                        return false
                    end

                    return false
                end)

                return tap
            end

            ms._bindHotkeys = function()
                -- Clear old taps
                for _, h in pairs(ms._hotkeyHandles) do
                    if h and h.stop then h:stop() end
                end
                ms._hotkeyHandles = {}
                _hotkeyCooldowns = {}
                _hotkeyDown = {}

                -- Panic
                local hk = ms._hotkeys.panic
                local tap = ms._makeKeyWatcher(hk.mods, hk.key, function()
                    if not ms._loadComplete then return end
                    if not ms._robloxActive and not ms._isSafeZone() then return end
                    ms.setMacros(0)
                end)
                if tap then ms._hotkeyHandles.panic = tap; tap:start() end

                -- Quick Reload
                hk = ms._hotkeys.quickReload
                tap = ms._makeKeyWatcher(hk.mods, hk.key, function()
                    if not ms._loadComplete then return end
                    if not ms._robloxActive and not ms._isSafeZone() then return end
                    if ms._qrCooldown then return end
                    ms._qrCooldown = true
                    hs.timer.doAfter(1.0, function() ms._qrCooldown = false end)
                    pcall(ms.reload)
                end)
                if tap then ms._hotkeyHandles.quickReload = tap; tap:start() end

                -- Full Reload
                hk = ms._hotkeys.fullReload
                tap = ms._makeKeyWatcher(hk.mods, hk.key, function()
                    if not ms._loadComplete then return end
                    hs.reload()
                end)
                if tap then ms._hotkeyHandles.fullReload = tap; tap:start() end

                -- Open Menu
                hk = ms._hotkeys.openMenu
                tap = ms._makeKeyWatcher(hk.mods, hk.key, function()
                    if not ms._loadComplete then return end
                    -- No _robloxActive / _isSafeZone guard: the menu is a
                    -- Hammerspoon UI, not a game action. It should open
                    -- regardless of target-app focus.
                    if ms._macroLabEnabled and ms.shell and ms.shell.toggle then
                        ms.shell.toggle()
                    elseif ms.ui and ms.ui.toggle then
                        ms.ui.toggle()
                    end
                end)
                if tap then ms._hotkeyHandles.openMenu = tap; tap:start() end

                -- Octane Mode
                hk = ms._hotkeys.octane
                tap = ms._makeKeyWatcher(hk.mods, hk.key, function()
                    if not ms._loadComplete then return end
                    if not ms._robloxActive and not ms._isSafeZone() then return end
                    ms.octane.toggle()
                end)
                if tap then ms._hotkeyHandles.octane = tap; tap:start() end
            end

            -- Register all hotkey taps with the resilience watchdog
            for _, tap in pairs(ms._hotkeyHandles) do
                if tap then ms._resilientTaps[#ms._resilientTaps+1] = tap end
            end

            -- Start the tap watchdog (2s poll)
            ms._tapWatchdog = hs.timer.doEvery(2, function()
                for _, tap in ipairs(ms._resilientTaps) do
                    if tap and not tap:isEnabled() then
                        tap:start()
                        if ms.dev then print("ms: revived a disabled eventtap") end
                    end
                end
            end)

            ms._bindHotkeys()

        -- END 7. Macro Bind Controller --

        -- 8. Utilities --

            -- Control flow logging helpers for hand-written macros
            -- Usage:  ms.log("if", condition, true)  → "[label] if (condition) → true"
            --         ms.log("for", "i=1,14", 14)    → "[label] for i=1,14 (14 iterations)"
            --         ms.log("while", condition, 5)   → "[label] while condition (5 iterations)"
            --         ms.log("repeat", condition, 3)  → "[label] repeat until condition (3 iterations)"
            --         ms.log("msg", "doing thing")    → "[label] doing thing"
            ms.log = function(kind, a, b)
                if not ms.dev then return end
                local msg
                if kind == "if" then
                    msg = "if (" .. tostring(a) .. ") → " .. tostring(b)
                elseif kind == "for" then
                    msg = "for " .. tostring(a) .. " (" .. tostring(b) .. " iterations)"
                elseif kind == "while" then
                    msg = "while " .. tostring(a) .. " (" .. tostring(b) .. " iterations)"
                elseif kind == "repeat" then
                    msg = "repeat until " .. tostring(a) .. " (" .. tostring(b) .. " iterations)"
                else
                    msg = tostring(kind) .. (a and (" " .. tostring(a)) or "")
                end
                if spoon and spoon.MsDevTools then
                    spoon.MsDevTools:macroLog(msg)
                end
            end

            -- Function call accumulator (tracks consecutive same-label calls)
            ms._fnAccum = { lastLabel = nil, count = 0, startTime = 0, timer = nil }
            local _fnFlush = function()
                local a = ms._fnAccum
                if a.count > 0 and a.lastLabel then
                    local dur = math.floor((hs.timer.absoluteTime() - a.startTime) / 1e6)
                    local msg = a.lastLabel
                    if a.count > 1 then msg = msg .. " \195\151" .. a.count end
                    if dur > 0 then msg = msg .. " (" .. dur .. "ms)" end
                    if ms.dev and ms.dev.log then
                        ms.dev.log({ type = "step", category = "macro", msg = "[" .. a.lastLabel .. "] " .. msg })
                    end
                end
                a.count = 0
                a.lastLabel = nil
                a.timer = nil
            end

            -- ms.fn: wraps a function in a coroutine with error handling and logging
            local _msFnWrap = function(fn, labelOrAsync)
                assert(type(fn) == "function", "ms.fn: fn must be a function")
                if labelOrAsync == false then return fn end

                local fnLabel = type(labelOrAsync) == "string" and labelOrAsync or nil

                return function(...)
                    local label = fnLabel or ms._pendingLabel or "macro"
                    ms._pendingLabel = nil

                    -- Accumulate consecutive calls to the same function
                    local a = ms._fnAccum
                    if a.lastLabel == label then
                        a.count = a.count + 1
                    else
                        _fnFlush()
                        a.lastLabel = label
                        a.count = 1
                        a.startTime = hs.timer.absoluteTime()
                    end
                    -- Reset flush timer (fires after 50ms of no new calls)
                    if a.timer then a.timer:stop() end
                    a.timer = hs.timer.doAfter(0.05, _fnFlush)

                    local ctx = {
                        cancelled  = false,
                        paused     = false,
                        callStack  = { label },
                    }

                    local coBody = function(...)
                        if ms.dev and ms.dev.log then
                            ms.dev.log({ type = "step", category = "macro", msg = "[" .. label .. "] ▶" })
                        end
                        local xok, xerr = xpcall(fn, debug.traceback, ...)
                        if ms.dev and ms.dev.log then
                            ms.dev.log({ type = "step", category = "macro", msg = "[" .. label .. "] ■" })
                        end
                        if not xok then
                            local tb = tostring(xerr)
                            print("═══ ms.fn error [" .. label .. "] ═══\n" .. tb)
                            if ms.dev and ms.dev.log then
                                ms.dev.log({ type = "error", event = "macro_error", macro = label, msg = tb })
                            end
                            ms.alert("Macro error [" .. label .. "] — see console", 6)
                        end
                    end
                    local co = coroutine.create(coBody)
                    ms._coroContext[co]    = ctx
                    ms._activeContexts[ctx] = true

                    if ms.dev and ms._branchTrace then spoon.MsDevTools:startTrace(co, label) end

                    local ok, err = coroutine.resume(co, ...)
                    if not ok then
                        print("═══ ms.fn resume error [" .. label .. "] ═══\n" .. tostring(err))
                    end

                    if coroutine.status(co) == "dead" then
                        if ms.dev then spoon.MsDevTools:stopTrace(co) end
                        ms._coroContext[co]    = nil
                        ms._activeContexts[ctx] = nil
                        if _keyFlushTimer then _keyFlushTimer:stop(); _keyFlushTimer = nil end
                        _keyFlush()
                        if ms.dev then spoon.MsDevTools:flushAll(ctx and ctx.callStack and ctx.callStack[1]) end
                    end
                end
            end

            -- ms.fn: callable table with registry
            ms.fn = setmetatable({
                registry = { _defs = {}, _defList = {} },

                define = function(id, fn, opts)
                    assert(type(id) == "string", "ms.fn.define: id must be a string")
                    local fnType = type(fn)
                    assert(fnType == "function" or (fnType == "table" and getmetatable(fn) and getmetatable(fn).__call),
                        "ms.fn.define: fn must be a function or callable table")
                    assert(not ms.fn.registry._defs[id],
                        "ms.fn.define: '" .. id .. "' is already registered")
                    opts = opts or {}
                    ms.fn.registry._defs[id] = {
                        fn      = fn,
                        label   = opts.label or id,
                        group   = opts.group or "user",
                        info    = opts.info,
                        params  = opts.params,      -- e.g. { {name="delay", type="number", default=100} }
                        icon    = opts.icon,
                        cleared = opts.cleared ~= false,  -- "clear for use" flag, defaults true
                    }
                    table.insert(ms.fn.registry._defList, id)
                end,

                lookup = function(id)
                    return ms.fn.registry._defs[id]
                end,

                list = function()
                    return ms.fn.registry._defList
                end,
            }, {
                __call = function(_, fn, labelOrAsync)
                    return _msFnWrap(fn, labelOrAsync)
                end,
            })

            -- Call stack helpers
            ms._capturedStack = nil

            -- Get current (innermost) label from call stack or captured stack
            -- Returns nil if not inside a macro context
            ms._getLabel = function()
                local co = coroutine.running()
                if co then
                    local ctx = ms._coroContext[co]
                    if ctx and ctx.callStack and #ctx.callStack > 0 then
                        return ctx.callStack[#ctx.callStack]
                    end
                end
                if ms._capturedStack and #ms._capturedStack > 0 then
                    return ms._capturedStack[#ms._capturedStack]
                end
                return nil
            end

            -- Get root (outermost) label — used for pause/resume identification
            ms._getRootLabel = function()
                local co = coroutine.running()
                if co then
                    local ctx = ms._coroContext[co]
                    if ctx and ctx.callStack and #ctx.callStack > 0 then
                        return ctx.callStack[1]
                    end
                end
                if ms._capturedStack and #ms._capturedStack > 0 then
                    return ms._capturedStack[1]
                end
                return nil
            end

            -- Get full call chain as "Root › Innermost" string (cap 2 levels)
            ms._getCallChain = function()
                local co = coroutine.running()
                local stack = nil
                if co then
                    local ctx = ms._coroContext[co]
                    stack = ctx and ctx.callStack
                end
                if not stack and ms._capturedStack then
                    stack = ms._capturedStack
                end
                if stack and #stack > 0 then
                    if #stack == 1 then
                        return stack[1]
                    else
                        return stack[1] .. " › " .. stack[#stack]
                    end
                end
                return nil
            end

            -- ms.sub: register a sub-function with automatic call stack tracking
            ms.sub = function(label, fn)
                assert(type(fn) == "function", "ms.sub: fn must be a function")
                return function(...)
                    local co = coroutine.running()
                    local ctx = co and ms._coroContext[co]
                    if ctx then
                        if not ctx.callStack then ctx.callStack = {} end
                        table.insert(ctx.callStack, label)
                        local results = { fn(...) }
                        table.remove(ctx.callStack)
                        return table.unpack(results)
                    end
                    -- Not in coroutine — check captured stack (ms.after callback)
                    if ms._capturedStack then
                        table.insert(ms._capturedStack, label)
                        local results = { fn(...) }
                        table.remove(ms._capturedStack)
                        return table.unpack(results)
                    end
                    return fn(...)
                end
            end

            ms.pause = function(id)
                if not id then
                    for _, ctx in pairs(ms._activeContexts) do ctx.paused = true end
                    return
                end
                for _, ctx in pairs(ms._activeContexts) do
                    if ctx.callStack and ctx.callStack[1] == id then ctx.paused = true; return end
                end
            end

            ms.resume = function(id)
                local function _resume(co)
                    local ctx = ms._coroContext[co]
                    if not ctx then return end
                    ctx.paused = false
                    if coroutine.status(co) ~= "suspended" then return end
                    local ok, err = coroutine.resume(co)
                    if not ok then
                        print("═══ ms.resume error [" .. (ctx.callStack and ctx.callStack[1] or "?") .. "] ═══\n" .. tostring(err))
                    end
                    if coroutine.status(co) == "dead" then
                        if ms.dev then spoon.MsDevTools:stopTrace(co) end
                        ms._coroContext[co] = nil
                        ms._activeContexts[ctx] = nil
                        if _keyFlushTimer then _keyFlushTimer:stop(); _keyFlushTimer = nil end
                        _keyFlush()
                        if ms.dev then spoon.MsDevTools:flushAll(ctx.callStack and ctx.callStack[1]) end
                    end
                end
                if not id then
                    for co in pairs(ms._coroContext) do _resume(co) end
                    return
                end
                for co, ctx in pairs(ms._coroContext) do
                    if ctx.callStack and ctx.callStack[1] == id then _resume(co); return end
                end
            end

            ms.copy = function(text)
                if ms.dev then spoon.MsDevTools:flushAll() end
                if ms.dev._watcherPanel then
                    spoon.MsDevTools:watcherStep("copy")
                end
                if ms.dev then
                    spoon.MsDevTools:macroLog("copy")
                end
                hs.pasteboard.setContents(text)
            end

            ms.cancelMacros = function()
                for co, ctx in pairs(ms._coroContext) do
                    ctx.cancelled = true
                    if ms.dev then spoon.MsDevTools:stopTrace(co) end
                end

                ms._activeContexts = {}
                ms._coroContext     = {}

                if ms.dev then spoon.MsDevTools:flushAll() end

                for keyCode, entry in pairs(ms._macroHeldKeys) do
                    local ev = hs.eventtap.event.newKeyEvent(entry.mods, keyCode, false)
                    if entry.hidinject then
                        local app = hs.application.get(ms._targetApp or "Roblox")
                        if app then ev:post(app)
                        else
                            ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                            ev:post()
                        end
                    else
                        ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                        ev:post()
                    end
                end
                ms._macroHeldKeys = {}

                for btn, entry in pairs(ms._macroHeldButtons) do
                    local ev = hs.eventtap.event.newMouseEvent(entry.upT, entry.pos)
                    if btn >= 2 then
                        ev:setProperty(hs.eventtap.event.properties.mouseEventButtonNumber, btn)
                    end
                    if entry.app then ev:post(entry.app)
                    else
                        ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                        ev:post()
                    end
                end
                ms._macroHeldButtons = {}
            end

            ms._soundsDirty = true  -- force the first scan at startup

            -- Auto-sort: move misplaced sounds to correct folder based on prefix.
            -- d_* → sounds/defaults/, a_* → sounds/active/, m_* → sounds/macro/
            ms._autoSortSounds = function()
                local SoundLib = hs.configdir .. "/sounds/"
                local dirs = {
                    { dir = SoundLib .. "defaults/", prefix = "d_", match = { "d_" } },
                    { dir = SoundLib .. "active/",   prefix = "a_", match = { "a_" } },
                    { dir = SoundLib .. "macro/",    prefix = "m_", match = { "m_" } },
                }
                for _, info in ipairs(dirs) do
                    if hs.fs.attributes(info.dir) then
                        for file in hs.fs.dir(info.dir) do
                            if file ~= "." and file ~= ".." and file:match("%.wav$") then
                                local name = file:match("^(.+)%.[^%.]+$")
                                if name then
                                    -- Check if prefix matches this directory
                                    local belongs = false
                                    for _, pfx in ipairs(info.match) do
                                        if name:sub(1, #pfx) == pfx then belongs = true; break end
                                    end
                                    if not belongs then
                                        -- Find correct directory
                                        for _, dest in ipairs(dirs) do
                                            for _, pfx in ipairs(dest.match) do
                                                if name:sub(1, #pfx) == pfx then
                                                    local src = info.dir .. file
                                                    local dst = dest.dir .. file
                                                    if src ~= dst then
                                                        os.rename(src, dst)
                                                    end
                                                    break
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end

            ms._discoverSounds = function()
                if not ms._soundsDirty then return end
                ms._soundsDirty = false
                ms.sounds      = {}
                ms.macroSounds = {}

                -- Auto-sort misplaced sounds before scanning
                pcall(ms._autoSortSounds)

                -- Helper: scan a directory for .wav files into a target table
                local function scanDir(dir, target)
                    target = target or ms.sounds
                    if not hs.fs.attributes(dir) then return end
                    for file in hs.fs.dir(dir) do
                        if file ~= "." and file ~= ".." then
                            local name = file:match("^(.+)%.[^%.]+$")
                            if name then
                                target[name] = dir .. file
                            end
                        end
                    end
                end

                -- Always load defaults
                scanDir(SoundDefaultsDir)

                -- Active profile sounds (gated by custom theme setting)
                if not ms._customThemeDisabled then
                    scanDir(SoundActiveDir)
                end

                -- Macro-specific sounds (separate category)
                scanDir(SoundMacroDir, ms.macroSounds)

                -- Imported sounds (MSPKG) also gated by custom theme setting
                for name, filename in pairs(ms.importedSounds or {}) do
                    if not ms._customThemeDisabled and not ms.sounds[name] then
                        local path = SoundLib .. filename
                        if hs.fs.attributes(path) then
                            ms.sounds[name] = path
                        end
                    end
                end
            end

            ms.sound = function(path, async, device)
                if ms.dev then spoon.MsDevTools:flushAll() end
                -- Resolve name to path if not a file path
                if path and not path:match("[/\\]") then
                    path = ms.sounds[path] or ms.macroSounds[path] or path
                end
                if path then
                    local fname = tostring(path):match("([^/\\]+)$") or tostring(path)
                    -- Dedup: skip if same sound was logged last time
                    if fname ~= ms._lastSoundLog then
                        ms._lastSoundLog = fname
                        if ms.dev then
                            local displayLabel = ms._getCallChain()
                            if displayLabel then
                                ms.dev.log({
                                    type = "sound",
                                    msg = "[" .. displayLabel .. "] " .. fname,
                                    category = "macro"
                                })
                            end
                        end
                    end
                end
                if not ms.soundEnabled then return end
                if not path then return end
                local s = hs.sound.getByFile(path) or hs.sound.getByName(path)
                if not s then
                    print("ms.sound: could not load sound: " .. tostring(path))
                    return
                end
                if ms.soundVolume ~= nil then
                    s:volume(ms.soundVolume / 100)
                end
                if device then
                    local dev = hs.audiodevice.findOutputByName(device)
                    if dev then s:device(dev:uid()) end
                end
                async = (async ~= false)
                if not async then
                    local co  = coroutine.running()
                    local ctx = co and ms._coroContext[co]  -- capture at yield time
                    if co then
                        s:setCallback(function(snd, state)
                            if state == "stop" then
                                snd:setCallback(nil)
                                if ctx and ctx.cancelled then return end
                                local ok, err = coroutine.resume(co)
                                if not ok then
                                    print("ms.sound resume error: " .. tostring(err))
                                end
                                if coroutine.status(co) == "dead" then
                                    if ms.dev then spoon.MsDevTools:stopTrace(co) end
                                    ms._coroContext[co] = nil
                                    if ctx then ms._activeContexts[ctx] = nil end
                                    if _keyFlushTimer then _keyFlushTimer:stop(); _keyFlushTimer = nil end
                                    _keyFlush()
                                    if ms.dev then spoon.MsDevTools:flushAll() end
                                end
                            end
                        end)
                        s:play()
                        coroutine.yield()
                        return
                    end
                end
                s:play()
                return s  -- return handle so callers can stop playback
            end

            local _slotDefaults = {
                load         = { "d_LoadEnd",   "d_Load End"   },
                launch       = { "d_Launch" },
                themeLoaded  = { "d_ThemeLoaded", "d_Theme Loaded" },
                updateAvailable = { "d_UpdateAvailable", "d_Update Available" },
            }
            ms.playSlot = function(slotId)
                if not ms.soundEnabled then return false end
                -- Suppress all sounds during reload to avoid jarring duplicate close/open sounds
                if ms._quickReloading then return false end
                -- Octane sound mute: independent axis from the master octane toggle
                if ms._octaneMode and ms._octaneMuteSounds then return false end
                if not ms._startupSoundDone and slotId ~= "load" and slotId ~= "themeLoaded" and slotId ~= "updateAvailable" and slotId ~= "settingsOpen" and slotId ~= "settingsClose" then return false end
                ms._slotHandles = ms._slotHandles or {}
                -- If this slot is already playing, stop it and play fresh
                -- (allows rapid hover/interact sounds without gaps)
                if ms._slotHandles[slotId] then
                    pcall(function() ms._slotHandles[slotId]:stop() end)
                    ms._slotHandles[slotId] = nil
                end
                local assigned = ms.soundAssign and ms.soundAssign[slotId]
                local path
                if assigned then
                    path = (ms.sounds and ms.sounds[assigned])
                        or (ms.macroSounds and ms.macroSounds[assigned])
                        or assigned
                else
                    path = ms.sounds and ms.sounds[slotId]
                    if not path then path = ms.macroSounds and ms.macroSounds[slotId] end
                    if not path then
                        local candidates = _slotDefaults[slotId]
                        if candidates then
                            for _, name in ipairs(candidates) do
                                path = ms.sounds and ms.sounds[name]
                                if path then break end
                            end
                        end
                    end
                end
                if not path then return false end
                local handle = ms.sound(path) or false
                if handle then ms._slotHandles[slotId] = handle end
                return handle
            end

            ms._biasedMenuPt = function(raw)
                local p  = raw or hs.mouse.absolutePosition()
                local sf = hs.screen.mainScreen():frame()
                return {
                    x = p.x * 0.75 + (sf.x + sf.w * 0.2) * 0.12,
                    y = p.y * 0.75 + (sf.y + sf.h * 0.2) * 0.12,
                }
            end

            ms._menuHoverStart = function()
                if ms._menuHoverWatcher then return end
                local lastKey = nil
                ms._menuHoverWatcher = hs.timer.doEvery(0.025, function()
                    if not ms._menuVisible then return end
                    local el = hs.uielement.focusedElement()
                    if not el then return end
                    local ok, frame = pcall(function() return el:frame() end)
                    if not ok or not frame then return end
                    local key = frame.x .. "," .. frame.y
                    if key ~= lastKey then
                        lastKey = key
                        ms.playSlot("hover")
                    end
                end)
            end

            ms._menuHoverStop = function()
                if ms._menuHoverWatcher then
                    ms._menuHoverWatcher:stop()
                    ms._menuHoverWatcher = nil
                end
            end

            ms.mousePos = function()
                local win = ms.getTargetWin() or hs.window.focusedWindow()
                local pos = hs.mouse.absolutePosition()
                if not win then return pos.x, pos.y end
                local f = win:frame()
                local relX = (pos.x - f.x) * (REF_W / f.w)
                local relY = (pos.y - f.y) * (REF_H / f.h)
                return relX, relY
            end

            ms.pixelColor = function(x, y, reference)
                reference = reference or "Absolute"
                local ax, ay = ms.resolvePoint(x, y, reference)
                if not ax or not ay then return nil end

                local screen = hs.screen.mainScreen()
                for _, scr in ipairs(hs.screen.allScreens()) do
                    local f = scr:frame()
                    if ax >= f.x and ax < f.x + f.w
                    and ay >= f.y and ay < f.y + f.h then
                        screen = scr; break
                    end
                end

                local scale = (screen:currentMode() and screen:currentMode().scale) or 1
                local img = screen:snapshot({ x = ax, y = ay, w = 1, h = 1 })
                if not img then return nil end
                local px = math.floor(scale / 2)
                local py = math.floor(scale / 2)
                local c = img:colorAt({ x = px, y = py })
                if not c then return nil end

                return {
                    r = math.floor((c.red   or 0) * 255 + 0.5),
                    g = math.floor((c.green or 0) * 255 + 0.5),
                    b = math.floor((c.blue  or 0) * 255 + 0.5),
                    a = math.floor((c.alpha or 1) * 255 + 0.5),
                }
            end

            ms.pixelMatch = function(x, y, reference, r, g, b, tolerance)
                tolerance = tolerance or 10
                local c = ms.pixelColor(x, y, reference)
                if not c then return false end
                return math.abs(c.r - r) <= tolerance
                   and math.abs(c.g - g) <= tolerance
                   and math.abs(c.b - b) <= tolerance
            end

            -- Random wait between min and max milliseconds
            ms.randWait = function(min, max)
                ms.wait(math.random(min, max))
            end

            -- Wait base milliseconds ± jitter
            ms.jitter = function(base, jitterMs)
                ms.wait(base + math.random(-jitterMs, jitterMs))
            end

            -- Save/restore cursor position
            local _savedCursor = nil
            ms.saveCursor = function()
                _savedCursor = hs.mouse.absolutePosition()
                return _savedCursor
            end
            ms.restoreCursor = function()
                if _savedCursor then
                    hs.mouse.absolutePosition(_savedCursor)
                end
            end

            -- Check if an app is running
            ms.appRunning = function(appName)
                return hs.application.get(appName) ~= nil
            end

            -- Check if an app is the frontmost application
            ms.appIsFront = function(appName)
                local front = hs.application.frontmostApplication()
                return front and front:name() == appName
            end

            -- Focus (activate) an app by name
            ms.focus = function(appName)
                local app = hs.application.get(appName)
                if app then
                    pcall(function() app:activate() end)
                    return true
                end
                return false
            end

            -- Toggle a key: press if not held, release if held
            ms.toggle = function(key, mods)
                if ms.keystate(key) then
                    ms.release(key, mods)
                else
                    ms.press(key, mods)
                end
            end

            -- Wait until a pixel matches expected color (poll loop)
            ms.waitPixel = function(x, y, ref, r, g, b, tol, timeout)
                timeout = timeout or 5000
                local deadline = hs.timer.absoluteTime() + timeout * 1000000
                while hs.timer.absoluteTime() < deadline do
                    if ms.pixelMatch(x, y, ref, r, g, b, tol or 10) then return true end
                    ms.wait(50)
                end
                return false
            end

            -- Wait until a pixel does NOT match expected color (poll loop)
            ms.waitNotPixel = function(x, y, ref, r, g, b, tol, timeout)
                timeout = timeout or 5000
                local deadline = hs.timer.absoluteTime() + timeout * 1000000
                while hs.timer.absoluteTime() < deadline do
                    if not ms.pixelMatch(x, y, ref, r, g, b, tol or 10) then return true end
                    ms.wait(50)
                end
                return false
            end

            -- Wait until an app appears (poll loop)
            ms.waitApp = function(appName, timeout)
                timeout = timeout or 10000
                local deadline = hs.timer.absoluteTime() + timeout * 1000000
                while hs.timer.absoluteTime() < deadline do
                    if hs.application.get(appName) then return true end
                    ms.wait(100)
                end
                return false
            end

            -- Wait until an app disappears (poll loop)
            ms.waitNotApp = function(appName, timeout)
                timeout = timeout or 10000
                local deadline = hs.timer.absoluteTime() + timeout * 1000000
                while hs.timer.absoluteTime() < deadline do
                    if not hs.application.get(appName) then return true end
                    ms.wait(100)
                end
                return false
            end

            -- Get window position of an app (returns {x, y, w, h} or nil)
            ms.windowPos = function(appName)
                local app = hs.application.get(appName)
                if not app then return nil end
                local win = app:mainWindow()
                if not win then return nil end
                local f = win:frame()
                return { x = f.x, y = f.y, w = f.w, h = f.h }
            end

            -- Press multiple keys in sequence with optional delay between them
            ms.multiPress = function(keys, delayMs, mods, hidinject)
                delayMs = delayMs or 15
                for i, key in ipairs(keys) do
                    ms.type(key, mods, hidinject)
                    if i < #keys then ms.wait(delayMs) end
                end
            end

            -- Set system volume (0-100)
            ms.setVolume = function(level)
                local dev = hs.audiodevice.defaultOutputDevice()
                if dev then dev:setVolume(level) end
            end

            -- Mute system audio
            ms.mute = function()
                local dev = hs.audiodevice.defaultOutputDevice()
                if dev then dev:setMuted(true) end
            end

            -- Unmute system audio
            ms.unmute = function()
                local dev = hs.audiodevice.defaultOutputDevice()
                if dev then dev:setMuted(false) end
            end

            -- Take a screenshot and save to path
            ms.screenshot = function(path)
                path = path or os.getenv("HOME") .. "/Desktop/screenshot_" .. os.date("%Y%m%d_%H%M%S") .. ".png"
                local screen = hs.screen.mainScreen()
                if not screen then return nil end
                local img = screen:snapshot()
                if not img then return nil end
                img:saveToFile(path)
                return path
            end

            -- Watch for clipboard changes
            local _clipWatcher = nil
            ms.clipChanged = function(callback)
                if _clipWatcher then _clipWatcher:stop() end
                _clipWatcher = hs.pasteboard.watcher.new(callback)
                _clipWatcher:start()
                return _clipWatcher
            end

            -- Animated mouse movement (interpolated over duration)
            ms.moveMouse = function(x, y, ref, durationMs)
                durationMs = durationMs or 200
                local targetX, targetY = ms.resolvePoint(x, y, ref or "Absolute")
                local startPos = hs.mouse.absolutePosition()
                local startX, startY = startPos.x, startPos.y
                local dx = targetX - startX
                local dy = targetY - startY
                local steps = math.max(10, math.floor(durationMs / 16))
                local step = 0
                local timer = hs.timer.doEvery(0.016, function()
                    step = step + 1
                    local t = math.min(step / steps, 1)
                    -- Ease out cubic
                    t = 1 - (1 - t) ^ 3
                    hs.mouse.absolutePosition({
                        x = startX + dx * t,
                        y = startY + dy * t,
                    })
                    if step >= steps then
                        hs.mouse.absolutePosition({ x = targetX, y = targetY })
                        return false -- stop timer
                    end
                end)
                return timer
            end

            -- Multi-point drag: press at points[1], drag through points[2..N], release
            ms.dragPath = function(points, button, ref, delayMs)
                if not points or #points < 2 then return end
                button = button or "Left"
                delayMs = delayMs or 10
                local btnNum = button == "Right" and 1 or (button == "Middle" and 2 or 0)
                local downType = btnNum == 1 and hs.eventtap.event.types.rightMouseDown
                    or (btnNum == 2 and hs.eventtap.event.types.otherMouseDown
                    or hs.eventtap.event.types.leftMouseDown)
                local upType = btnNum == 1 and hs.eventtap.event.types.rightMouseUp
                    or (btnNum == 2 and hs.eventtap.event.types.otherMouseUp
                    or hs.eventtap.event.types.leftMouseUp)
                local dragType = btnNum == 1 and hs.eventtap.event.types.rightMouseDragged
                    or (btnNum == 2 and hs.eventtap.event.types.otherMouseDragged
                    or hs.eventtap.event.types.leftMouseDragged)

                -- Resolve first point and press
                local x1, y1 = ms.resolvePoint(points[1][1], points[1][2], ref or "Absolute")
                hs.mouse.absolutePosition({ x = x1, y = y1 })
                local downEv = hs.eventtap.event.newMouseEvent(downType, { x = x1, y = y1 })
                if btnNum > 0 then downEv:setProperty(hs.eventtap.event.properties.mouseEventButtonNumber, btnNum) end
                downEv:post()
                ms.wait(delayMs)

                -- Drag through remaining points
                for i = 2, #points do
                    local px, py = ms.resolvePoint(points[i][1], points[i][2], ref or "Absolute")
                    hs.mouse.absolutePosition({ x = px, y = py })
                    local dragEv = hs.eventtap.event.newMouseEvent(dragType, { x = px, y = py })
                    if btnNum > 0 then dragEv:setProperty(hs.eventtap.event.properties.mouseEventButtonNumber, btnNum) end
                    dragEv:post()
                    ms.wait(delayMs)
                end

                -- Release
                local finalPos = hs.mouse.absolutePosition()
                local upEv = hs.eventtap.event.newMouseEvent(upType, finalPos)
                if btnNum > 0 then upEv:setProperty(hs.eventtap.event.properties.mouseEventButtonNumber, btnNum) end
                upEv:post()
            end

            -- Native macOS notification
            ms.notify = function(title, subTitle, infoText)
                local note = hs.notify.new({
                    title = title or "mudscript",
                    subTitle = subTitle or "",
                    informativeText = infoText or "",
                }):send()
                return note
            end

            -- Anti-Timeout — prevents Roblox 20-minute inactivity kick
                ms._antiTimeout = { fn = nil, interval = 900, timer = nil, running = false }

                ms.antiTimeout = function(config)
                    assert(type(config) == "table", "ms.antiTimeout: config must be a table")
                    assert(type(config.action) == "function", "ms.antiTimeout: config.action must be a function")

                    ms._antiTimeout.fn       = config.action
                    ms._antiTimeout.interval = tonumber(config.interval) or 900

                    -- Respect the settings toggle
                    local enabled  = config.enabled
                    if enabled == nil then enabled = true end
                    -- Settings toggle overrides macro config when explicitly set
                    if ms._antiTimeoutEnabled == true then
                        enabled = true
                    elseif ms._antiTimeoutEnabled == false then
                        enabled = false
                    end

                    -- Stop any existing timer
                    if ms._antiTimeout.timer then
                        ms._antiTimeout.timer:stop()
                        ms._antiTimeout.timer = nil
                    end

                    if enabled then
                        ms._antiTimeout.running = true
                        local wrappedFn = ms.fn(ms._antiTimeout.fn)
                        ms._antiTimeout.timer = hs.timer.doEvery(ms._antiTimeout.interval, function()
                            if not ms._antiTimeout.running then return end
                            if not ms._robloxActive then return end
                            pcall(wrappedFn)
                        end)
                    else
                        ms._antiTimeout.running = false
                    end
                end

                ms.antiTimeoutStop = function()
                    ms._antiTimeout.running = false
                    if ms._antiTimeout.timer then
                        ms._antiTimeout.timer:stop()
                        ms._antiTimeout.timer = nil
                    end
                end

                ms.antiTimeoutStart = function()
                    if not ms._antiTimeout.fn then return end
                    ms._antiTimeout.running = true
                    if not ms._antiTimeout.timer then
                        local wrappedFn = ms.fn(ms._antiTimeout.fn)
                        ms._antiTimeout.timer = hs.timer.doEvery(ms._antiTimeout.interval, function()
                            if not ms._antiTimeout.running then return end
                            if not ms._robloxActive then return end
                            pcall(wrappedFn)
                        end)
                    end
                end

                ms.antiTimeoutToggle = function()
                    if ms._antiTimeout.running then
                        ms.antiTimeoutStop()
                    else
                        ms.antiTimeoutStart()
                    end
                    return ms._antiTimeout.running
                end
            -- END Anti-Timeout --

        -- END 8. Utilities --

        -- 9. Bind System & Settings Panel --
            ms.bind.define = function(id, a, b)
                assert(type(id) == "string", "ms.bind.define: id must be a string")
                local fn   = type(a) == "function" and a or (type(b) == "function" and b or nil)
                local opts = type(a) == "table"    and a or (type(b) == "table"    and b or {})
                -- Reject legacy sub/mod syntax — user must update ms_macros.lua
                if opts.sub or opts.mod then
                    error("bind '" .. id .. "' uses deprecated sub/mod syntax. "
                        .. "Update to: default = { type = \"<parentID>\", mods = {\"<mod>\"} } "
                        .. "— see documentation for the unified bind model.", 2)
                end
                local label, group
                if opts.default and type(opts.default) == "table" and opts.default.type
                    and ms.registry._defs[opts.default.type] then
                    -- Derived bind: inherit label/group conventions
                    label = opts.label or id
                    group = opts.group
                else
                    if opts.label then
                        label = opts.label
                    else
                        ms.bind._autoCount = ms.bind._autoCount + 1
                        label = "Macro" .. ms.bind._autoCount
                    end
                    group = opts.group or "main"
                end
                ms.registry._defs[id] = {
                    label    = label,
                    group    = group,
                    enabled  = (opts.enabled ~= false),
                    cooldown = opts.cooldown or 1000,
                    shared   = opts.shared,
                    info     = opts.info,
                    default  = opts.default,
                    system   = opts.system or false,
                }
                table.insert(ms.registry._defList, id)
                if fn ~= nil then
                    assert(type(fn) == "function",
                        "ms.bind.define: fn must be a function for id '" .. id .. "'")
                    ms.bind._wires[id] = fn
                end
            end

            ms.bind._registerSystemBinds = function()
                ms.bind.define("__panicButton", nil, {
                    label      = "Panic Button / Stop All",
                    group      = "system",
                    enabled    = true,
                    system     = true,
                    default    = { type = "key", mods = {"alt"}, key = "F10" },
                })
                ms.bind.define("__quickReload", nil, {
                    label      = "Quick Reload",
                    group      = "system",
                    enabled    = true,
                    system     = true,
                    default    = { type = "key", mods = {"alt"}, key = "[" },
                })
                ms.bind.define("__fullReload", nil, {
                    label      = "Full Reload",
                    group      = "system",
                    enabled    = true,
                    system     = true,
                    default    = { type = "key", mods = {"alt"}, key = "]" },
                })
                ms.bind.define("__openMenu", nil, {
                    label      = "Open Menu",
                    group      = "system",
                    enabled    = true,
                    system     = true,
                    default    = { type = "key", mods = {"alt"}, key = "p" },
                })
                -- Wire up system bind actions
                ms.bind._wires["__panicButton"] = function()
                    ms.setMacros(0)
                end
                ms.bind._wires["__quickReload"] = function()
                    if ms._qrCooldown then return end
                    ms._qrCooldown = true
                    hs.timer.doAfter(1.0, function() ms._qrCooldown = false end)
                    if ms.reload then ms.reload() end
                end
                ms.bind._wires["__fullReload"] = function()
                    hs.reload()
                end
                -- __openMenu is handled by _bindHotkeys() via _makeKeyWatcher.
                -- No wire here — having both would double-fire toggle().
            end

            ms.systemBinds._defs = {
                enable  = { label = "Enable Macros",  default = { type = "key", mods = {}, key = "return" } },
                disable = { label = "Disable Macros", default = { type = "key", mods = {}, key = "/" } },
                toggle  = { label = "Toggle Macros",  default = { type = "key", mods = {}, key = "escape" } },
            }
            ms.systemBinds._actions = {
                enable  = function() ms.setMacros(1) end,
                disable = function() ms.setMacros(0) end,
                toggle  = function() ms.setMacros(BindValidity == 1 and 0 or 1) end,
            }

            ms.systemBinds.effective = function(id)
                return ms.systemBinds._config[id]
                    or (ms.systemBinds._defs[id] and ms.systemBinds._defs[id].default)
            end

            ms.systemBinds.bindStr = function(id)
                local c = ms.systemBinds.effective(id)
                if not c then return "( unset )" end
                if c.type == "mouse" then return "Mouse " .. tostring(c.button) end
                if c.type == "scroll" then
                    local d = c.direction or "?"
                    return "Scroll " .. d:sub(1,1):upper() .. d:sub(2)
                end
                if c.type == "gamepad" then return "Pad " .. (c.button or "?"):upper() end
                local parts = {}
                for _, m in ipairs(c.mods or {}) do table.insert(parts, m:sub(1, 1):upper() .. m:sub(2)) end
                table.insert(parts, (c.key or ""):upper())
                return table.concat(parts, "+")
            end

            ms.systemBinds.rebind = function()
                for _, h in pairs(ms.systemBinds._handles) do
                    if h and h.delete then h:delete() end
                end
                ms.systemBinds._handles = {}

                for id, action in pairs(ms.systemBinds._actions) do
                    local c = ms.systemBinds.effective(id)
                    if not c then goto sysBindContinue end
                    if c.type == "key" then
                        local tap = ms._makeKeyWatcher(c.mods, c.key, function()
                            if not ms._robloxActive and not ms._isSafeZone() then return end
                            local co = coroutine.create(action)
                            local ok, err = coroutine.resume(co)
                            if not ok then print("ms.systemBind error: " .. tostring(err)) end
                        end)
                        if tap then ms.systemBinds._handles[id] = tap; tap:start() end
                    elseif c.type == "mouse" then
                        ms.systemBinds._handles[id] = ms.mouse(c.button, false, function()
                            if not ms._robloxActive and not ms._isSafeZone() then return end
                            local co = coroutine.create(action)
                            local ok, err = coroutine.resume(co)
                            if not ok then print("ms.systemBind error: " .. tostring(err)) end
                        end, true)
                    elseif c.type == "scroll" then
                        ms.systemBinds._handles[id] = ms.scrollBind(c.direction, function()
                            if not ms._robloxActive and not ms._isSafeZone() then return end
                            local co = coroutine.create(action)
                            local ok, err = coroutine.resume(co)
                            if not ok then print("ms.systemBind error: " .. tostring(err)) end
                        end)
                    elseif c.type == "gamepad" then
                        ms.systemBinds._handles[id] = ms.gamepadBind(c.button, function()
                            if not ms._robloxActive and not ms._isSafeZone() then return end
                            local co = coroutine.create(action)
                            local ok, err = coroutine.resume(co)
                            if not ok then print("ms.systemBind error: " .. tostring(err)) end
                        end)
                    end
                    ::sysBindContinue::
                end
            end

            ms.bind.group = function(id)
                local def = ms.registry._defs[id]
                if not def then return "G_" .. tostring(id) end
                if def.shared then return def.shared end
                -- Walk derived triggers to find the root bind for group resolution
                local current, seen = id, {}
                while true do
                    local d = ms.registry._defs[current]
                    if not d or not d.default or type(d.default) ~= "table"
                        or not d.default.type or not ms.registry._defs[d.default.type]
                        or seen[current] then break end
                    seen[current] = true
                    current = d.default.type
                end
                local rootDef = ms.registry._defs[current]
                if rootDef and rootDef.shared then return rootDef.shared end
                return "G_" .. current
            end

            ms.done = function(id)
                local group = ms.bind.group(id)
                local timer = ms.running[group]
                if timer then
                    timer:stop()
                    ms.running[group] = nil
                end
            end

            -- Register built-in utility functions for macro lab auto-detection
            -- Input
            ms.fn.define("ms.press", ms.press, {
                label  = "Press Key",
                group  = "input",
                info   = "Press and release a key",
                params = { {name = "key", type = "string"}, {name = "mods", type = "table"} },
                icon   = "inputs",
            })
            ms.fn.define("ms.release", ms.release, {
                label  = "Release Key",
                group  = "input",
                info   = "Release a held key",
                params = { {name = "key", type = "string"}, {name = "mods", type = "table"} },
                icon   = "inputs",
            })
            ms.fn.define("ms.type", ms.type, {
                label  = "Type Key",
                group  = "input",
                info   = "Type a key with modifiers and optional hold duration",
                params = { {name = "key", type = "string"}, {name = "mods", type = "table"}, {name = "holdMs", type = "number"} },
                icon   = "inputs",
            })
            ms.fn.define("ms.toggle", ms.toggle, {
                label  = "Toggle Key",
                group  = "input",
                info   = "Toggle a key on/off",
                params = { {name = "key", type = "string"}, {name = "mods", type = "table"} },
                icon   = "inputs",
            })
            ms.fn.define("ms.multiPress", ms.multiPress, {
                label  = "Multi Press",
                group  = "input",
                info   = "Press multiple keys in sequence",
                params = { {name = "keys", type = "table"}, {name = "delayMs", type = "number"}, {name = "mods", type = "table"} },
                icon   = "inputs",
            })
            ms.fn.define("ms.Mouse", ms.Mouse, {
                label  = "Mouse",
                group  = "mouse",
                info   = "Full mouse control (Click, Drag, Move, etc.)",
                params = { {name = "operation", type = "string"}, {name = "button", type = "string"}, {name = "reference", type = "string"}, {name = "x", type = "number"}, {name = "y", type = "number"} },
                icon   = "move",
            })
            ms.fn.define("ms.scroll", ms.scroll, {
                label  = "Scroll",
                group  = "mouse",
                info   = "Scroll the mouse wheel",
                params = { {name = "direction", type = "string"}, {name = "clicks", type = "number"} },
                icon   = "scroll",
            })
            ms.fn.define("ms.moveMouse", ms.moveMouse, {
                label  = "Move Mouse",
                group  = "mouse",
                info   = "Move mouse to position with optional duration",
                params = { {name = "x", type = "number"}, {name = "y", type = "number"}, {name = "ref", type = "string"}, {name = "durationMs", type = "number"} },
                icon   = "move",
            })
            ms.fn.define("ms.dragPath", ms.dragPath, {
                label  = "Drag Path",
                group  = "mouse",
                info   = "Drag mouse through a series of points",
                params = { {name = "points", type = "table"}, {name = "button", type = "string"}, {name = "ref", type = "string"}, {name = "delayMs", type = "number"} },
                icon   = "move",
            })
            ms.fn.define("ms.cam", ms.cam, {
                label  = "Camera",
                group  = "mouse",
                info   = "Move camera by delta",
                params = { {name = "dx", type = "number"}, {name = "dy", type = "number"} },
                icon   = "move",
            })

            -- Timing
            ms.fn.define("ms.wait", ms.wait, {
                label  = "Wait",
                group  = "timing",
                info   = "Wait for a duration in milliseconds",
                params = { {name = "ms", type = "number", default = 100} },
                icon   = "pause",
            })
            ms.fn.define("ms.randWait", ms.randWait, {
                label  = "Random Wait",
                group  = "timing",
                info   = "Wait for a random duration between min and max",
                params = { {name = "min", type = "number"}, {name = "max", type = "number"} },
                icon   = "pause",
            })
            ms.fn.define("ms.jitter", ms.jitter, {
                label  = "Jitter",
                group  = "timing",
                info   = "Wait with random jitter around a base duration",
                params = { {name = "base", type = "number"}, {name = "jitterMs", type = "number"} },
                icon   = "pause",
            })

            -- Sensing
            ms.fn.define("ms.pixelColor", ms.pixelColor, {
                label  = "Pixel Color",
                group  = "sensing",
                info   = "Get the RGB color of a pixel",
                params = { {name = "x", type = "number"}, {name = "y", type = "number"}, {name = "ref", type = "string"} },
                icon   = "pixelscan",
            })
            ms.fn.define("ms.pixelMatch", ms.pixelMatch, {
                label  = "Pixel Match",
                group  = "sensing",
                info   = "Check if a pixel matches a color",
                params = { {name = "x", type = "number"}, {name = "y", type = "number"}, {name = "ref", type = "string"}, {name = "r", type = "number"}, {name = "g", type = "number"}, {name = "b", type = "number"}, {name = "tol", type = "number"} },
                icon   = "pixelscan",
            })
            ms.fn.define("ms.waitPixel", ms.waitPixel, {
                label  = "Wait for Pixel",
                group  = "sensing",
                info   = "Wait until a pixel matches a color",
                params = { {name = "x", type = "number"}, {name = "y", type = "number"}, {name = "ref", type = "string"}, {name = "r", type = "number"}, {name = "g", type = "number"}, {name = "b", type = "number"}, {name = "tol", type = "number"}, {name = "timeout", type = "number"} },
                icon   = "pixelscan",
            })
            ms.fn.define("ms.waitNotPixel", ms.waitNotPixel, {
                label  = "Wait for Pixel Change",
                group  = "sensing",
                info   = "Wait until a pixel no longer matches a color",
                params = { {name = "x", type = "number"}, {name = "y", type = "number"}, {name = "ref", type = "string"}, {name = "r", type = "number"}, {name = "g", type = "number"}, {name = "b", type = "number"}, {name = "tol", type = "number"}, {name = "timeout", type = "number"} },
                icon   = "pixelscan",
            })
            ms.fn.define("ms.mousePos", ms.mousePos, {
                label  = "Mouse Position",
                group  = "sensing",
                info   = "Get current mouse position",
                params = {},
                icon   = "move",
            })
            ms.fn.define("ms.keystate", ms.keystate, {
                label  = "Key State",
                group  = "sensing",
                info   = "Check if a key is currently held",
                params = { {name = "key", type = "string"} },
                icon   = "inputs",
            })

            -- Clipboard
            ms.fn.define("ms.copy", ms.copy, {
                label  = "Copy",
                group  = "clipboard",
                info   = "Copy text to clipboard",
                params = { {name = "text", type = "string"} },
                icon   = "save",
            })

            -- Window/App
            ms.fn.define("ms.appRunning", ms.appRunning, {
                label  = "App Running",
                group  = "app",
                info   = "Check if an app is running",
                params = { {name = "appName", type = "string"} },
                icon   = "window",
            })
            ms.fn.define("ms.appIsFront", ms.appIsFront, {
                label  = "App in Front",
                group  = "app",
                info   = "Check if an app is the frontmost",
                params = { {name = "appName", type = "string"} },
                icon   = "window",
            })
            ms.fn.define("ms.focus", ms.focus, {
                label  = "Focus App",
                group  = "app",
                info   = "Bring an app to the front",
                params = { {name = "appName", type = "string"} },
                icon   = "window",
            })
            ms.fn.define("ms.windowPos", ms.windowPos, {
                label  = "Window Position",
                group  = "app",
                info   = "Get the position of an app's window",
                params = { {name = "appName", type = "string"} },
                icon   = "window",
            })

            -- System
            ms.fn.define("ms.sound", ms.sound, {
                label  = "Play Sound",
                group  = "system",
                info   = "Play a sound file",
                params = { {name = "path", type = "string"} },
                icon   = "play",
            })
            ms.fn.define("ms.alert", ms.alert, {
                label  = "Alert",
                group  = "system",
                info   = "Show a toast notification",
                params = { {name = "msg", type = "string"}, {name = "duration", type = "number"} },
                icon   = "alert",
            })
            ms.fn.define("ms.notify", ms.notify, {
                label  = "Notify",
                group  = "system",
                info   = "Show a system notification",
                params = { {name = "title", type = "string"}, {name = "subTitle", type = "string"}, {name = "infoText", type = "string"} },
                icon   = "alert",
            })
            ms.fn.define("ms.screenshot", ms.screenshot, {
                label  = "Screenshot",
                group  = "system",
                info   = "Take a screenshot",
                params = { {name = "path", type = "string"} },
                icon   = "record",
            })
            ms.fn.define("ms.setVolume", ms.setVolume, {
                label  = "Set Volume",
                group  = "system",
                info   = "Set system volume (0-100)",
                params = { {name = "level", type = "number"} },
                icon   = "play",
            })
            ms.fn.define("ms.mute", ms.mute, {
                label  = "Mute",
                group  = "system",
                info   = "Mute system audio",
                params = {},
                icon   = "stop",
            })
            ms.fn.define("ms.unmute", ms.unmute, {
                label  = "Unmute",
                group  = "system",
                info   = "Unmute system audio",
                params = {},
                icon   = "play",
            })
            ms.fn.define("ms.clipChanged", ms.clipChanged, {
                label  = "Clipboard Changed",
                group  = "system",
                info   = "Register a callback for clipboard changes",
                params = { {name = "callback", type = "function"} },
                icon   = "watcher",
            })
            ms.fn.define("ms.saveCursor", ms.saveCursor, {
                label  = "Save Cursor",
                group  = "system",
                info   = "Save current cursor position",
                params = {},
                icon   = "save",
            })
            ms.fn.define("ms.restoreCursor", ms.restoreCursor, {
                label  = "Restore Cursor",
                group  = "system",
                info   = "Restore saved cursor position",
                params = {},
                icon   = "upload",
            })

            -- Macro Control
            ms.fn.define("ms.cancelMacros", ms.cancelMacros, {
                label  = "Cancel Macros",
                group  = "control",
                info   = "Cancel all running macros",
                params = {},
                icon   = "stop",
            })
            ms.fn.define("ms.pause", ms.pause, {
                label  = "Pause",
                group  = "control",
                info   = "Pause current macro",
                params = {},
                icon   = "pause",
            })
            ms.fn.define("ms.resume", ms.resume, {
                label  = "Resume",
                group  = "control",
                info   = "Resume paused macro",
                params = {},
                icon   = "play",
            })
            ms.fn.define("ms.done", ms.done, {
                label  = "Done",
                group  = "control",
                info   = "Signal macro completion",
                params = {},
                icon   = "stop",
            })

            ms.bind.teardown = function()
                for id, handle in pairs(ms.bindHandles) do
                    if handle and handle.delete then handle:delete() end
                end
                ms.bindHandles = {}
                ms._mouseCallbacks = {}
                ms._scrollCallbacks = {}
                if ms._scrollListener then
                    ms._scrollListener:stop()
                    ms._scrollListener = nil
                end
                ms._gamepadCallbacks = {}
                ms.gamepadStop()
            end

            ms.bind.rebind = function()
                ms.bind.teardown()

                local function bindKey(c)
                    if not c then return nil end
                    local mods = {}
                    for _, m in ipairs(c.mods or {}) do mods[#mods+1] = m end
                    table.sort(mods)
                    local modStr = #mods > 0 and (":" .. table.concat(mods, ",")) or ""
                    if c.type == "mouse"   then return "mouse:"   .. tostring(c.button) .. modStr end
                    if c.type == "scroll"  then return "scroll:"  .. (c.direction or "up") .. modStr end
                    if c.type == "gamepad" then return "gamepad:" .. (c.button or "?")  .. modStr end
                    return "key:" .. table.concat(mods, ",") .. ":" .. (c.key or "")
                end

                local function triggerKey(c)
                    if c.type == "mouse"   then return "mouse:"   .. tostring(c.button) end
                    if c.type == "scroll"  then return "scroll:"  .. (c.direction or "up") end
                    if c.type == "gamepad" then return "gamepad:" .. (c.button or "?") end
                    return nil
                end

                -- Count modifiers for a resolved bind (most-specific-wins ordering)
                local function modCount(c)
                    if not c or not c.mods then return 0 end
                    local n = 0; for _ in ipairs(c.mods) do n = n + 1 end; return n
                end

                local conflicted = {}

                -- Single conflict-detection pass: all binds go through the same
                -- key-conflict path (derived binds resolve via effectiveBind).
                local rootUsed = {}
                for _, id in ipairs(ms.registry._defList) do
                    local def = ms.registry._defs[id]
                    if not def then goto c1 end
                    local enabled = ms.binds[id]; if enabled == nil then enabled = def.enabled end
                    if not enabled then goto c1 end
                    local key = bindKey(ms.effectiveBind(id))
                    if key then
                        if rootUsed[key] then
                            local other = rootUsed[key]
                            conflicted[id] = true; conflicted[other] = true
                            local l1 = ms.registry._defs[id].label
                            local l2 = ms.registry._defs[other].label
                            hs.timer.doAfter(0, function()
                                ms.alert("Bind conflict: \"" .. l1 .. "\" and \"" .. l2
                                    .. "\" share the same input.\nBoth disabled — right-click the macro in the Macros panel › Rebind to resolve.", 10)
                            end)
                        else
                            rootUsed[key] = id
                        end
                    end
                    ::c1::
                end

                -- Registration: sort most-mods-first so more-specific binds
                -- are registered before less-specific ones (first-match-wins).
                local sortedIds = {}
                for _, id in ipairs(ms.registry._defList) do
                    sortedIds[#sortedIds + 1] = id
                end
                table.sort(sortedIds, function(a, b)
                    local ca = modCount(ms.effectiveBind(a))
                    local cb = modCount(ms.effectiveBind(b))
                    return ca > cb
                end)

                local deviceGroups = {}
                local deviceOrder  = {}

                for _, id in ipairs(sortedIds) do
                    if conflicted[id] then goto continue end
                    local fn  = ms.bind._wires[id]
                    local def = ms.registry._defs[id]
                    if not fn or not def then goto continue end

                    local group    = ms.bind.group(id)
                    local cooldown = ms.cooldowns[id] or def.cooldown or 1000

                    local enabled = ms.binds[id]
                    if enabled == nil then enabled = def.enabled end
                    if not enabled then goto continue end
                    local c = ms.effectiveBind(id)
                    if not c then goto continue end
                    local function firedFn()
                        if ms.running[group] then return end
                        ms.running[group] = hs.timer.doAfter(cooldown / 1000, function()
                            ms.running[group] = nil
                        end)
                        if ms.dev then
                            local _trig = (function()
                                if c.type == "mouse" then return "M" .. c.button end
                                if c.type == "scroll" then return "S:" .. (c.direction or "?") end
                                if c.type == "gamepad" then return "G:" .. (c.button or "?") end
                                local _p = {}
                                for _, m in ipairs(c.mods or {}) do _p[#_p+1] = m end
                                _p[#_p+1] = c.key or ""; return table.concat(_p, "+")
                            end)()
                            pcall(ms.dev._onMacroFire, id, def.label, nil, nil, _trig)
                        end
                        ms._pendingLabel = def.label
                        fn()
                    end
                    if c.type == "key" then
                        ms.bindHandles[id] = ms.key(c.mods, c.key, false, firedFn)
                    elseif c.type == "mouse" or c.type == "scroll" or c.type == "gamepad" then
                        local tkey = triggerKey(c)
                        local grp  = deviceGroups[tkey]
                        if not grp then
                            grp = { ctype = c.type, button = c.button, direction = c.direction, claimants = {} }
                            deviceGroups[tkey] = grp
                            deviceOrder[#deviceOrder + 1] = tkey
                        end
                        grp.claimants[#grp.claimants + 1] = { mods = c.mods or {}, firedFn = firedFn }
                    end

                    ::continue::
                end

                for _, tkey in ipairs(deviceOrder) do
                    local grp       = deviceGroups[tkey]
                    local claimants = grp.claimants
                    local function dispatch()
                        for _, cl in ipairs(claimants) do
                            local match = (#cl.mods == 0)
                            if not match then
                                match = true
                                for _, m in ipairs(cl.mods) do
                                    if not ms.keystate(m) then match = false; break end
                                end
                            end
                            if match then cl.firedFn(); return end
                        end
                    end
                    if grp.ctype == "mouse" then
                        ms.mouse(grp.button, false, dispatch)
                    elseif grp.ctype == "scroll" then
                        ms.bindHandles["_disp:" .. tkey] = ms.scrollBind(grp.direction, dispatch)
                    elseif grp.ctype == "gamepad" then
                        ms.bindHandles["_disp:" .. tkey] = ms.gamepadBind(grp.button, dispatch)
                    end
                end

                if ms.trackpadMode then
                    if ms._trackpadLeftListener  then ms._trackpadLeftListener:start()  end
                    if ms._trackpadRightListener then ms._trackpadRightListener:start() end
                else
                    if ms._trackpadLeftListener  then ms._trackpadLeftListener:stop()  end
                    if ms._trackpadRightListener then ms._trackpadRightListener:stop() end
                end
                ms.bind.rebindSystem()
            end
            ms.bind.rebindSystem = function()
                if ms._systemBindHandles then
                    for _, h in pairs(ms._systemBindHandles) do
                        if h and h.delete then h:delete() end
                    end
                end
                ms._systemBindHandles = {}

                for _, id in ipairs(ms.registry._defList) do
                    local def = ms.registry._defs[id]
                    if not def or not def.system then goto sysContinue end
                    local enabled = ms.binds[id]
                    if enabled == nil then enabled = def.enabled end
                    if not enabled then goto sysContinue end
                    local c = ms.effectiveBind(id)
                    if not c then goto sysContinue end
                    local fn = ms.bind._wires[id]
                    if not fn then goto sysContinue end
                    print("rebindSystem: registering " .. id .. " as system bind")
                    if c.type == "key" then
                        local tap = ms._makeKeyWatcher(c.mods, c.key, function()
                            if not ms._robloxActive and not ms._isSafeZone() then return end
                            local co = coroutine.create(fn)
                            local ok, err = coroutine.resume(co)
                            if not ok then print("ms.systemBind error: " .. tostring(err)) end
                        end)
                        if tap then ms._systemBindHandles[id] = tap; tap:start() end
                    elseif c.type == "mouse" then
                        ms._systemBindHandles[id] = ms.mouse(c.button, false, function()
                            if not ms._robloxActive and not ms._isSafeZone() then return end
                            local co = coroutine.create(fn)
                            local ok, err = coroutine.resume(co)
                            if not ok then print("ms.systemBind error: " .. tostring(err)) end
                        end, true)
                    elseif c.type == "scroll" then
                        ms._systemBindHandles[id] = ms.scrollBind(c.direction, function()
                            if not ms._robloxActive and not ms._isSafeZone() then return end
                            local co = coroutine.create(fn)
                            local ok, err = coroutine.resume(co)
                            if not ok then print("ms.systemBind error: " .. tostring(err)) end
                        end)
                    elseif c.type == "gamepad" then
                        ms._systemBindHandles[id] = ms.gamepadBind(c.button, function()
                            if not ms._robloxActive and not ms._isSafeZone() then return end
                            local co = coroutine.create(fn)
                            local ok, err = coroutine.resume(co)
                            if not ok then print("ms.systemBind error: " .. tostring(err)) end
                        end)
                    end
                    ::sysContinue::
                end
                ms.systemBinds.rebind()
            end

            ms.bind.siblingConflict = function(id, c)
                local def = ms.registry._defs[id]
                if not def or def.default or not c then return nil end
                local function key(cfg)
                    if not cfg then return nil end
                    if cfg.type == "mouse" then return "mouse:" .. tostring(cfg.button) end
                    if cfg.type == "scroll" then return "scroll:" .. (cfg.direction or "up") end
                    if cfg.type == "gamepad" then return "gamepad:" .. (cfg.button or "?") end
                    local mods = {}; for _, m in ipairs(cfg.mods or {}) do table.insert(mods, m) end
                    table.sort(mods)
                    return "key:" .. table.concat(mods, ",") .. ":" .. (cfg.key or "")
                end
                local ck = key(c)
                if not ck then return nil end
                for _, sibId in ipairs(ms.registry._defList) do
                    if sibId ~= id then
                        local sibDef = ms.registry._defs[sibId]
                        if sibDef and not sibDef.default then
                            local sibEnabled = ms.binds[sibId]
                            if sibEnabled == nil then sibEnabled = sibDef.enabled end
                            if sibEnabled and key(ms.effectiveBind(sibId)) == ck then
                                return sibId
                            end
                        end
                    end
                end
                return nil
            end

            local _tpModMap = {shift=56, ctrl=59, alt=58, cmd=55}

            if not ms._trackpadLeftListener then
                local leftPhysicallyHeld = false
                local leftActive = false
                ms._trackpadLeftListener = hs.eventtap.new({
                    hs.eventtap.event.types.keyDown,
                    hs.eventtap.event.types.keyUp,
                }, function(event)
                    if BindValidity ~= 1 then return false end
                    local isSynthetic = event:getProperty(hs.eventtap.event.properties.eventSourceUserData) == 999
                    if isSynthetic then return false end
                    local leftHoldCode = _tpModMap[ms.trackpadHoldKeys.left] or hs.keycodes.map[ms.trackpadHoldKeys.left]
                    if not leftHoldCode then return false end
                    local evType  = event:getType()
                    local keyCode = event:getKeyCode()
                    if keyCode ~= leftHoldCode then return false end
                    local isDown = evType == hs.eventtap.event.types.keyDown
                    leftPhysicallyHeld = isDown
                    ms.keytrack[keyCode] = isDown
                    if isDown and not leftActive then
                        leftActive = true
                        local co = coroutine.create(function()
                            ms.Mouse(Press, Left, Mouse, 0, 0)
                            while leftPhysicallyHeld and BindValidity == 1 and ms._robloxActive do ms.wait(1) end
                            ms.Mouse(Release, Left, Mouse, 0, 0)
                            ms.wait(50)
                            leftActive = false
                        end)
                        coroutine.resume(co)
                    end
                    return true
                end)
            end

            if not ms._trackpadRightListener then
                local rightPhysicallyHeld = false
                local rightActive = false
                ms._trackpadRightListener = hs.eventtap.new({
                    hs.eventtap.event.types.keyDown,
                    hs.eventtap.event.types.keyUp,
                }, function(event)
                    if BindValidity ~= 1 then return false end
                    local isSynthetic = event:getProperty(hs.eventtap.event.properties.eventSourceUserData) == 999
                    if isSynthetic then return false end
                    local rightHoldCode = _tpModMap[ms.trackpadHoldKeys.right] or hs.keycodes.map[ms.trackpadHoldKeys.right]
                    if not rightHoldCode then return false end
                    local evType  = event:getType()
                    local keyCode = event:getKeyCode()
                    if keyCode ~= rightHoldCode then return false end
                    local isDown = evType == hs.eventtap.event.types.keyDown
                    rightPhysicallyHeld = isDown
                    ms.keytrack[keyCode] = isDown
                    if isDown and not rightActive then
                        rightActive = true
                        local co = coroutine.create(function()
                            ms.Mouse(Press, Right, Mouse, 0, 0)
                            while rightPhysicallyHeld and BindValidity == 1 and ms._robloxActive do ms.wait(1) end
                            ms.Mouse(Release, Right, Mouse, 0, 0)
                            ms.wait(50)
                            rightActive = false
                        end)
                        coroutine.resume(co)
                    end
                    return true
                end)
            end
        -- END 9. Bind System & Settings Panel --

        -- 10. Event Bus (ms.bus) --
            -- Moved to before MsDevTools loads (section 0) so spoons can register handlers.
        -- END 10. Event Bus (ms.bus) --

        -- 11. Documentation Accessor (ms.docs) --
            do
                local _docsCache = nil  -- { [sectionName] = sectionText, ... }
                local _docsPath = os.getenv("HOME") .. "/.hammerspoon/data/DOCS_MAC.md"

                local function _parseDocs()
                    if _docsCache then return _docsCache end
                    _docsCache = {}
                    local f = io.open(_docsPath, "r")
                    if not f then
                        print("ms.docs: cannot open " .. _docsPath)
                        return _docsCache
                    end
                    local src = f:read("*all")
                    f:close()
                    local currentName = nil
                    local currentBody = {}
                    for line in src:gmatch("([^\n]*)\n?") do
                        local h2 = line:match("^##%s+(.+)$")
                        if h2 then
                            if currentName then
                                _docsCache[currentName] = table.concat(currentBody, "\n"):match("^%s*(.-)%s*$")
                            end
                            currentName = h2
                            currentBody = {}
                        elseif currentName then
                            currentBody[#currentBody + 1] = line
                        end
                    end
                    if currentName then
                        _docsCache[currentName] = table.concat(currentBody, "\n"):match("^%s*(.-)%s*$")
                    end
                    return _docsCache
                end

                ms.docs = {}

                ms.docs.get = function(name)
                    assert(type(name) == "string", "ms.docs.get: name must be a string")
                    local cache = _parseDocs()
                    return cache[name] or nil
                end

                ms.docs.reload = function()
                    _docsCache = nil
                    return _parseDocs()
                end

                ms.docs.sections = function()
                    local cache = _parseDocs()
                    local list = {}
                    for k, _ in pairs(cache) do list[#list + 1] = k end
                    table.sort(list)
                    return list
                end
            end
        -- END 11. Documentation Accessor (ms.docs) --

        -- 12. Shell Infrastructure (ms.shell) --
            package.loaded["lib.ms_shell"] = nil
            require("lib.ms_shell")(ms)
        -- END 12. Shell Infrastructure (ms.shell) --

        -- 12a. Shell Bus Listeners --
            do
                if ms.bus then
                    ms.bus.on("ui:_shell:navigate", function(data)
                        if data and data.panel then
                            ms.shell.setActivePanel(data.panel)
                        end
                    end)
                    ms.bus.on("ui:_shell:popOut", function(data)
                        if data and data.panel then
                            pcall(function() ms.shell.popOut(data.panel) end)
                        end
                    end)
                    -- Panel close: hide the shell when any panel sends {action:"close"}
                    ms.bus.on("ui:*:close", function()
                        pcall(function() ms.shell.hide() end)
                    end)
                    -- Clipboard: write text to system clipboard
                    ms.bus.on("ui:*:clipboard", function(_, body)
                        if body and body.text then
                            pcall(function() hs.pasteboard.setContents(body.text) end)
                        end
                    end)
                end
            end
        -- END 12a --

        -- 13. Visual Macro Compiler (ms.compiler) --
            package.loaded["lib.ms_compiler"] = nil
            require("lib.ms_compiler")(ms)
        -- END 13. Visual Macro Compiler --

        -- 13a. Macro Lab Shell ↔ Compiler bridge --
            do
                local function _macroShellEval(js)
                    if ms.shell and ms.shell.eval then
                        ms.shell.eval(js)
                    end
                end

                if ms.bus then
                    ms.bus.on("ui:macros:listMacros", function(body)
                        local ids = ms.compiler.list()
                        local json = hs.json.encode(ids)
                        _macroShellEval("if(window.macroLab)macroLab.setMacroList(" .. json .. ")")
                    end)

                    ms.bus.on("ui:macros:getMacro", function(body)
                        if not body or not body.id then return end
                        local def = ms.compiler.get(body.id)
                        if def then
                            local json = hs.json.encode(def)
                            _macroShellEval("if(window.macroLab)macroLab.setMacroDef(" .. json .. ")")
                        end
                    end)

                    ms.bus.on("ui:macros:saveMacro", function(body)
                        if not body or not body.id or not body.def then return end
                        local ok, err = pcall(ms.compiler.write, body.id, body.def)
                        if ok then
                            _macroShellEval("shellDispatch('macros','macroSaved',{})")
                        else
                            print("ms.compiler.saveMacro error: " .. tostring(err))
                        end
                    end)

                    ms.bus.on("ui:macros:deleteMacro", function(body)
                        if not body or not body.id then return end
                        local ok, err = pcall(ms.compiler.delete, body.id)
                        if ok then
                            _macroShellEval("shellDispatch('macros','macroSaved',{})")
                        else
                            print("ms.compiler.deleteMacro error: " .. tostring(err))
                        end
                    end)
                end
            end
        -- END 13a. Macro Lab Shell ↔ Compiler bridge --

        -- 14. Safety Nets --
            do
                local macrosPath = os.getenv("HOME") .. "/.hammerspoon/ms_macros.lua"

                local frozenMs = setmetatable({}, {
                    __index    = function(t, k)
                        if k == "integrity" or k == "dev" or k == "showGuardian" or k == "_systemActions"
                       or k == "bus" or k == "docs" or k == "shell" or k == "compiler" then
                            error("ms_macros.lua: ms." .. k .. " is not accessible from macros.", 2)
                        end
                        if k == "key" then
                            return function(mods, key, swallow, pressFn, releaseFn)
                                return ms.key(mods, key, swallow, pressFn, releaseFn, false)
                            end
                        elseif k == "mouse" then
                            return function(button, swallow, clickFn, hidinject)
                                return ms.mouse(button, swallow, clickFn, hidinject, false)
                            end
                        elseif k == "bind" then
                            return setmetatable({}, {
                                __index = function(_, bk)
                                    if bk == "define" then
                                        return function(id, a, b)
                                            local opts = type(a) == "table" and a or (type(b) == "table" and b or {})
                                            opts.system = false
                                            return ms.bind.define(id, a, b)
                                        end
                                    end
                                    return ms.bind[bk]
                                end,
                            })
                        elseif k == "fn" then
                            -- Wrap ms.fn: expose define with user-group guardrail
                            local origFn = ms.fn
                            return setmetatable({}, {
                                __call = function(_, fn, label)
                                    return origFn(fn, label)
                                end,
                                __index = function(_, bk)
                                    if bk == "define" then
                                        return function(id, fn, opts)
                                            opts = opts or {}
                                            opts.group = "user"  -- force user group in sandbox
                                            return ms.fn.define(id, fn, opts)
                                        end
                                    end
                                    return ms.fn[bk]
                                end,
                            })
                        end
                        if k == "alert" then
                            return setmetatable({}, {
                                __call = function(_, msg, duration, noDefaultSound)
                                    return ms.alert(msg, duration, noDefaultSound, { source = "macro" })
                                end,
                                __index = function(_, bk)
                                    if bk == "dismissById" then
                                        return ms.alert[bk]
                                    end
                                    return nil
                                end,
                            })
                        end
                        return ms[k]
                    end,
                    __newindex = function(t, k, v)
                        if k == "macroMeta" then
                            rawset(ms, k, v)
                        else
                            error("ms_macros.lua: unauthorized write to ms." .. tostring(k)
                                .. "  —  only ms.macroMeta and ms.bind.define are permitted.", 2)
                        end
                    end,
                })

                local BLOCKED = {
                    hs=true, require=true, os=true, io=true,
                    _G=true, load=true, loadfile=true, loadstring=true,
                    dofile=true, rawget=true, rawset=true,
                    debug=true, package=true, collectgarbage=true,
                    setfenv=true, getfenv=true,
                    setmetatable=true, getmetatable=true,
                    roblox=true,               -- hs.application handle; :activate() risk
                    __ms_appWatcher=true,        -- hs.eventtap: :stop() kills app monitoring
                    _integrityPollTimer=true,    -- hs.timer: :stop() disables integrity poll
                    _initTimer=true,             -- hs.timer: deferred init timer
                }

                local sandbox = {
                    ms        = frozenMs,
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
                    sub       = ms.sub,       -- sub-function wrapper with call stack tracking
                    Move        = Move,        Click       = Click,       DoubleClick  = DoubleClick,
                    TripleClick = TripleClick, Drag        = Drag,        Press        = Press,
                    Release     = Release,
                    Left        = Left,        Right       = Right,       Center       = Center,
                    Button4     = Button4,     Button5     = Button5,
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
                        local v = rawget(_G, k)
                        local vt = type(v)
                        if vt == "string" or vt == "number" or vt == "boolean" or v == nil then
                            return v
                        end
                        error("ms_macros.lua: access to '" .. tostring(k)
                            .. "' is not permitted (non-primitive globals are not accessible from macros).", 2)
                    end,
                    __newindex = function(t, k, v)
                        error("ms_macros.lua: cannot write global '" .. tostring(k)
                            .. "' — use 'local' for all variables.", 2)
                    end,
                })

                ms._macroSandbox = sandbox

                -- Preprocessor: wrap local function definitions with sub() for instrumentation
                -- Transforms: local X = function(...) → local X = sub("X", function(...)
                -- Finds matching end and adds closing )
                ms._wrapMacroFunctions = function(src)
                    -- Split source into lines
                    local srcLines = {}
                    for line in (src .. "\n"):gmatch("([^\n]*)\n") do
                        srcLines[#srcLines + 1] = line
                    end

                    local out = {}
                    local i = 1
                    while i <= #srcLines do
                        local line = srcLines[i]
                        -- Match: local NAME = function(
                        local indent, name, rest = line:match("^(%s*)local%s+(%w+)%s*=%s*(function%s*%(.*)$")
                        if name and rest then
                            out[#out + 1] = indent .. 'local ' .. name .. ' = sub("' .. name .. '", ' .. rest
                            -- Track depth to find matching end
                            local depth = 1
                            i = i + 1
                            while i <= #srcLines and depth > 0 do
                                local l = srcLines[i]
                                -- Count block-opening keywords
                                for kw in l:gmatch("(%w+)") do
                                    if kw == "function" or kw == "if" or kw == "for"
                                    or kw == "while" or kw == "repeat" then
                                        depth = depth + 1
                                    end
                                end
                                -- Count closing keywords (skip strings)
                                local stripped = l:gsub('"[^"]*"', '""'):gsub("'[^']*'", "''")
                                for kw in stripped:gmatch("(%w+)") do
                                    if kw == "end" then
                                        depth = depth - 1
                                    end
                                end
                                if depth > 0 then
                                    out[#out + 1] = l
                                else
                                    -- Matching end — add closing )
                                    local endIndent = l:match("^(%s*)") or ""
                                    out[#out + 1] = endIndent .. "end)"
                                end
                                i = i + 1
                            end
                        else
                            out[#out + 1] = line
                            i = i + 1
                        end
                    end
                    return table.concat(out, "\n")
                end

                local rawSrc
                do
                    local af = io.open(macrosPath, "r")
                    if not af then
                        error("ms_macros.lua: cannot open file for security audit: " .. macrosPath)
                    end
                    rawSrc = af:read("*all"); af:close()
                    local auditErrs = ms.auditMacros(rawSrc)
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

                local chunk, loadErr
                if _VERSION and _VERSION >= "Lua 5.2" or not setfenv then
                    chunk, loadErr = load(rawSrc, "@ms_macros.lua", "bt", sandbox)
                else
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

                if not ms.macroMeta then
                    print("Warning: ms_macros.lua did not set ms.macroMeta.")
                    hs.timer.doAfter(0.5, function()
                        ms.alert("Warning: ms_macros.lua did not declare ms.macroMeta.", 6)
                    end)
                end
                ms.loading.pushMeta()
                if not next(ms.registry._defs) then
                    error("ms_macros.lua: no ms.bind.define calls found — file may be malformed.")
                end
            end

            ms.macroDefaults = {
                trackpadMode = false,
                socdEnabled  = false,
                socdMode     = "lastWins",
                macros = {
                    spawnAlt = { enabled = false },
                },
            }
        -- END 14. Safety Nets --
    -- END Hammerspoon mudscript Utility Library --

    -- Startup Executions --
        ms._systemActions = {}
        if ms._userSettingIndex["showTamperWarning"] then
            ms._systemActions["showTamperWarning"] = function()
                ms.showGuardian()
            end
            ms._systemActions["showIntegrityError"] = function()
                ms.showGuardian()
            end
        end

        for _, id in ipairs(ms.registry._defList) do
            local def = ms.registry._defs[id]
            if def and not def.default and ms.binds[id] == nil then
                ms.binds[id] = def.enabled
            end
        end
        ms._devArchiveLimit   = 15     -- overridden by loadSettings() if previously saved
        ms._loadComplete   = false  -- gates macro activation; set to true by _announceLoad
        _G._bootChoreographyStarted = false  -- reset guard for loading screen ready handshake
        ms.loadSettings()            -- load first so importedSounds/soundAssign are available
        -- If custom themes disabled, reset loading sound presets to defaults
        if ms._customThemeDisabled then
            local defaultAssigns = {
                themeLoaded = "d_ThemeLoaded",
                load        = "d_LoadEnd",
                launch      = "d_Launch",
            }
            for sid, def in pairs(defaultAssigns) do
                ms.soundAssign[sid] = def
            end
        end
        ms._soundsDirty = true       -- force re-scan after settings (may have new importedSounds)
        ms._discoverSounds()
        -- Theme loading deferred to after loading screen appears (debounce)

        -- Sync Roblox cache cleaner LaunchAgent with setting
        do
            local home = os.getenv("HOME")
            local plistDst = home .. "/Library/LaunchAgents/com.mudscript.cache-cleaner.plist"
            local agentExists = hs.fs.attributes(plistDst) ~= nil

            -- Migration: if setting never saved but agent already installed, preserve it
            if ms._cacheCleanerEnabled == nil then
                ms._cacheCleanerEnabled = agentExists
                if agentExists then pcall(ms.saveSettings) end
            end

            if ms._cacheCleanerEnabled and not agentExists then
                -- Setting says ON but agent missing — install it
                local plistSrc = home .. "/.hammerspoon/bin/com.mudscript.cache-cleaner.plist"
                local scriptSrc = home .. "/.hammerspoon/bin/clean_roblox_cache.sh"
                if hs.fs.attributes(plistSrc) and hs.fs.attributes(scriptSrc) then
                    local f = io.open(plistSrc, "r")
                    if f then
                        local content = f:read("*all"); f:close()
                        content = content:gsub("%%AGENT_PATH%%", scriptSrc)
                        local g = io.open(plistDst, "w")
                        if g then g:write(content); g:close() end
                        os.execute("chmod 755 '" .. scriptSrc .. "'")
                        os.execute("launchctl load '" .. plistDst .. "' 2>/dev/null")
                    end
                end
            elseif not ms._cacheCleanerEnabled and agentExists then
                -- Setting says OFF but agent present — uninstall it
                os.execute("launchctl unload '" .. plistDst .. "' 2>/dev/null")
                os.remove(plistDst)
            end
        end
        os.remove(os.getenv("HOME") .. "/.hammerspoon/data/.ms_update_pending")
        ms.bind._registerSystemBinds()
        ms.bind.rebind()
        ms.socdApply()
        BindValidity = 0  -- block macros during loading; _announceLoad re-enables when toasts fire
        ms._startupSoundDone = false  -- suppresses all non-load sounds until _announceLoad runs

        -- Loading Screen — Announce & Boot Completion --
            ms.loading.create()

            _announceLoad = function()
                if _loadAnnounced then return end
                _loadAnnounced = true
                pcall(function() ms.playSlot("load") end)
                _G._loadTimers.announceBody = hs.timer.doAfter(0.4, function()
                    ms._startupSoundDone = true
                    pcall(function() ms.playSlot("launch") end)
                    ms.alert("Macros loaded. Press \xe2\x8c\xa5 and P to open settings.", 3, true, { priority = "low" })
                    _G._loadTimers.announce3 = hs.timer.doAfter(3, function()
                        ms.alert("Hammerspoon mudscript Utility Library\nBy: mudbourn \xe2\x80\x94 https://mudbourn.info", 3, true, { priority = "low" })
                    end)
                    _G._loadTimers.announce6 = hs.timer.doAfter(6, function()
                        if ms.macroMeta then
                            local msg = "\"" .. (ms.macroMeta.name or "Unknown Macro Pack") .. "\"\n"
                            if ms.macroMeta.author  then msg = msg .. "By: " .. ms.macroMeta.author end
                            if ms.macroMeta.website then msg = msg .. " \xe2\x80\x94 " .. ms.macroMeta.website end
                            ms.alert(msg, 3, true, { priority = "low" })
                        end
                    end)
                    ms.loading.applyTheme()
                    ms._loadComplete = true
                    ms.dev.log({ type = "system", event = "startup_complete" })
                    -- Apply Octane Mode if persisted as on
                    if ms._octaneMode and ms.octane and ms.octane._apply then
                        pcall(ms.octane._apply)
                    end
                    if ms._robloxActive then ms.setMacros(1, true) end
                    _G._loadTimers.integrityWarn = hs.timer.doAfter(10, function()
                        if _needsIntegrityWarning then
                            ms.alert("\u{26a0} Integrity Error\nNo trusted manifest on record.\nSettings \u{2192} Developer \u{2192} Trust Current Version.", 10)
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

            _G._timers = {}
            -- Delay loading sequence until boot animation completes (~2.9s)
            _G._timers.animGate = hs.timer.doAfter(2.9, function()
            ms.loading.update(20, "Initializing\u{2026}")
            -- Timing for loading sequence
            local t1 = 0.3
            local t2 = 0.5
            local t3 = 0.8
            local t4 = 1.3
            local t5 = 2.0
            local t6 = 2.6
            local t7 = 3.2
            local t8 = 3.8
            local t9 = 4.2
            local t10 = 4.6
            _G._timers[1] = hs.timer.doAfter(0, function()
                print("[startup] t=0: prebuild")
                pcall(function() ms.ui.prebuild() end)
                pcall(function() ms.ui._precacheHTML() end)
                ms.loading.update(25, "Building UI state cache\u{2026}")
            end)
            _G._timers[2] = hs.timer.doAfter(t1, function()
                print("[startup] t=" .. t1 .. ": prep settings")
                ms.loading.update(32, "Preparing settings panel\u{2026}")
            end)
            _G._timers[3] = hs.timer.doAfter(t2, function()
                print("[startup] t=" .. t2 .. ": prewarm")
                pcall(function() ms.ui.prewarm() end)
                ms.loading.update(40, "Loading settings panel\u{2026}")
            end)
            _G._timers[4] = hs.timer.doAfter(t3, function()
                print("[startup] t=" .. t3 .. ": theme")
                ms.loading.update(48, "Applying theme\u{2026}")
                -- Apply theme in sync with themeLoaded sound
                if ms.loading.isVisible() then
                    local themeJson = hs.json.encode(ms._theme or {})
                    pcall(function() ms.loading.eval("applyTheme(" .. themeJson .. ")") end)
                end
                pcall(function() ms.playSlot("themeLoaded") end)
                -- Show profile name, creator, and version when theme loads (macros loaded by now)
                if ms.loading.isVisible() then
                    -- Re-push metadata now that ms_macros.lua has loaded
                    if ms.macroMeta and ms.macroMeta.name then
                        pcall(function() ms.loading.eval("setProfileName('" .. ms.macroMeta.name:gsub("'", "\\'") .. "')") end)
                    end
                    if ms.macroMeta and ms.macroMeta.author and ms.macroMeta.author ~= "" then
                        pcall(function() ms.loading.eval("setCreator('" .. ms.macroMeta.author:gsub("'", "\\'") .. "')") end)
                    end
                    -- Push version from MANIFEST.json (same source as MsUI.spoon)
                    local _ver = (function()
                        local p = os.getenv("HOME") .. "/.hammerspoon/MANIFEST.json"
                        local f = io.open(p, "r")
                        if not f then return nil end
                        local ok, m = pcall(hs.json.decode, f:read("*all")); f:close()
                        local base = (ok and m and m.version) or nil
                        if not base then return nil end
                        if ms._updateChannel == "testing" then
                            local maj, min, pat = base:match("^(%d+)%.(%d+)%.(%d+)$")
                            if maj and min and pat then
                                local nextVer = maj .. "." .. min .. "." .. tostring(tonumber(pat) + 1)
                                local buildPath = os.getenv("HOME") .. "/.hammerspoon/data/.ms_build_num"
                                local bf = io.open(buildPath, "r")
                                local buildNum = 0
                                if bf then buildNum = tonumber(bf:read("*all")) or 0; bf:close() end
                                return nextVer .. "-pre." .. tostring(buildNum)
                            end
                        end
                        return base
                    end)()
                    if _ver then
                        pcall(function() ms.loading.eval("setVersion('" .. _ver:gsub("'", "\\'") .. "')") end)
                    end
                    pcall(function() ms.loading.eval("showProfile()") end)
                    pcall(function() ms.loading.eval("showCreator()") end)
                    pcall(function() ms.loading.eval("showVersion()") end)
                end
            end)
            _G._timers[5] = hs.timer.doAfter(t4, function()
                print("[startup] t=" .. t4 .. ": integrity seed")
                ms.loading.update(55, "Seeding integrity hash\u{2026}")
            end)
            _G._timers[6] = hs.timer.doAfter(t5, function()
                print("[startup] t=" .. t5 .. ": console")
                ms.loading.update(62, "Loading console\u{2026}")
                _G._timers[60] = hs.timer.doAfter(0, function()
                    pcall(function() ms.dev.prewarmStep("console") end)
                end)
            end)
            _G._timers[7] = hs.timer.doAfter(t6, function()
                print("[startup] t=" .. t6 .. ": watcher")
                ms.loading.update(72, "Loading macro monitor\u{2026}")
                _G._timers[70] = hs.timer.doAfter(0, function()
                    pcall(function() ms.dev.prewarmStep("watcher") end)
                end)
            end)
            _G._timers[8] = hs.timer.doAfter(t7, function()
                print("[startup] t=" .. t7 .. ": keys")
                ms.loading.update(82, "Loading input monitor\u{2026}")
                _G._timers[80] = hs.timer.doAfter(0, function()
                    pcall(function() ms.dev.prewarmStep("keys") end)
                end)
            end)
            _G._timers[9] = hs.timer.doAfter(t8, function()
                print("[startup] t=" .. t8 .. ": window")
                ms.loading.update(90, "Loading window monitor\u{2026}")
                _G._timers[90] = hs.timer.doAfter(0, function()
                    pcall(function() ms.dev.prewarmStep("window") end)
                end)
            end)
            _G._timers[10] = hs.timer.doAfter(t9, function()
                print("[startup] t=" .. t9 .. ": finalize")
                if not ms.loading.isFadingOut() then ms.loading.update(96, "Finalizing\u{2026}") end
            end)
            _G._timers[11] = hs.timer.doAfter(t10, function()
                print("[startup] t=" .. t10 .. ": fade start")
                if not ms.loading.isFadingOut() then
                    ms.loading.update(100, "Ready.")
                    _G._timers[12] = hs.timer.doAfter(0.8, function()
                        print("[startup] fade out")
                        pcall(function() ms.loading.fadeOut(_announceLoad) end)
                    end)
                end
            end)
            _G._timers.guard = hs.timer.doAfter(8, function()
                print("[startup] t=8: GUARD fired")
                pcall(function()
                    if ms.loading.isVisible() and not ms.loading.isFadingOut() then ms.loading.fadeOut(_announceLoad) end
                end)
                ms._startupSoundDone = true
                print("[startup] t=8: startupSoundDone set to", ms._startupSoundDone)
            end)
            _G._timers.integrity = hs.timer.doAfter(3, function()
                print("[startup] t=3: integrity check")
                pcall(function()
                    if ms.integrity.check() ~= "uninitialized" then return end
                    -- First install: try to seed from MANIFEST.json
                    local _mPath = os.getenv("HOME") .. "/.hammerspoon/MANIFEST.json"
                    local _mf    = io.open(_mPath, "r")
                    if _mf then
                        local _ok, _manifest = pcall(hs.json.decode, _mf:read("*all")); _mf:close()
                        if _ok and type(_manifest) == "table"
                            and type(_manifest.sha256) == "string"
                            and #_manifest.sha256 == 64 then
                            local _cur = ms.integrity.hashFile(corePath)
                            if _cur and _cur:lower() == _manifest.sha256:lower() then
                                -- MANIFEST matches — seal all tracked files
                                ms.integrity.trustCurrent()
                                return
                            end
                        end
                    end
                    _needsIntegrityWarning = true
                end)
            end)


            if roblox then roblox:activate() end

            notice = 0
            loadfinish = 0

            _G._loadfinishTimer = hs.timer.doAfter(3000 / 1000, function()
                _G._loadfinishTimer = nil
                loadfinish = 1
            end)

            _G._integrityPollTimer = hs.timer.doEvery(180, function()
                if loadfinish ~= 1 then return end  -- skip startup grace period
                if ms._updateInProgress then return end  -- skip during updates
                ms.integrity.check()
            end)

            if notice ~= 1 then
                _G._announceTimer = hs.timer.doAfter(7.0, function()
                    _G._announceTimer = nil
                    pcall(function() _announceLoad() end)
                    -- Hard guarantee: if _announceLoad failed or returned early,
                    -- ensure startup flags are set so sounds/macros aren't blocked.
                    _G._announceGuardTimer = hs.timer.doAfter(1, function()
                        _G._announceGuardTimer = nil
                        ms._startupSoundDone = true
                        if not ms._loadComplete then
                            ms._loadComplete = true
                            if ms._robloxActive then pcall(function() ms.setMacros(1, true) end) end
                        end
                    end)
                end)
                notice = 1
            end
            end) -- end animGate
        -- END Loading Screen — Announce & Boot Completion --
    -- END Startup Executions --
-- END Core System --
