-- Core System ---- PLEASE EDIT CAREFULLY --
    -- Hammerspoon mudscript Utility Library --
        -- 0. Bootstrap & Spoons --
            ms = {}
            if _G.__ms_appWatcher then pcall(function() _G.__ms_appWatcher:stop() end) end
            if _G.__ms_core_running then return end
            _G.__ms_core_running = true

            -- Loading Screen locals (webview created after spoon loading) --
                local _lWebView, _lFadingOut, _lFadeTimer
                local _lFadeOut, _loadAnnounced, _announceLoad
                local _needsIntegrityWarning = false
                local _lMsgBuffer = {}
                local _lUpdate = function(pct, msg)
                    _lMsgBuffer[#_lMsgBuffer + 1] = { pct = pct, msg = msg }
                end
            -- END Loading Screen locals --

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
                _lUpdate(3, "Configuring Guardian\u{2026}")
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
                _lUpdate(6, "Configuring Dev Tools\u{2026}")
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
                    }

                    print("MsDevTools: running without dev panels (spoon not loaded)")
                end
            -- END MsDevTools (logging & dev panels) --

            -- MsAlert (toast notifications) --
                _lUpdate(9, "Configuring Alerts\u{2026}")
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
            -- END MsAlert (toast notifications) --

            -- MsCamera removed (ms.cam uses CGEvent directly) --

            -- MsSettings (settings menu & profiles) --
                _lUpdate(15, "Configuring Settings\u{2026}")
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
                _lUpdate(18, "Configuring UI\u{2026}")
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
                ms._themeDefaults = {
                    bg       = "#0e0e0e",
                    surface  = "#1a1a1a",
                    surface2 = "#252525",
                    hover    = "#333333",
                    accent   = "#cccccc",
                    accentHi = "#e8e8e8",
                    success  = "#888888",
                    dangerBg = "#1a1616",
                    danger   = "#d8d8d8",
                    warning  = "#aaaaaa",
                    text     = "#d8d8d8",
                    radius       = 4,
                    windowRadius = 4,
                    font         = "Arial",
                    fadeMs       = 100,
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
                    if ms.dev and ms.dev._onKeyEvent then
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
                    if not isRepeat and ms.dev then
                        pcall(ms.dev._onKeyEvent, keyCode, hs.keycodes.map[keyCode], true)
                    end
                    if not isRepeat and ms._keyBindings then
                        ms._currentFlags = flags
                        for _, binding in pairs(ms._keyBindings) do
                            if binding and binding.keyCode == keyCode then
                                local modsMatch = true
                                if binding.mods.cmd   and not flags.cmd   then modsMatch = false end
                                if binding.mods.alt   and not flags.alt   then modsMatch = false end
                                if binding.mods.ctrl  and not flags.ctrl  then modsMatch = false end
                                if binding.mods.shift and not flags.shift then modsMatch = false end
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
                    end
                elseif type == hs.eventtap.event.types.keyUp then
                    ms.keytrack[keyCode] = false
                    if ms.dev then
                        pcall(ms.dev._onKeyEvent, keyCode, hs.keycodes.map[keyCode], false)
                    end
                    if ms._keyBindings then
                        for _, binding in pairs(ms._keyBindings) do
                            if binding and binding.keyCode == keyCode then
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

            -- Key press/release/type accumulator (value-change flushing, like wait/cam)
            local _keyAccum      = 0
            local _keyMsg        = nil
            local _keyFlushLabel = nil
            local _keyFlush = function()
                if _keyAccum > 0 then
                    local msg = _keyMsg
                    if _keyAccum > 1 then msg = msg .. " ×" .. _keyAccum end
                    if ms.dev and spoon.MsDevTools then
                        spoon.MsDevTools:macroLog(msg, _keyFlushLabel)
                        if ms.dev._watcherPanel then
                            spoon.MsDevTools:watcherStep(msg, _keyFlushLabel)
                        end
                    end
                    _keyAccum      = 0
                    _keyMsg        = nil
                    _keyFlushLabel = nil
                end
            end
            -- END Key accumulator --

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
                            if _keyAccum > 0 and msg == _keyMsg then
                                _keyAccum = _keyAccum + 1
                            else
                                _keyFlush()
                                _keyAccum = 1
                                _keyMsg   = msg
                            end
                            if not _keyFlushLabel then _keyFlushLabel = ms._getCallChain() end
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
                        if _keyAccum > 0 and msg == _keyMsg then
                            _keyAccum = _keyAccum + 1
                        else
                            _keyFlush()
                            _keyAccum = 1
                            _keyMsg   = msg
                        end
                        if not _keyFlushLabel then _keyFlushLabel = ms._getCallChain() end
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
                        if _keyAccum > 0 and msg == _keyMsg then
                            _keyAccum = _keyAccum + 1
                        else
                            _keyFlush()
                            _keyAccum = 1
                            _keyMsg   = msg
                        end
                        if not _keyFlushLabel then _keyFlushLabel = ms._getCallChain() end
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

                    return { delete = function()
                        for i, b in ipairs(ms._keyBindings) do
                            if b == binding then
                                table.remove(ms._keyBindings, i)
                                break
                            end
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

                        if ms.dev and ms.dev._onMouseEvent then
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
                    local curSens = CUR_CAM_SENS or 1.5
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
                    spoon.MsDevTools:accCamMove(dx, dy)
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
                    local currentSens = CUR_CAM_SENS or 1.5
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
                        if not ms.alert.updateById("_state", "Macros enabled!", 3) then
                            ms.alert("Macros enabled!",  3, true, { id = "_state", source = "system" })
                        end
                    else
                        _stateSound = ms.playSlot("disabled")
                        if not ms.alert.updateById("_state", "Macros disabled.", 3) then
                            ms.alert("Macros disabled.", 3, true, { id = "_state", source = "system" })
                        end
                    end
                end)
            end

            ms.setMacros = function(state, silent)
                if ms.ui and ms.ui.markDirty then ms.ui.markDirty() end
                if state == 1 and BindValidity ~= 1 then
                    BindValidity = 1
                    pcall(function() end)  -- ms.legacycam.enable() opt-in
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
                    pcall(function() end)  -- ms.legacycam.disable() opt-in
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
                        -- ms.legacycam._setupWatcher()  -- opt-in
                        if not ms._loadComplete then return end
                        if fromDialog then
                            BindValidity = 1
                            -- pcall(function() ms.legacycam.enable() end)  -- opt-in
                        else
                            ms.setMacros(1)
                        end
                    else
                        if ms.ui._open and appName == "Hammerspoon" then return end
                        ms._inputOpen    = (appName == "Hammerspoon") and ms._robloxActive
                        ms._robloxActive = false
                        ms.dev.log({ type = "system", event = "target_blur", to = appName })
                        -- Reset camera activation state when Roblox loses focus
                        if ms._camActivated ~= nil then ms._camActivated = false end
                        if BindValidity == 1 then
                            ms.setMacros(0, ms._inputOpen)
                        end
                    end
                elseif ms._targetApp and eventType == hs.application.watcher.launched and appName == ms._targetApp then
                    -- ms.legacycam._setupWatcher()
                end
            end):start()
            _G.__ms_appWatcher = ms._appWatcher  -- survives reload (lives outside the ms table) so next load's stop-guard can find this generation

            _G._initTimer = hs.timer.doAfter(0.3, function()
                local frontApp = hs.application.frontmostApplication()
                if ms._targetApp and frontApp and frontApp:name() == ms._targetApp then
                    ms._robloxActive = true
                    -- ms.legacycam._setupWatcher()
                    -- ms.legacycam.enable()
                end
            end)

            -- System hotkey bindings (configurable via shell)
            ms._hotkeys = {
                panic       = { mods = {"alt"}, key = "F10" },
                quickReload = { mods = {"alt"}, key = "[" },
                fullReload  = { mods = {"alt"}, key = "]" },
                openMenu    = { mods = {"alt"}, key = "p" },
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
                    -- Check no extra mods are held
                    local count = 0
                    for _ in pairs(flags) do count = count + 1 end
                    return count == #mods
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
                        if kc == keyCode and modsMatch(flags) and not _hotkeyDown[id] and not _hotkeyCooldowns[id] then
                            _hotkeyDown[id] = true
                            onDown()
                        end
                        return false  -- never swallow
                    end

                    if type == hs.eventtap.event.types.keyUp then
                        if kc == keyCode then
                            _hotkeyDown[id] = false
                            -- Cooldown: wait 0.15s after key up before allowing re-fire
                            _hotkeyCooldowns[id] = true
                            hs.timer.doAfter(0.15, function()
                                _hotkeyCooldowns[id] = false
                            end)
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
                    if not ms._robloxActive and not ms._isSafeZone() then return end
                    if ms._macroLabEnabled and ms.shell and ms.shell.toggle then
                        ms.shell.toggle()
                    elseif ms.ui and ms.ui.toggle then
                        ms.ui.toggle()
                    end
                end)
                if tap then ms._hotkeyHandles.openMenu = tap; tap:start() end
            end

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
                if opts.sub then
                    assert(ms.registry._defs[opts.sub],
                        "ms.bind.define: parent '" .. tostring(opts.sub) .. "' must be defined before '" .. id .. "'")
                end
                local label, group
                if not opts.sub then
                    if opts.label then
                        label = opts.label
                    else
                        ms.bind._autoCount = ms.bind._autoCount + 1
                        label = "Macro" .. ms.bind._autoCount
                    end
                    group = opts.group or "main"
                else
                    label = opts.label or id
                    group = opts.group
                end
                ms.registry._defs[id] = {
                    label    = label,
                    group    = group,
                    enabled  = (opts.enabled ~= false),
                    cooldown = opts.cooldown or 1000,
                    shared   = opts.shared,
                    sub      = opts.sub,
                    mod      = opts.mod,
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
                ms.bind._wires["__openMenu"] = function()
                    if ms._macroLabEnabled and ms.shell and ms.shell.toggle then
                        ms.shell.toggle()
                    elseif ms.ui and ms.ui.toggle then
                        ms.ui.toggle()
                    end
                end
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
                local current, seen = id, {}
                while true do
                    local d = ms.registry._defs[current]
                    if not d or not d.sub or seen[current] then break end
                    seen[current] = true
                    current = d.sub
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
                    if c.type == "mouse" then return "mouse:" .. tostring(c.button) end
                    if c.type == "scroll" then return "scroll:" .. (c.direction or "up") end
                    if c.type == "gamepad" then return "gamepad:" .. (c.button or "?") end
                    local mods = {}
                    for _, m in ipairs(c.mods or {}) do table.insert(mods, m) end
                    table.sort(mods)
                    return "key:" .. table.concat(mods, ",") .. ":" .. (c.key or "")
                end

                local conflicted = {}

                local rootUsed = {}
                for _, id in ipairs(ms.registry._defList) do
                    local def = ms.registry._defs[id]
                    if not def or def.sub then goto c1 end
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
                                    .. "\" share the same input.\nBoth disabled — resolve via Settings › Keybinds.", 10)
                            end)
                        else
                            rootUsed[key] = id
                        end
                    end
                    ::c1::
                end

                local modUsed = {}
                for _, id in ipairs(ms.registry._defList) do
                    local def = ms.registry._defs[id]
                    if not def or not def.sub then goto c2 end
                    local mod = ms.getMod(id)
                    if not mod then goto c2 end
                    local parent = def.sub
                    modUsed[parent] = modUsed[parent] or {}
                    if modUsed[parent][mod] then
                        local other = modUsed[parent][mod]
                        conflicted[id] = true; conflicted[other] = true
                        local l1 = ms.registry._defs[id].label
                        local l2 = ms.registry._defs[other].label
                        local lp = (ms.registry._defs[parent] and ms.registry._defs[parent].label) or parent
                        hs.timer.doAfter(0, function()
                            ms.alert("Modifier conflict: \"" .. l1 .. "\" and \"" .. l2
                                .. "\" share modifier \"" .. mod .. "\" under " .. lp
                                .. ".\nBoth disabled — resolve via Settings › Modifiers.", 10)
                        end)
                    else
                        modUsed[parent][mod] = id
                    end
                    ::c2::
                end

                for _, id in ipairs(ms.registry._defList) do
                    if conflicted[id] then goto continue end
                    local fn  = ms.bind._wires[id]
                    local def = ms.registry._defs[id]
                    if not fn or not def then goto continue end

                    local group    = ms.bind.group(id)
                    local cooldown = ms.cooldowns[id] or def.cooldown or 1000

                    if def.sub then
                        if ms.independentBindsEnabled and ms.subBinds and ms.subBinds[id] then
                            local c = ms.subBinds[id]
                            local function firedFn()
                                if ms.running[group] then return end
                                ms.running[group] = hs.timer.doAfter(cooldown / 1000, function()
                                    ms.running[group] = nil
                                end)
                                ms._activeSub = id
                                if ms.dev then
                                    local _pd = ms.registry._defs[def.sub]
                                    local _trig = (function()
                                        if c.type == "mouse" then return "M" .. c.button end
                                        if c.type == "scroll" then return "S:" .. (c.direction or "?") end
                                        if c.type == "gamepad" then return "G:" .. (c.button or "?") end
                                        local _p = {}
                                        for _, m in ipairs(c.mods or {}) do _p[#_p+1] = m end
                                        _p[#_p+1] = c.key or ""; return table.concat(_p, "+")
                                    end)()
                                    pcall(ms.dev._onMacroFire, id, def.label, def.sub, _pd and _pd.label, _trig)
                                end
                                ms._pendingLabel = def.label
                                fn()
                            end
                            if c.type == "mouse" then
                                ms.mouse(c.button, false, firedFn)
                            elseif c.type == "key" then
                                ms.bindHandles[id] = ms.key(c.mods, c.key, false, firedFn)
                            elseif c.type == "scroll" then
                                ms.bindHandles[id] = ms.scrollBind(c.direction, firedFn)
                            elseif c.type == "gamepad" then
                                ms.bindHandles[id] = ms.gamepadBind(c.button, firedFn)
                            end
                        end
                    else
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
                            ms._activeSub = nil  -- clear sub-item state before root bind fires
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
                        if c.type == "mouse" then
                            ms.mouse(c.button, false, firedFn)
                        elseif c.type == "key" then
                            ms.bindHandles[id] = ms.key(c.mods, c.key, false, firedFn)
                        elseif c.type == "scroll" then
                            ms.bindHandles[id] = ms.scrollBind(c.direction, firedFn)
                        elseif c.type == "gamepad" then
                            ms.bindHandles[id] = ms.gamepadBind(c.button, firedFn)
                        end
                    end

                    ::continue::
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
                if not def or def.sub or not c then return nil end
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
                        if sibDef and not sibDef.sub then
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

            ms.bind.siblingModConflict = function(id, modKey)
                local def = ms.registry._defs[id]
                if not def or not def.sub or not modKey then return nil end
                for _, sibId in ipairs(ms.registry._defList) do
                    if sibId ~= id then
                        local sibDef = ms.registry._defs[sibId]
                        if sibDef and sibDef.sub == def.sub and ms.getMod(sibId) == modKey then
                            return sibId
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

            ms.getMod = function(id)
                if ms.modConfig[id] ~= nil then return ms.modConfig[id] end
                local def = ms.registry._defs[id]
                return def and def.mod or nil
            end

            ms.modHeld = function(id)
                local key = ms.getMod(id)
                if not key then
                    if ms.dev and ms.dev.trace then
                        ms.dev.step("modHeld(" .. tostring(id) .. ") → false")
                    end
                    return false
                end
                local result = ms.keystate(key)
                if ms.dev and ms.dev.trace then
                    ms.dev.step("modHeld(" .. tostring(id) .. ") → " .. tostring(result))
                end
                return result
            end

            ms.isSub = function(id)
                if ms._activeSub == id or (not ms._activeSub and ms.modHeld(id)) then
                    ms._activeSub = nil
                    if ms.dev then
                        local def = ms.registry._defs[id]
                        if def and def.sub then
                            local pd  = ms.registry._defs[def.sub]
                            pcall(ms.dev._onMacroFire, id, def.label,
                                def.sub, pd and pd.label, ms.getMod(id) or "")
                        end
                        if ms.dev.trace then
                            ms.dev.step("isSub(" .. tostring(id) .. ") → true")
                        end
                    end
                    return true
                end
                if ms.dev and ms.dev.trace then
                    ms.dev.step("isSub(" .. tostring(id) .. ") → false")
                end
                return false
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
            do
                local _shellView     = nil
                local _shellChannel  = nil
                local _shellReady    = false
                local _shellEvalQ    = {}
                local _shellFadeTimer = nil

                ms.shell = {}

                ms.shell.eval = function(js)
                    if type(js) ~= "string" then return end
                    if _shellView and _shellReady then
                        local ok, err = pcall(function() _shellView:evaluateJavaScript(js) end)
                        if not ok then print("[shell] eval failed: " .. tostring(err):sub(1, 200)) end
                    else
                        _shellEvalQ[#_shellEvalQ + 1] = js
                    end
                end

                ms.shell.isReady = function() return _shellReady end
                ms.shell.webview = function() return _shellView end

                ms.shell.init = function()
                    if _shellView then return end
                    require("hs.webview")
                    require("hs.webview.usercontent")

                    _shellChannel = hs.webview.usercontent.new("msShell")
                    _shellChannel:setCallback(function(message)
                        local raw = tostring(message.body or "")
                        local ok, data = pcall(hs.json.decode, raw)
                        if not ok or type(data) ~= "table" then
                            return
                        end
                        local panel  = data.panel  or "_shell"
                        local action = data.action or "unknown"
                        local body   = data.body

                        if panel == "_shell" and action == "ready" then
                            _shellReady = true
                            for _, js in ipairs(_shellEvalQ) do
                                pcall(function() _shellView:evaluateJavaScript(js) end)
                            end
                            _shellEvalQ = {}
                            hs.timer.doAfter(0.1, function()
                                if ms.ui and ms.ui.refresh then pcall(ms.ui.refresh) end
                            end)
                            -- Start fade-in if shell.show() was called before page loaded
                            if ms._shellState and ms._shellState.visible and _shellView then
                                local view = _shellView
                                local step, steps = 0, 6
                                local fadeMs = (ms._theme and ms._theme.fadeMs) or 150
                                _shellFadeTimer = hs.timer.doEvery(fadeMs / 1000 / steps, function()
                                    step = step + 1
                                    pcall(function() view:alpha(step / steps) end)
                                    if step >= steps then
                                        if _shellFadeTimer then _shellFadeTimer:stop(); _shellFadeTimer = nil end
                                    end
                                end)
                            end
                        end
                        -- Close: hide the shell when any panel sends {action:"close"}
                        if action == "close" then
                            pcall(function() ms.shell.hide() end)
                            return
                        end
                        -- Drag: JS only signals start; we track the real OS mouse
                        -- position (hs.mouse.absolutePosition) so the window's own
                        -- motion can never feed back into the pointer coordinates.
                        -- The webview reports those window-relative, which is what
                        -- made the panel accelerate off-screen away from the cursor.
                        if action == "dragStart" then
                            pcall(function()
                                if ms._shellDragTap then ms._shellDragTap:stop() end
                                -- Signal the Window Spy engine (and anything else on the
                                -- shared thread) to idle while we drag our own window, so
                                -- its watchers don't contend with the drag eventtap.
                                ms._shellDragging = true
                                -- Move by the delta of the OS mouse from where the drag
                                -- began, relative to where the window began. Using deltas
                                -- (not mouse - windowOrigin) means any constant offset
                                -- between the mouse and webview coordinate spaces cancels
                                -- out, and the global mouse position can't feed back from
                                -- the window's own motion.
                                local startFrame = _shellView:frame()
                                local startMouse = hs.mouse.absolutePosition()
                                local w, h = startFrame.w, startFrame.h
                                -- Usable top of the screen the drag began on. The window
                                -- top is never allowed above this: every drag handle lives
                                -- at the top of the window, so letting it go above the
                                -- screen would leave nothing to grab. Down/left/right are
                                -- safe because the grabbed point stays under the cursor.
                                local topLimit = (hs.mouse.getCurrentScreen() or hs.screen.mainScreen()):frame().y
                                -- Drop the shadow for the drag: recompositing a soft shadow
                                -- on a transparent, rounded window every reposition is the
                                -- main thing that makes it lag behind the cursor.
                                pcall(function() _shellView:shadow(false) end)
                                local et = hs.eventtap.event.types
                                ms._shellDragTap = hs.eventtap.new(
                                    { et.leftMouseDragged, et.leftMouseUp },
                                    function(ev)
                                        if not _shellView then return false end
                                        if ev:getType() == et.leftMouseUp then
                                            if ms._shellDragTap then ms._shellDragTap:stop(); ms._shellDragTap = nil end
                                            ms._shellDragging = false
                                            pcall(function() _shellView:shadow(true) end)
                                            pcall(ms.shell.saveState)
                                            return false
                                        end
                                        local mp = hs.mouse.absolutePosition()
                                        pcall(function()
                                            _shellView:frame({
                                                x = startFrame.x + (mp.x - startMouse.x),
                                                y = math.max(startFrame.y + (mp.y - startMouse.y), topLimit),
                                                w = w, h = h,
                                            })
                                        end)
                                        return false
                                    end)
                                ms._shellDragTap:start()
                            end)
                            return
                        end
                        -- MoveEnd: stop the tracker, then rubber-band back if the
                        -- window ended up more than half off-screen.
                        if action == "moveEnd" then
                            pcall(function()
                                if ms._shellDragTap then ms._shellDragTap:stop(); ms._shellDragTap = nil end
                                ms._shellDragging = false
                                pcall(function() _shellView:shadow(true) end)
                                local f = _shellView:frame()
                                local sf = hs.screen.mainScreen():frame()
                                -- How much of the window is visible
                                local visW = math.max(0, math.min(f.x + f.w, sf.x + sf.w) - math.max(f.x, sf.x))
                                local visH = math.max(0, math.min(f.y + f.h, sf.y + sf.h) - math.max(f.y, sf.y))
                                if visW < f.w * 0.5 or visH < f.h * 0.5 then
                                    -- Clamp so at least half is visible. Horizontally we
                                    -- allow some overhang; vertically the top is floored at
                                    -- the screen top so the drag handles are never hidden.
                                    local nx = math.max(sf.x - f.w * 0.4, math.min(f.x, sf.x + sf.w - f.w * 0.4))
                                    local ny = math.max(sf.y, math.min(f.y, sf.y + sf.h - f.h * 0.4))
                                    -- Animate with a quick timer
                                    local sx, sy = f.x, f.y
                                    local step, steps = 0, 5
                                    local view = _shellView
                                    _shellView:alpha(0.85)
                                    hs.timer.doEvery(0.016, function()
                                        step = step + 1
                                        local t = step / steps
                                        -- Ease-out curve
                                        t = 1 - (1 - t) * (1 - t)
                                        pcall(function()
                                            view:frame({
                                                x = sx + (nx - sx) * t,
                                                y = sy + (ny - sy) * t,
                                                w = f.w, h = f.h,
                                            })
                                        end)
                                        if step >= steps then
                                            pcall(function() view:frame({ x = nx, y = ny, w = f.w, h = f.h }) end)
                                            pcall(function() view:alpha(1) end)
                                            ms.shell.saveState()
                                            return false
                                        end
                                    end)
                                else
                                    -- On-screen: just persist where it landed.
                                    pcall(ms.shell.saveState)
                                end
                            end)
                            return
                        end
                        -- ClampSize: enforce minimum window dimensions
                        if action == "clampSize" and body and body.w and body.h then
                            pcall(function()
                                local f = _shellView:frame()
                                if f.w < body.w or f.h < body.h then
                                    _shellView:frame({
                                        x = f.x, y = f.y,
                                        w = math.max(f.w, body.w),
                                        h = math.max(f.h, body.h),
                                    })
                                end
                            end)
                            return
                        end
                        -- Reload actions: handled directly, not through bus
                        if action == "quickReload" then
                            pcall(ms.reload)
                            return
                        end
                        if action == "reloadMacros" then
                            if ms.ui and ms.ui._actions and ms.ui._actions.reloadMacros then
                                pcall(ms.ui._actions.reloadMacros)
                            end
                            return
                        end
                        if action == "reloadTheme" then
                            if ms.ui and ms.ui._actions and ms.ui._actions.reloadTheme then
                                pcall(ms.ui._actions.reloadTheme)
                            end
                            return
                        end
                        if action == "reloadSettings" then
                            if ms.ui and ms.ui._actions and ms.ui._actions.reloadSettings then
                                pcall(ms.ui._actions.reloadSettings)
                            end
                            return
                        end
                        if action == "reloadUI" then
                            if ms.ui and ms.ui._actions and ms.ui._actions.reloadUI then
                                pcall(ms.ui._actions.reloadUI)
                            end
                            return
                        end
                        -- PopOut: extract panel into standalone webview
                        if action == "popOut" and body and body.panel then
                            local pid = body.panel
                            local ok = ms.shell.popOut(pid)
                            if ok then
                                -- Tell shell to hide the inline panel
                                ms.shell.eval("shellReceive('" .. pid .. "', 'poppedOut')")
                            end
                            return
                        end
                        -- PopIn: return panel to shell (from standalone close)
                        if action == "popIn" and body and body.panel then
                            ms.shell.popIn(body.panel)
                            return
                        end
                        -- FocusPopOut: bring a popped-out panel's window to front
                        if action == "focusPopOut" and body and body.panel then
                            if ms.shell and ms.shell.getPopOutView then
                                local popView = ms.shell.getPopOutView(body.panel)
                                if popView then
                                    pcall(function() popView:show() end)
                                    pcall(function() popView:bringToFront(true) end)
                                    hs.timer.doAfter(0.15, function()
                                        pcall(function() popView:bringToFront(true) end)
                                    end)
                                end
                            end
                            return
                        end
                        -- PlaySlot: route sound requests back to ms.playSlot
                        if action == "playSlot" and body and body.slot then
                            pcall(function() ms.playSlot(body.slot) end)
                            return
                        end
                        -- Bus routing
                        if ms.bus then
                            local topic = "ui:" .. panel .. ":" .. action
                            ms.bus.emit(topic, body)
                        end
                    end)

                    local sf = hs.screen.mainScreen():frame()
                    -- Cap to 85% of screen so it fits on low-res displays
                    local maxW = math.floor(sf.w * 0.85)
                    local maxH = math.floor(sf.h * 0.85)
                    local w = math.min(820, maxW)
                    local h = math.min(520, maxH)
                    local x = sf.x + math.floor((sf.w - w) / 2)
                    local y = sf.y + math.floor((sf.h - h) / 2)
                    local st = ms._shellState
                    if st and st.x and st.y then
                        x, y = st.x, st.y
                        if st.w then w = st.w end
                        if st.h then h = st.h end
                    end

                    _shellView = hs.webview.new({ x = x, y = y, w = w, h = h }, {}, _shellChannel)
                    pcall(function() _shellView:windowStyle(0) end)
                    pcall(function() _shellView:transparent(true) end)
                    pcall(function() _shellView:allowResizing(true) end)
                    -- Note: minimumSize is unreliable on borderless webviews.
                    -- JS-side enforcement handles the actual clamping.
                    pcall(function() _shellView:minimumSize({ w = 800, h = 500 }) end)
                    pcall(function() _shellView:level(hs.canvas.windowLevels.popUpMenu or 101) end)
                    pcall(function() _shellView:allowTextEntry(true) end)
                    pcall(function() _shellView:shadow(true) end)
                    _shellView:alpha(0)

                    local htmlPath = hs.configdir .. "/ui/ms_shell.html"
                    local baseURL  = "file://" .. hs.configdir .. "/ui/"
                    local f = io.open(htmlPath, "r")
                    if f then
                        local html = f:read("*all"); f:close()
                        -- Inject window radius CSS variable + transparent html into <head>
                        local r = (ms._theme and ms._theme.windowRadius)
                            or (ms._themeDefaults and ms._themeDefaults.windowRadius) or 0
                        local inject = string.format(
                            '<style>html{background:transparent!important;--ms-window-radius:%dpx;}</style>',
                            r
                        )
                        html = html:gsub("</head>", inject .. "</head>", 1)
                        _shellView:html(html, baseURL)
                    end

                    -- Apply window radius (transparent bg + CSS variable)
                    if ms.theme and ms.theme.applyWindowRadius then
                        ms.theme.applyWindowRadius(_shellView)
                    end
                    -- Re-apply shadow after applyWindowRadius (it disables shadow for rounded windows)
                    pcall(function() _shellView:shadow(true) end)

                    hs.timer.doAfter(0.05, function()
                        if not _shellView then return end
                        local themeJson = hs.json.encode(ms._theme or {})
                        _shellView:evaluateJavaScript("applyTheme(" .. themeJson .. ")")
                    end)

                    -- When a popout closes, tell the shell to restore the inline panel
                    -- and trigger a history reload so the inline panel has data.
                    if ms.bus then
                        ms.bus.on("panel:poppedIn", function(data)
                            if data and data.id then
                                ms.shell.eval("shellReceive('" .. data.id .. "', 'poppedIn')")
                                -- Trigger history reload for the inline panel
                                hs.timer.doAfter(0.1, function()
                                    pcall(function()
                                        ms.bus.emit("ui:" .. data.id .. ":ready", { action = "ready" })
                                    end)
                                end)
                            end
                        end)
                    end
                end

                ms.shell.saveState = function()
                    if not _shellView then return end
                    local ok, frame = pcall(function() return _shellView:frame() end)
                    if ok and frame then
                        ms._shellState = ms._shellState or {}
                        ms._shellState.x = math.floor(frame.x)
                        ms._shellState.y = math.floor(frame.y)
                        ms._shellState.w = math.floor(frame.w)
                        ms._shellState.h = math.floor(frame.h)
                        if ms.saveSettings then pcall(ms.saveSettings) end
                    end
                end

                ms.shell._restoreFrame = function()
                    if not _shellView then return end
                    local st = ms._shellState
                    if not st or not st.x or not st.y then return end
                    pcall(function()
                        local w = st.w or 820
                        local h = st.h or 520
                        -- Pick the screen the saved position sits on; fall back to
                        -- the main screen so a frame left over from a now-disconnected
                        -- display (or dragged off-screen) still lands somewhere visible.
                        local screenObj = hs.screen.mainScreen()
                        local cx, cy = st.x + w / 2, st.y + h / 2
                        for _, s in ipairs(hs.screen.allScreens()) do
                            local sf = s:frame()
                            if cx >= sf.x and cx < sf.x + sf.w and cy >= sf.y and cy < sf.y + sf.h then
                                screenObj = s
                                break
                            end
                        end
                        local sf = screenObj:frame()
                        w = math.min(w, sf.w)
                        h = math.min(h, sf.h)
                        -- Clamp fully on-screen so a persisted off-screen frame self-heals
                        -- on reload instead of reopening where it can't be grabbed.
                        local x = math.max(sf.x, math.min(st.x, sf.x + sf.w - w))
                        local y = math.max(sf.y, math.min(st.y, sf.y + sf.h - h))
                        _shellView:frame({ x = x, y = y, w = w, h = h })
                    end)
                end

                ms.shell._activePanel = "macros"
                ms.shell.setActivePanel = function(id)
                    if type(id) ~= "string" then return end
                    ms.shell._activePanel = id
                    ms._shellState = ms._shellState or {}
                    ms._shellState.lastPanel = id
                end

                ms.shell.show = function()
                    if not _shellView then ms.shell.init() end
                    if _shellFadeTimer then _shellFadeTimer:stop(); _shellFadeTimer = nil end
                    ms.shell._restoreFrame()
                    pcall(function() ms.playSlot("settingsOpen") end)
                    _shellView:alpha(0)
                    _shellView:show()
                    pcall(function() _shellView:bringToFront(true) end)
                    ms._shellState = ms._shellState or {}
                    ms._shellState.visible = true
                    if ms.bus then ms.bus.emit("macroLab:toggled", { visible = true }) end
                    -- If page hasn't loaded yet, the "ready" callback will start the fade
                    if not _shellReady then return end
                    local view = _shellView
                    local step, steps = 0, 6
                    local fadeMs = (ms._theme and ms._theme.fadeMs) or 150
                    _shellFadeTimer = hs.timer.doEvery(fadeMs / 1000 / steps, function()
                        step = step + 1
                        pcall(function() view:alpha(step / steps) end)
                        if step >= steps then
                            if _shellFadeTimer then _shellFadeTimer:stop(); _shellFadeTimer = nil end
                        end
                    end)
                end

                ms.shell.hide = function()
                    if _shellView then
                        if _shellFadeTimer then _shellFadeTimer:stop(); _shellFadeTimer = nil end
                        if ms._shellState and ms._shellState.visible then
                            pcall(function() ms.playSlot("settingsClose") end)
                        end
                        ms.shell.saveState()
                        ms._shellState = ms._shellState or {}
                        ms._shellState.visible = false
                        local view = _shellView
                        local startAlpha = 1
                        pcall(function() startAlpha = view:alpha() or 1 end)
                        local step, steps = 0, 6
                        local fadeMs = (ms._theme and ms._theme.fadeMs) or 150
                        _shellFadeTimer = hs.timer.doEvery(fadeMs / 1000 / steps, function()
                            step = step + 1
                            pcall(function() view:alpha(startAlpha * (1 - (step / steps))) end)
                            if step >= steps then
                                if _shellFadeTimer then _shellFadeTimer:stop(); _shellFadeTimer = nil end
                                pcall(function() view:hide() end)
                            end
                        end)
                        if ms.bus then ms.bus.emit("macroLab:toggled", { visible = false }) end
                    end
                end

                ms.shell.toggle = function()
                    if _shellView and _shellView:isVisible() then
                        ms.shell.hide()
                    else
                        ms.shell.show()
                    end
                end

                ms.shell.destroy = function()
                    if _shellFadeTimer then _shellFadeTimer:stop(); _shellFadeTimer = nil end
                    if _shellView then
                        pcall(function() _shellView:delete() end)
                        _shellView = nil
                    end
                    _shellChannel  = nil
                    _shellReady    = false
                    _shellEvalQ    = {}
                end

                -- shellDispatch: route messages from inline panels to Lua handlers
                ms.shell.dispatch = function(panel, action, body)
                    if ms.bus then
                        ms.bus.emit("ui:" .. panel .. ":" .. action, body)
                    end
                end

                -- popOut: load standalone panel HTML into its own webview
                local _popouts = {}
                local _panelFiles = {
                    console = "ms_console.html",
                    watcher = "ms_watcher.html",
                    keys    = "ms_keys.html",
                    window  = "ms_window.html",
                }

                --- Build a :root CSS block from ms._theme tokens so popouts
                --- render with the correct palette immediately (no JS race).
                local function _buildThemeCSS()
                    local t = ms._theme or {}
                    local d = ms._themeDefaults or {}
                    local function v(k) return t[k] or d[k] end
                    local parts = {}
                    local map = {
                        bg = "--bg", surface = "--surface", surface2 = "--surface2",
                        hover = "--hover", accent = "--accent", accentHi = "--accent-hi",
                        success = "--success", dangerBg = "--danger-bg", danger = "--danger",
                        warning = "--warning", text = "--text",
                        accentGlow = "--accent-glow", accentGlowFaint = "--accent-glow-faint",
                        dangerGlow = "--danger-glow", dangerBorder = "--danger-border",
                        mouse = "--mouse", scroll = "--scroll", key = "--key",
                        recording = "--recording", recordingText = "--recording-text",
                        recordingBg = "--recording-bg", running = "--running",
                        runningText = "--running-text", runningBg = "--running-bg",
                    }
                    for k, cssVar in pairs(map) do
                        local val = v(k)
                        if val then parts[#parts + 1] = cssVar .. ":" .. val end
                    end
                    -- Hex-to-rgb helper for derived vars
                    local function hexRgb(hex)
                        if not hex or type(hex) ~= "string" then return nil end
                        hex = hex:gsub("#", "")
                        if #hex ~= 6 then return nil end
                        local r = tonumber(hex:sub(1,2), 16)
                        local g = tonumber(hex:sub(3,4), 16)
                        local b = tonumber(hex:sub(5,6), 16)
                        if not r or not g or not b then return nil end
                        return r, g, b
                    end
                    -- Derived text2/text3 (from text color with reduced alpha)
                    local tr, tg, tb = hexRgb(v("text"))
                    if tr then
                        if not t.text2 then parts[#parts + 1] = ("--text2:rgba(%d,%d,%d,0.85)"):format(tr, tg, tb) end
                        if not t.text3 then parts[#parts + 1] = ("--text3:rgba(%d,%d,%d,0.55)"):format(tr, tg, tb) end
                    end
                    -- Derived accent-glow / accent-glow-faint (from accent)
                    if not t.accentGlow then
                        local ar2, ag2, ab2 = hexRgb(v("accent"))
                        if ar2 then parts[#parts + 1] = ("--accent-glow:rgba(%d,%d,%d,0.4)"):format(ar2, ag2, ab2) end
                    end
                    if not t.accentGlowFaint then
                        local ar3, ag3, ab3 = hexRgb(v("accent"))
                        if ar3 then parts[#parts + 1] = ("--accent-glow-faint:rgba(%d,%d,%d,0.12)"):format(ar3, ag3, ab3) end
                    end
                    -- Derived danger-glow / danger-border (from danger)
                    if not t.dangerGlow then
                        local dr2, dg2, db2 = hexRgb(v("danger"))
                        if dr2 then parts[#parts + 1] = ("--danger-glow:rgba(%d,%d,%d,0.6)"):format(dr2, dg2, db2) end
                    end
                    if not t.dangerBorder then
                        local dr3, dg3, db3 = hexRgb(v("danger"))
                        if dr3 then parts[#parts + 1] = ("--danger-border:rgba(%d,%d,%d,0.3)"):format(dr3, dg3, db3) end
                    end
                    -- Derived border/border-dim (blend of accent + hover)
                    if not t.border then
                        local ar, ag, ab = hexRgb(v("accent"))
                        local hr, hg, hb = hexRgb(v("hover"))
                        if ar and hr then
                            local mr, mg, mb = math.floor((ar+hr)/2), math.floor((ag+hg)/2), math.floor((ab+hb)/2)
                            parts[#parts + 1] = ("--border:rgba(%d,%d,%d,0.55)"):format(mr, mg, mb)
                            parts[#parts + 1] = ("--border-dim:rgba(%d,%d,%d,0.18)"):format(mr, mg, mb)
                        end
                    end
                    -- Radius
                    local radius = v("radius") or 4
                    parts[#parts + 1] = "--radius:" .. radius .. "px"
                    parts[#parts + 1] = "--radius-s:" .. math.max(0, radius - 1) .. "px"
                    -- Font
                    local font = v("font")
                    if font then
                        parts[#parts + 1] = "--font:\"" .. font .. "\",Almendra,Palatino,Georgia,serif"
                    end
                    return ":root{" .. table.concat(parts, ";") .. "}"
                end

                --- Pre-bake popout HTML files with current theme injected.
                --- Called at init and when theme changes.
                ms.shell.bakePopOuts = function()
                    local themeCSS = _buildThemeCSS()
                    local r = (ms._theme and ms._theme.windowRadius)
                        or (ms._themeDefaults and ms._themeDefaults.windowRadius) or 0
                    for pid, fileName in pairs(_panelFiles) do
                        local srcPath = hs.configdir .. "/ui/" .. fileName
                        local f = io.open(srcPath, "r")
                        if f then
                            local html = f:read("*all"); f:close()
                            -- Inject CSS: html/body transparent, #popout-root has bg + radius
                            -- (mirrors #shell-root pattern in ms_shell.html)
                            local inject = string.format(
                                '<style>html,body{background:transparent!important;overflow:hidden;}'
                                .. '#popout-root{display:flex;flex-direction:column;'
                                .. 'width:100%%;height:100%%;'
                                .. 'background:var(--bg);border-radius:%dpx;overflow:hidden;}'
                                .. ':root{--ms-window-radius:%dpx;}'
                                .. '%s</style>',
                                r, r, themeCSS
                            )
                            html = html:gsub("</head>", inject:gsub("%%", "%%%%") .. "</head>", 1)
                            -- Wrap body content in #popout-root (like #shell-root)
                            html = html:gsub("(<body[^>]*>)", "%1<div id='popout-root'>")
                            html = html:gsub("(</body>)", "</div>%1")
                            local tmpName = hs.configdir .. "/ui/_popout_" .. pid .. ".html"
                            local wf = io.open(tmpName, "w")
                            if wf then
                                wf:write(html); wf:close()
                            end
                        end
                    end
                end

                -- Bake on init
                ms.shell.bakePopOuts()

                -- Rebake whenever theme changes
                if ms.loadTheme then
                    local _origLoadTheme = ms.loadTheme
                    ms.loadTheme = function()
                        _origLoadTheme()
                        pcall(ms.shell.bakePopOuts)
                    end
                end

                --- Push JS to a popout webview (used by _pushToPanel fallback).
                ms.shell.getPopOutView = function(panelId)
                    local pop = _popouts[panelId]
                    return pop and pop.view or nil
                end

                ms.shell.popOut = function(panelId)
                    if _popouts[panelId] then
                        pcall(function() _popouts[panelId].view:show() end)
                        pcall(function() _popouts[panelId].view:bringToFront(true) end)
                        hs.timer.doAfter(0.1, function()
                            pcall(function() _popouts[panelId].view:bringToFront(true) end)
                        end)
                        return true
                    end
                    local tmpName = hs.configdir .. "/ui/_popout_" .. panelId .. ".html"
                    local f = io.open(tmpName, "r")
                    if not f then
                        ms.shell.bakePopOuts()
                        f = io.open(tmpName, "r")
                        if not f then
                            print("[popOut] no baked file for panel: " .. tostring(panelId))
                            return false
                        end
                    end
                    f:close()

                    require("hs.webview")
                    require("hs.webview.usercontent")

                    local sf = hs.screen.mainScreen():frame()
                    local w, h = 650, 450
                    local x = sf.x + math.floor((sf.w - w) / 2) + 40
                    local y = sf.y + math.floor((sf.h - h) / 2) + 40

                    -- Use the panel's own channel name so no HTML surgery is needed.
                    -- The standalone HTML sends to webkit.messageHandlers[panelId].
                    local popChannel = hs.webview.usercontent.new(panelId)
                    local popView  -- declare before callback so closure captures it
                    popChannel:setCallback(function(message)
                        local ok, data = pcall(hs.json.decode, message.body or "")
                        if not ok or type(data) ~= "table" then return end
                        local panel  = data.panel  or panelId
                        local action = data.action or "unknown"
                        local body   = data.body or data
                        -- Route playSlot back through ms.playSlot
                        if action == "playSlot" and body and body.slot then
                            pcall(function() ms.playSlot(body.slot) end)
                            return
                        end
                        -- Close: hide instantly, restore to shell, then delete
                        if action == "close" then
                            pcall(function() popView:hide() end)
                            _popouts[panelId] = nil
                            -- Tell shell directly (don't rely on bus)
                            if ms.shell and ms.shell.eval then
                                ms.shell.eval("shellReceive('" .. panelId .. "', 'poppedIn')")
                                -- Trigger history reload for the inline panel
                                hs.timer.doAfter(0.1, function()
                                    pcall(function()
                                        ms.bus.emit("ui:" .. panelId .. ":ready", { action = "ready" })
                                    end)
                                end)
                            end
                            hs.timer.doAfter(0.3, function()
                                pcall(function() popView:delete() end)
                            end)
                            return
                        end
                        -- Move: drag the popout window (JS sends dx/dy deltas)
                        if action == "move" and body and body.dx and body.dy then
                            pcall(function()
                                local f2 = popView:frame()
                                popView:frame({
                                    x = f2.x + body.dx,
                                    y = f2.y + body.dy,
                                    w = f2.w,
                                    h = f2.h,
                                })
                            end)
                            return
                        end
                        -- ClampSize: enforce minimum popout dimensions
                        if action == "clampSize" and body and body.w and body.h then
                            pcall(function()
                                local f2 = popView:frame()
                                if f2.w < body.w or f2.h < body.h then
                                    popView:frame({
                                        x = f2.x, y = f2.y,
                                        w = math.max(f2.w, body.w),
                                        h = math.max(f2.h, body.h),
                                    })
                                end
                            end)
                            return
                        end
                        if ms.bus then
                            ms.bus.emit("ui:" .. panel .. ":" .. action, body)
                        end
                    end)

                    popView = hs.webview.new({ x = x, y = y, w = w, h = h }, {}, popChannel)
                    if not popView then
                        print("[popOut] hs.webview.new returned nil")
                        return false
                    end
                    pcall(function() popView:windowStyle(0) end)
                    pcall(function() popView:transparent(true) end)
                    pcall(function() popView:level(hs.canvas.windowLevels.popUpMenu or 101) end)
                    pcall(function() popView:allowTextEntry(true) end)
                    pcall(function() popView:shadow(true) end)
                    pcall(function() popView:minimumSize({ w = 400, h = 300 }) end)
                    pcall(function() popView:allowResizing(true) end)

                    -- Load via url() — document gets a real file URL
                    popView:url("file://" .. tmpName)
                    popView:show()
                    -- Bring popout above the shell after window system settles
                    hs.timer.doAfter(0.15, function()
                        pcall(function() popView:bringToFront(true) end)
                    end)

                    -- Apply theme after page loads (url() is async)
                    -- NOTE: do NOT call applyWindowRadius on popouts — it sets
                    -- body background to transparent, but popouts have no inner
                    -- wrapper like #shell-root to fill the gap (invisible bg bug).
                    -- The bake CSS already handles body background + border-radius.
                    hs.timer.doAfter(0.5, function()
                        if not popView then return end
                        local themeJson = hs.json.encode(ms._theme or {})
                        pcall(function() popView:evaluateJavaScript("applyTheme(" .. themeJson .. ")") end)
                    end)

                    _popouts[panelId] = { view = popView, channel = popChannel }
                    if ms.bus then ms.bus.emit("panel:poppedOut", { id = panelId }) end
                    return true
                end

                ms.shell.popIn = function(panelId)
                    local pop = _popouts[panelId]
                    if not pop then return false end
                    pcall(function() pop.view:hide() end)
                    _popouts[panelId] = nil
                    -- Tell shell directly (don't rely on bus)
                    if ms.shell and ms.shell.eval then
                        ms.shell.eval("shellReceive('" .. panelId .. "', 'poppedIn')")
                        -- Trigger history reload for the inline panel
                        hs.timer.doAfter(0.1, function()
                            pcall(function()
                                ms.bus.emit("ui:" .. panelId .. ":ready", { action = "ready" })
                            end)
                        end)
                    end
                    hs.timer.doAfter(0.3, function()
                        pcall(function() pop.view:delete() end)
                    end)
                    return true
                end

                ms.shell.isPoppedOut = function(panelId)
                    return _popouts[panelId] ~= nil
                end
            end
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
            do
                local home       = os.getenv("HOME")
                local dataDir    = home .. "/.hammerspoon/data"
                local jsonPath   = dataDir .. "/ms_macros_visual.json"
                local luaPath    = dataDir .. "/ms_macros_visual.lua"

                ms.compiler = {}

                -- ── helpers ──────────────────────────────────────────────

                --- Serialize a Lua value to a source literal.
                local function serialize(val)
                    local t = type(val)
                    if t == "string"  then return string.format("%q", val) end
                    if t == "number"  then return tostring(val) end
                    if t == "boolean" then return tostring(val) end
                    if t == "nil"     then return "nil" end
                    if t == "table" then
                        local parts = {}
                        local isList = (#val > 0)
                        if isList then
                            for _, v in ipairs(val) do
                                parts[#parts + 1] = serialize(v)
                            end
                        else
                            for k, v in pairs(val) do
                                local key
                                if type(k) == "string" and k:match("^%a[%w_]*$") then
                                    key = k
                                else
                                    key = "[" .. serialize(k) .. "]"
                                end
                                parts[#parts + 1] = key .. " = " .. serialize(v)
                            end
                        end
                        return "{" .. table.concat(parts, ", ") .. "}"
                    end
                    return tostring(val)
                end

                --- Build the argument list string for a sandbox call.
                --- params is a table; keys are positional in order of an explicit `args` array
                --- OR named keys that map to the function signature.
                local function buildArgs(params, argOrder)
                    if not params or not argOrder then return "" end
                    local parts = {}
                    for _, key in ipairs(argOrder) do
                        local v = params[key]
                        if v ~= nil then
                            parts[#parts + 1] = serialize(v)
                        end
                    end
                    return table.concat(parts, ", ")
                end

                -- ── action → Lua code emitter ────────────────────────────
                -- Each emitter returns a string of Lua code for one step.
                -- indent is the current indentation level (number of 4-space groups).

                local INDENT = "    "

                local function indent(n)
                    local s = ""
                    for _ = 1, n do s = s .. INDENT end
                    return s
                end

                --- Emit a single action step. Returns Lua source lines (string).
                local emitStep  -- forward declaration

                local emitters = {}

                -- Simple passthrough calls ---------------------------------

                emitters["ms.type"] = function(step, lvl)
                    local p = step.params or {}
                    local args
                    if p.mods and #p.mods > 0 then
                        args = serialize(p.key) .. ", " .. serialize(p.mods)
                    else
                        args = serialize(p.key)
                    end
                    return indent(lvl) .. "ms.type(" .. args .. ")"
                end

                emitters["ms.wait"] = function(step, lvl)
                    local ms_val = (step.params and step.params.ms) or 100
                    return indent(lvl) .. "ms.wait(" .. tostring(ms_val) .. ")"
                end

                emitters["ms.copy"] = function(step, lvl)
                    local text = (step.params and step.params.text) or ""
                    return indent(lvl) .. "ms.copy(" .. serialize(text) .. ")"
                end

                emitters["ms.paste"] = function(step, lvl)
                    return indent(lvl) .. "ms.paste()"
                end

                emitters["ms.press"] = function(step, lvl)
                    local p = step.params or {}
                    local args
                    if p.mods and #p.mods > 0 then
                        args = serialize(p.key) .. ", " .. serialize(p.mods)
                    else
                        args = serialize(p.key)
                    end
                    return indent(lvl) .. "ms.press(" .. args .. ")"
                end

                emitters["ms.hold"] = function(step, lvl)
                    local p = step.params or {}
                    local args
                    if p.mods and #p.mods > 0 then
                        args = serialize(p.key) .. ", " .. serialize(p.mods)
                    else
                        args = serialize(p.key)
                    end
                    return indent(lvl) .. "ms.hold(" .. args .. ")"
                end

                emitters["ms.release"] = function(step, lvl)
                    local key = (step.params and step.params.key) or ""
                    return indent(lvl) .. "ms.release(" .. serialize(key) .. ")"
                end

                emitters["ms.cam"] = function(step, lvl)
                    local p = step.params or {}
                    return indent(lvl) .. "ms.cam(" .. tostring(p.dx or 0) .. ", " .. tostring(p.dy or 0) .. ")"
                end

                emitters["ms.cam.rebalance"] = function(step, lvl)
                    return indent(lvl) .. "ms.cam.rebalance()"
                end

                emitters["ms.cam.reset"] = function(step, lvl)
                    return indent(lvl) .. "ms.cam.reset()"
                end

                emitters["ms.scroll"] = function(step, lvl)
                    local p = step.params or {}
                    local dir = serialize(p.direction or "up")
                    if p.clicks and p.clicks > 1 then
                        return indent(lvl) .. "ms.scroll(" .. dir .. ", " .. tostring(p.clicks) .. ")"
                    end
                    return indent(lvl) .. "ms.scroll(" .. dir .. ")"
                end

                emitters["ms.alert"] = function(step, lvl)
                    local p = step.params or {}
                    local args = serialize(p.message or p.msg or "")
                    if p.duration then args = args .. ", " .. tostring(p.duration) end
                    return indent(lvl) .. "ms.alert(" .. args .. ")"
                end

                -- Mouse operations (from recording) ----------------------------

                emitters["ms.Mouse"] = function(step, lvl)
                    local p = step.params or {}
                    local parts = {}
                    parts[#parts + 1] = serialize(p.operation or "Click")
                    parts[#parts + 1] = serialize(p.button or "Left")
                    parts[#parts + 1] = serialize(p.reference or "Mouse")
                    parts[#parts + 1] = tostring(p.x or 0)
                    parts[#parts + 1] = tostring(p.y or 0)
                    return indent(lvl) .. "ms.Mouse(" .. table.concat(parts, ", ") .. ")"
                end

                -- Variable operations --------------------------------------

                emitters["var_set"] = function(step, lvl)
                    local p = step.params or {}
                    local name  = p.name or "v"
                    local value = serialize(p.value)
                    return indent(lvl) .. "local " .. name .. " = " .. value
                end

                emitters["var_add"] = function(step, lvl)
                    local p = step.params or {}
                    local name   = p.name or "v"
                    local amount = p.amount or 1
                    return indent(lvl) .. name .. " = " .. name .. " + " .. tostring(amount)
                end

                emitters["var_sub"] = function(step, lvl)
                    local p = step.params or {}
                    local name   = p.name or "v"
                    local amount = p.amount or 1
                    return indent(lvl) .. name .. " = " .. name .. " - " .. tostring(amount)
                end

                emitters["var_mul"] = function(step, lvl)
                    local p = step.params or {}
                    local name   = p.name or "v"
                    local amount = p.amount or 2
                    return indent(lvl) .. name .. " = " .. name .. " * " .. tostring(amount)
                end

                -- Control flow ---------------------------------------------

                local _flowCounter = 0

                emitters["if"] = function(step, lvl)
                    local cond = step.condition or "true"
                    local lines = {}
                    lines[#lines + 1] = indent(lvl) .. "if " .. cond .. " then"
                    lines[#lines + 1] = indent(lvl + 1) .. "ms.log('if', '" .. cond:gsub("'", "\\'") .. "', true)"
                    if step.then_steps then
                        for _, s in ipairs(step.then_steps) do
                            lines[#lines + 1] = emitStep(s, lvl + 1)
                        end
                    end
                    if step.else_steps then
                        lines[#lines + 1] = indent(lvl) .. "else"
                        lines[#lines + 1] = indent(lvl + 1) .. "ms.log('if', '" .. cond:gsub("'", "\\'") .. "', false)"
                        for _, s in ipairs(step.else_steps) do
                            lines[#lines + 1] = emitStep(s, lvl + 1)
                        end
                    end
                    lines[#lines + 1] = indent(lvl) .. "end"
                    return table.concat(lines, "\n")
                end

                emitters["for"] = function(step, lvl)
                    local p = step.params or {}
                    local varName = p.var or "i"
                    local from    = p.from or 1
                    local to      = p.to or 1
                    local stepVal = p.step
                    local lines = {}
                    local forArgs = tostring(from) .. ", " .. tostring(to)
                    if stepVal then forArgs = forArgs .. ", " .. tostring(stepVal) end
                    _flowCounter = _flowCounter + 1
                    local fc = "_fc" .. _flowCounter
                    lines[#lines + 1] = indent(lvl) .. "local " .. fc .. " = 0"
                    lines[#lines + 1] = indent(lvl) .. "for " .. varName .. " = " .. forArgs .. " do"
                    lines[#lines + 1] = indent(lvl + 1) .. fc .. " = " .. fc .. " + 1"
                    if step.body then
                        for _, s in ipairs(step.body) do
                            lines[#lines + 1] = emitStep(s, lvl + 1)
                        end
                    end
                    lines[#lines + 1] = indent(lvl) .. "end"
                    lines[#lines + 1] = indent(lvl) .. "ms.log('for', '" .. varName .. "=" .. forArgs .. "', " .. fc .. ")"
                    return table.concat(lines, "\n")
                end

                emitters["while"] = function(step, lvl)
                    local cond = step.condition or "true"
                    local lines = {}
                    _flowCounter = _flowCounter + 1
                    local fc = "_fc" .. _flowCounter
                    lines[#lines + 1] = indent(lvl) .. "local " .. fc .. " = 0"
                    lines[#lines + 1] = indent(lvl) .. "while " .. cond .. " do"
                    lines[#lines + 1] = indent(lvl + 1) .. fc .. " = " .. fc .. " + 1"
                    if step.body then
                        for _, s in ipairs(step.body) do
                            lines[#lines + 1] = emitStep(s, lvl + 1)
                        end
                    end
                    lines[#lines + 1] = indent(lvl) .. "end"
                    lines[#lines + 1] = indent(lvl) .. "ms.log('while', '" .. cond:gsub("'", "\\'") .. "', " .. fc .. ")"
                    return table.concat(lines, "\n")
                end

                emitters["repeat"] = function(step, lvl)
                    local cond = step.condition or "true"
                    local lines = {}
                    _flowCounter = _flowCounter + 1
                    local fc = "_fc" .. _flowCounter
                    lines[#lines + 1] = indent(lvl) .. "local " .. fc .. " = 0"
                    lines[#lines + 1] = indent(lvl) .. "repeat"
                    lines[#lines + 1] = indent(lvl + 1) .. fc .. " = " .. fc .. " + 1"
                    if step.body then
                        for _, s in ipairs(step.body) do
                            lines[#lines + 1] = emitStep(s, lvl + 1)
                        end
                    end
                    lines[#lines + 1] = indent(lvl) .. "until " .. cond
                    lines[#lines + 1] = indent(lvl) .. "ms.log('repeat', '" .. cond:gsub("'", "\\'") .. "', " .. fc .. ")"
                    return table.concat(lines, "\n")
                end

                -- Comment ---------------------------------------------------

                emitters["comment"] = function(step, lvl)
                    local text = (step.params and step.params.text) or ""
                    return indent(lvl) .. "-- " .. text
                end

                -- Custom code (escape hatch) --------------------------------

                emitters["code"] = function(step, lvl)
                    local src = (step.params and step.params.source) or ""
                    -- Indent each line of the custom source
                    local lines = {}
                    for line in src:gmatch("([^\n]*)\n?") do
                        if line ~= "" then
                            lines[#lines + 1] = indent(lvl) .. line
                        end
                    end
                    return table.concat(lines, "\n")
                end

                -- Generic fallback for any ms.* call -----------------------

                local function genericEmitter(step, lvl)
                    local action = step.action
                    local p = step.params or {}
                    -- If params has an ordered `args` array, use it
                    if p.args then
                        local parts = {}
                        for _, v in ipairs(p.args) do
                            parts[#parts + 1] = serialize(v)
                        end
                        return indent(lvl) .. action .. "(" .. table.concat(parts, ", ") .. ")"
                    end
                    -- Otherwise serialize all params as a single table
                    local parts = {}
                    for k, v in pairs(p) do
                        parts[#parts + 1] = k .. "=" .. serialize(v)
                    end
                    if #parts == 0 then
                        return indent(lvl) .. action .. "()"
                    end
                    return indent(lvl) .. action .. "(" .. serialize(p) .. ")"
                end

                -- emitStep implementation -----------------------------------

                emitStep = function(step, lvl)
                    lvl = lvl or 1
                    local action = step.action
                    if not action then return indent(lvl) .. "-- [empty step]" end
                    local emitter = emitters[action]
                    if emitter then
                        return emitter(step, lvl)
                    end
                    -- Fallback: treat as an ms.* call
                    return genericEmitter(step, lvl)
                end

                -- ── compile one macro definition → Lua source ─────────────

                ---@param macroDef table  A single macro definition from the JSON
                ---@return string         Lua source code (without the global header)
                ms.compiler.compile = function(macroDef)
                    assert(type(macroDef) == "table", "ms.compiler.compile: macroDef must be a table")
                    assert(type(macroDef.id) == "string", "ms.compiler.compile: macroDef.id must be a string")

                    local id     = macroDef.id
                    local name   = macroDef.name or id
                    local author = macroDef.author or "Visual"
                    local group  = macroDef.group or "visual"
                    local steps  = macroDef.steps or {}
                    local bind   = macroDef.bind or {}
                    local cooldown = macroDef.cooldown

                    -- Validate id is a safe Lua identifier
                    assert(id:match("^[%a_][%w_]*$"),
                        "ms.compiler.compile: invalid macro id '" .. id .. "' (must be a valid Lua identifier)")

                    local fnName = id .. "Function"
                    local lines = {}

                    -- Function body
                    lines[#lines + 1] = "local " .. fnName .. " = ms.fn(function()"
                    -- Default timing variable
                    lines[#lines + 1] = indent(1) .. "local t = 100"
                    for _, step in ipairs(steps) do
                        lines[#lines + 1] = emitStep(step, 1)
                    end
                    lines[#lines + 1] = 'end, "' .. name .. '")'
                    lines[#lines + 1] = ""

                    -- bind.define call
                    lines[#lines + 1] = 'ms.bind.define("' .. id .. '", ' .. fnName .. ", {"
                    lines[#lines + 1] = indent(1) .. 'group   = "' .. group .. '",'
                    lines[#lines + 1] = indent(1) .. 'label   = "' .. name .. '",'
                    if cooldown then
                        lines[#lines + 1] = indent(1) .. "cooldown = " .. tostring(cooldown) .. ","
                    end
                    if bind.type or bind.key then
                        lines[#lines + 1] = indent(1) .. "default = {"
                        lines[#lines + 1] = indent(2) .. 'type = "' .. (bind.type or "key") .. '",'
                        if bind.mods and #bind.mods > 0 then
                            local modParts = {}
                            for _, m in ipairs(bind.mods) do modParts[#modParts + 1] = '"' .. m .. '"' end
                            lines[#lines + 1] = indent(2) .. "mods = {" .. table.concat(modParts, ", ") .. "},"
                        else
                            lines[#lines + 1] = indent(2) .. "mods = {},"
                        end
                        if bind.key then
                            lines[#lines + 1] = indent(2) .. 'key  = "' .. bind.key .. '",'
                        end
                        lines[#lines + 1] = indent(1) .. "},"
                    end
                    lines[#lines + 1] = "})"

                    return table.concat(lines, "\n")
                end

                -- ── write compiled Lua to file ────────────────────────────

                --- Write (or rewrite) the full compiled file from all macro sources.
                ---@param sources table  Array of { id=string, source=string } pairs
                ms.compiler._writeFile = function(sources)
                    local lines = {}
                    lines[#lines + 1] = "-- ══════════════════════════════════════════════════════════════"
                    lines[#lines + 1] = "-- AUTO-GENERATED by ms.compiler — DO NOT EDIT BY HAND"
                    lines[#lines + 1] = "-- Source: data/ms_macros_visual.json"
                    lines[#lines + 1] = "-- Rebuild: ms.compiler.rebuild()"
                    lines[#lines + 1] = "-- ══════════════════════════════════════════════════════════════"
                    lines[#lines + 1] = ""
                    lines[#lines + 1] = "-- Creator Credits --"
                    lines[#lines + 1] = "    ms.macroMeta = {"
                    lines[#lines + 1] = '        name    = "Visual Macros",'
                    lines[#lines + 1] = '        author  = "ms.compiler"'
                    lines[#lines + 1] = "    }"
                    lines[#lines + 1] = "-- END Creator Credits --"
                    lines[#lines + 1] = ""

                    for _, entry in ipairs(sources) do
                        lines[#lines + 1] = "-- " .. entry.id .. " --"
                        lines[#lines + 1] = entry.source
                        lines[#lines + 1] = "-- END " .. entry.id .. " --"
                        lines[#lines + 1] = ""
                    end

                    local out = table.concat(lines, "\n") .. "\n"

                    -- Ensure data/ directory exists
                    os.execute("mkdir -p '" .. dataDir .. "'")

                    local f = io.open(luaPath, "w")
                    if not f then
                        error("ms.compiler: cannot open " .. luaPath .. " for writing")
                    end
                    f:write(out)
                    f:close()

                    return true
                end

                -- ── rebuild: read JSON, compile all, write Lua ────────────

                ms.compiler.rebuild = function()
                    -- Read JSON source file
                    local f = io.open(jsonPath, "r")
                    if not f then
                        error("ms.compiler.rebuild: cannot open " .. jsonPath)
                    end
                    local raw = f:read("*all")
                    f:close()

                    local ok, data = pcall(hs.json.decode, raw)
                    if not ok or type(data) ~= "table" then
                        error("ms.compiler.rebuild: invalid JSON in " .. jsonPath .. ": " .. tostring(data))
                    end

                    local macros = data.macros or {}
                    local sources = {}
                    local count = 0

                    for id, macroDef in pairs(macros) do
                        macroDef.id = id  -- ensure id is set
                        local srcOk, src = pcall(ms.compiler.compile, macroDef)
                        if not srcOk then
                            print("ms.compiler: compile error for '" .. id .. "': " .. tostring(src))
                            -- Write an error stub so the file is still valid Lua
                            src = "-- [COMPILE ERROR for " .. id .. "]\n"
                               .. "-- " .. tostring(src) .. "\n"
                        end
                        sources[#sources + 1] = { id = id, source = src }
                        count = count + 1
                    end

                    -- Sort by id for deterministic output
                    table.sort(sources, function(a, b) return a.id < b.id end)

                    ms.compiler._writeFile(sources)

                    print("ms.compiler.rebuild: compiled " .. count .. " macro(s) → " .. luaPath)
                    return count
                end

                -- ── load: execute the compiled file in the macro sandbox ──

                ms.compiler.load = function()
                    if not hs.fs.attributes(luaPath) then
                        print("ms.compiler.load: no compiled file at " .. luaPath .. " — skipping")
                        return false
                    end

                    local f = io.open(luaPath, "r")
                    if not f then
                        print("ms.compiler.load: cannot open " .. luaPath)
                        return false
                    end
                    local rawSrc = f:read("*all")
                    f:close()

                    -- Audit the compiled source (same as ms_macros.lua)
                    if ms.auditMacros then
                        local auditErrs = ms.auditMacros(rawSrc)
                        if #auditErrs > 0 then
                            local msg = "ms_macros_visual.lua failed security audit ("
                                .. #auditErrs .. " violation"
                                .. (#auditErrs > 1 and "s" or "") .. "):\n"
                            for _, e in ipairs(auditErrs) do
                                msg = msg .. "  • " .. e .. "\n"
                            end
                            print(msg)
                            ms.alert("Visual macros audit failed — see console", 6)
                            return false
                        end
                    end

                    -- Load into the macro sandbox
                    local sandbox = ms._macroSandbox
                    if not sandbox then
                        error("ms.compiler.load: macro sandbox not initialized")
                    end

                    local chunk, loadErr
                    if _VERSION and _VERSION >= "Lua 5.2" or not setfenv then
                        chunk, loadErr = load(rawSrc, "@ms_macros_visual.lua", "bt", sandbox)
                    else
                        chunk, loadErr = loadstring(rawSrc, "@ms_macros_visual.lua")
                        if chunk then setfenv(chunk, sandbox) end
                    end
                    if not chunk then
                        print("ms.compiler.load: failed to load: " .. tostring(loadErr))
                        ms.alert("Visual macros load error — see console", 6)
                        return false
                    end

                    local ok, runErr = pcall(chunk)
                    if not ok then
                        print("ms.compiler.load: execution error: " .. tostring(runErr))
                        ms.alert("Visual macros runtime error — see console", 6)
                        return false
                    end

                    print("ms.compiler.load: visual macros loaded into sandbox")
                    return true
                end

                -- ── write: compile a single macro and append/replace in file ──

                --- Compile one macro definition and merge it into the JSON + rebuild.
                ---@param macroId string   The macro identifier
                ---@param macroDef table   Full macro definition (name, author, bind, steps)
                ms.compiler.write = function(macroId, macroDef)
                    assert(type(macroId) == "string", "ms.compiler.write: macroId must be a string")
                    assert(type(macroDef) == "table",  "ms.compiler.write: macroDef must be a table")

                    macroDef.id = macroId

                    -- Read existing JSON
                    local data = { macros = {} }
                    local f = io.open(jsonPath, "r")
                    if f then
                        local raw = f:read("*all"); f:close()
                        local ok, parsed = pcall(hs.json.decode, raw)
                        if ok and type(parsed) == "table" then
                            data = parsed
                            data.macros = data.macros or {}
                        end
                    end

                    -- Upsert the macro
                    data.macros[macroId] = {
                        name     = macroDef.name,
                        author   = macroDef.author,
                        group    = macroDef.group,
                        bind     = macroDef.bind,
                        steps    = macroDef.steps,
                        cooldown = macroDef.cooldown,
                    }

                    -- Write updated JSON
                    os.execute("mkdir -p '" .. dataDir .. "'")
                    local jf = io.open(jsonPath, "w")
                    if not jf then
                        error("ms.compiler.write: cannot open " .. jsonPath .. " for writing")
                    end
                    jf:write(hs.json.encode(data, true))
                    jf:close()

                    -- Recompile everything
                    ms.compiler.rebuild()

                    print("ms.compiler.write: saved '" .. macroId .. "' to JSON and recompiled")
                    return true
                end

                -- ── delete: remove a macro from JSON and recompile ────────

                ms.compiler.delete = function(macroId)
                    assert(type(macroId) == "string", "ms.compiler.delete: macroId must be a string")

                    local f = io.open(jsonPath, "r")
                    if not f then
                        print("ms.compiler.delete: no JSON file found")
                        return false
                    end
                    local raw = f:read("*all"); f:close()
                    local ok, data = pcall(hs.json.decode, raw)
                    if not ok or type(data) ~= "table" then
                        error("ms.compiler.delete: invalid JSON")
                    end

                    data.macros = data.macros or {}
                    if not data.macros[macroId] then
                        print("ms.compiler.delete: macro '" .. macroId .. "' not found")
                        return false
                    end

                    data.macros[macroId] = nil

                    local jf = io.open(jsonPath, "w")
                    if not jf then
                        error("ms.compiler.delete: cannot write JSON")
                    end
                    jf:write(hs.json.encode(data, true))
                    jf:close()

                    ms.compiler.rebuild()
                    print("ms.compiler.delete: removed '" .. macroId .. "' and recompiled")
                    return true
                end

                -- ── list: return ids of all compiled visual macros ────────

                ms.compiler.list = function()
                    local f = io.open(jsonPath, "r")
                    if not f then return {} end
                    local raw = f:read("*all"); f:close()
                    local ok, data = pcall(hs.json.decode, raw)
                    if not ok or type(data) ~= "table" or type(data.macros) ~= "table" then
                        return {}
                    end
                    local ids = {}
                    for id in pairs(data.macros) do ids[#ids + 1] = id end
                    table.sort(ids)
                    return ids
                end

                -- ── get: return a single macro definition from JSON ───────

                ms.compiler.get = function(macroId)
                    local f = io.open(jsonPath, "r")
                    if not f then return nil end
                    local raw = f:read("*all"); f:close()
                    local ok, data = pcall(hs.json.decode, raw)
                    if not ok or type(data) ~= "table" or type(data.macros) ~= "table" then
                        return nil
                    end
                    local def = data.macros[macroId]
                    if def then def.id = macroId end
                    return def
                end

                -- ── paths: expose file locations ──────────────────────────

                ms.compiler.paths = {
                    json = jsonPath,
                    lua  = luaPath,
                    data = dataDir,
                }
            end
        -- END 13. Visual Macro Compiler (ms.compiler) --

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
                                    if bk == "updateById" or bk == "dismissById" then
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
            if def and not def.sub and ms.binds[id] == nil then
                ms.binds[id] = def.enabled
            end
        end
        ms._devArchiveLimit   = 15     -- overridden by loadSettings() if previously saved
        ms._loadComplete   = false  -- gates macro activation; set to true by _announceLoad
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
        ms.loadTheme()

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
        -- ms.legacycam.updateMultiplier()  -- opt-in: call manually if needed
        os.remove(os.getenv("HOME") .. "/.hammerspoon/data/.ms_update_pending")
        ms.bind._registerSystemBinds()
        ms.bind.rebind()
        ms.socdApply()
        BindValidity = 0  -- block macros during loading; _announceLoad re-enables when toasts fire
        ms._startupSoundDone = false  -- suppresses all non-load sounds until _announceLoad runs

        -- Loading Screen — Webview Creation --
            do
                local sf  = hs.screen.mainScreen():frame()
                local lw, lh = 300, 104
                local lx  = sf.x + math.floor((sf.w - lw) / 2)
                local ly  = sf.y + sf.h - 150 - lh

                local _ucLoad = hs.webview.usercontent.new("loadingScreen")
                _ucLoad:setCallback(function(message)
                    local ok, data = pcall(hs.json.decode, message.body)
                    if not ok or type(data) ~= "table" then return end
                end)

                local htmlPath = hs.configdir .. "/ui/ms_loading.html"
                local baseURL  = "file://" .. hs.configdir .. "/ui/"

                _lWebView = hs.webview.new({ x=lx, y=ly, w=lw, h=lh }, {}, _ucLoad)
                pcall(function() _lWebView:windowStyle(0) end)
                pcall(function() _lWebView:transparent(true) end)
                pcall(function() _lWebView:level(hs.canvas.windowLevels.popUpMenu or 25) end)
                pcall(function() _lWebView:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces) end)
                pcall(function() _lWebView:allowTextEntry(false) end)
                pcall(function() _lWebView:shadow(false) end)
                _lWebView:alpha(0)

                -- Replace buffer function with live function
                _lUpdate = function(pct, msg)
                    if not _lWebView then return end
                    local encoded = msg and ('"' .. msg:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n') .. '"') or "null"
                    local js = string.format("setProgress(%d, %s)", pct, encoded)
                    _lWebView:evaluateJavaScript(js)
                end

                local f = io.open(htmlPath, "r")
                if f then
                    local html = f:read("*all"); f:close()
                    _lWebView:html(html, baseURL)
                end

                -- Show and initialize after a short delay (let the webview render)
                _G._loadTimers = {}
                _G._loadTimers[1] = hs.timer.doAfter(0.05, function()
                    if not _lWebView then return end
                    -- Inject theme and state
                    local themeJson = hs.json.encode(ms._theme or {})
                    _lWebView:evaluateJavaScript("applyTheme(" .. themeJson .. ")")
                    -- Replay buffered messages
                    for _, entry in ipairs(_lMsgBuffer) do
                        local encoded = entry.msg and ('"' .. entry.msg:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n') .. '"') or "null"
                        _lWebView:evaluateJavaScript(string.format("setProgress(%d, %s)", entry.pct, encoded))
                    end
                    _lMsgBuffer = {}
                    -- Fade in
                    _lWebView:show()
                    -- Set macro name (after show, webview is now accepting JS)
                    if ms.macroMeta and ms.macroMeta.name then
                        _lWebView:evaluateJavaScript("setMacroName(" ..
                            '"' .. ms.macroMeta.name:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"' .. ")")
                    end
                    -- Set profile name
                    local profileName = (ms.macroMeta and ms.macroMeta.name) or ""
                    if profileName ~= "" then
                        _lWebView:evaluateJavaScript("setProfileName(" ..
                            '"' .. profileName:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"' .. ")")
                    end
                    pcall(function() ms.sound(SoundDefaultsDir .. "d_Reset.wav") end)
                    local step, steps = 0, 6
                    _G._loadTimers.fadeIn = hs.timer.doEvery((ms._theme.fadeMs or 100) / 1000 / steps, function()
                        step = step + 1
                        if _lWebView then _lWebView:alpha(step / steps) end
                        if step >= steps and _G._loadTimers.fadeIn then _G._loadTimers.fadeIn:stop(); _G._loadTimers.fadeIn = nil end
                    end)
                end)
            end
        -- END Loading Screen — Webview Creation --

        -- Loading Screen — Fade, Announce & Timers --
            _lUpdate(20, "Initializing\u{2026}")

            _lFadeOut = function()
                if not _lWebView or _lFadingOut then return end
                _lFadingOut = true
                local step, steps = 0, 6
                _G._loadTimers.fadeOut = hs.timer.doEvery((ms._theme.fadeMs or 100) / 1000 / steps, function()
                    step = step + 1
                    if _lWebView then _lWebView:alpha(1 - (step / steps)) end
                    if step >= steps then
                        if _G._loadTimers.fadeOut then _G._loadTimers.fadeOut:stop(); _G._loadTimers.fadeOut = nil end
                        if _lWebView then _lWebView:delete(); _lWebView = nil end
                        _G._loadTimers.announce = hs.timer.doAfter(0.1, _announceLoad)
                    end
                end)
            end

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
                    -- Re-inject theme now that MsSettings has loaded it
                    if _lWebView then
                        local themeJson = hs.json.encode(ms._theme or {})
                        _lWebView:evaluateJavaScript("applyTheme(" .. themeJson .. ")")
                    end
                    ms._loadComplete = true
                    ms.dev.log({ type = "system", event = "startup_complete" })
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
                _lUpdate(25, "Building UI state cache\u{2026}")
            end)
            _G._timers[2] = hs.timer.doAfter(t1, function()
                print("[startup] t=" .. t1 .. ": prep settings")
                _lUpdate(32, "Preparing settings panel\u{2026}")
            end)
            _G._timers[3] = hs.timer.doAfter(t2, function()
                print("[startup] t=" .. t2 .. ": prewarm")
                pcall(function() ms.ui.prewarm() end)
                _lUpdate(40, "Loading settings panel\u{2026}")
            end)
            _G._timers[4] = hs.timer.doAfter(t3, function()
                print("[startup] t=" .. t3 .. ": theme")
                _lUpdate(48, "Applying theme\u{2026}")
                pcall(function()
                    if _lWebView then
                        local themeJson = hs.json.encode(ms._theme or {})
                        _lWebView:evaluateJavaScript("applyTheme(" .. themeJson .. ")")
                    end
                end)
                pcall(function() ms.playSlot("themeLoaded") end)
            end)
            _G._timers[5] = hs.timer.doAfter(t4, function()
                print("[startup] t=" .. t4 .. ": integrity seed")
                _lUpdate(55, "Seeding integrity hash\u{2026}")
            end)
            _G._timers[6] = hs.timer.doAfter(t5, function()
                print("[startup] t=" .. t5 .. ": console")
                _lUpdate(62, "Loading console\u{2026}")
                _G._timers[60] = hs.timer.doAfter(0, function()
                    pcall(function() ms.dev.prewarmStep("console") end)
                end)
            end)
            _G._timers[7] = hs.timer.doAfter(t6, function()
                print("[startup] t=" .. t6 .. ": watcher")
                _lUpdate(72, "Loading macro monitor\u{2026}")
                _G._timers[70] = hs.timer.doAfter(0, function()
                    pcall(function() ms.dev.prewarmStep("watcher") end)
                end)
            end)
            _G._timers[8] = hs.timer.doAfter(t7, function()
                print("[startup] t=" .. t7 .. ": keys")
                _lUpdate(82, "Loading input monitor\u{2026}")
                _G._timers[80] = hs.timer.doAfter(0, function()
                    pcall(function() ms.dev.prewarmStep("keys") end)
                end)
            end)
            _G._timers[9] = hs.timer.doAfter(t8, function()
                print("[startup] t=" .. t8 .. ": window")
                _lUpdate(90, "Loading window monitor\u{2026}")
                _G._timers[90] = hs.timer.doAfter(0, function()
                    pcall(function() ms.dev.prewarmStep("window") end)
                end)
            end)
            _G._timers[10] = hs.timer.doAfter(t9, function()
                print("[startup] t=" .. t9 .. ": finalize")
                if not _lFadingOut then _lUpdate(96, "Finalizing\u{2026}") end
            end)
            _G._timers[11] = hs.timer.doAfter(t10, function()
                print("[startup] t=" .. t10 .. ": fade start")
                if not _lFadingOut then
                    _lUpdate(100, "Ready.")
                    _G._timers[12] = hs.timer.doAfter(0.8, function()
                        print("[startup] fade out")
                        pcall(function() _lFadeOut() end)
                    end)
                end
            end)
            _G._timers.guard = hs.timer.doAfter(8, function()
                print("[startup] t=8: GUARD fired")
                pcall(function()
                    if _lWebView and not _lFadingOut then _lFadeOut() end
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
        -- END Startup Loading Indicator --
    -- END Startup Executions --
-- END Core System --
