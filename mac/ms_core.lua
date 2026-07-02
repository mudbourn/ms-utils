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

            -- MsCamera (camera engine) --
                _lUpdate(12, "Configuring Camera\u{2026}")
                local _msCamOk, _msCamErr = pcall(function()
                    hs.loadSpoon("MsCamera")
                end)

                if not _msCamOk then
                    print("MsCamera: load failed — " .. tostring(_msCamErr))
                end

                if spoon.MsCamera then
                    ms.legacycam = spoon.MsCamera
                    -- ms.legacycam._setupWatcher()  -- opt-in: call manually if needed
                else
                    ms.legacycam = {
                        anchor     = nil,
                        button     = 5,
                        cachedMult = 1.0,
                        updateMultiplier = function() end,
                        updateAnchor     = function() end,
                        scheduleUpdate   = function() end,
                        enable           = function() end,
                        disable          = function() end,
                        move             = function() end,
                        _setupWatcher    = function() end,
                    }

                    print("MsCamera: running without camera engine (spoon not loaded)")
                end

                -- ms.legacycam available as fallback
                -- ms.cam is the primary camera engine
            -- END MsCamera (camera engine) --

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
            roblox = hs.application.get("Roblox")

            ms._targetApp     = "Roblox"
            ms._targetHandle  = hs.application.get(ms._targetApp)
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
            REF_W = 1680
            REF_H = 1044
            REF_SENS = 1.5
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
                    radius       = 2,
                    windowRadius = 3,
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
                    pcall(function()
                        local r = (ms._theme and ms._theme.windowRadius)
                            or (ms._themeDefaults and ms._themeDefaults.windowRadius)
                            or 3
                        if r > 0 then
                            panel:transparent(true)
                        end
                    end)
                end

                --- Push updated --ms-window-radius CSS variable into a live webview panel.
                --- Safe to call on any panel that was built with applyWindowRadius.
                ms.theme._pushWindowRadius = function(panel)
                    pcall(function()
                        local r = (ms._theme and ms._theme.windowRadius) or 3
                        local js = string.format(
                            "document.documentElement.style.setProperty('--ms-window-radius','%dpx')",
                            r
                        )
                        panel:evaluateJavaScript(js)
                    end)
                end

                --- Register a callback to fire whenever the theme changes (live-update).
                --- Returns an ID that can be passed to _unwatchTheme.
                ms.theme._watchers = ms.theme._watchers or {}
                ms.theme._nextWatcherId = ms.theme._nextWatcherId or 1

                ms.theme.onChanged = function(fn)
                    local id = ms.theme._nextWatcherId
                    ms.theme._nextWatcherId = id + 1
                    ms.theme._watchers[id] = fn
                    return id
                end

                ms.theme._unwatch = function(id)
                    ms.theme._watchers[id] = nil
                end

                --- Fire all registered theme-changed watchers.
                --- Call this from wherever the theme is reloaded/re-applied.
                ms.theme._fireChanged = function()
                    for _, fn in pairs(ms.theme._watchers) do
                        pcall(fn)
                    end
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
                    local roblox = hs.application.get("Roblox")
                    if roblox then
                        ms._robloxActive = true

                        local hs_app = hs.application.get("Hammerspoon")
                        if hs_app then hs_app:activate() end

                        hs.timer.doAfter(0.25, function()
                            local app = hs.application.get("Roblox") or roblox
                            local ok, win = pcall(function() return app:mainWindow() end)
                            if ok and win then pcall(function() win:focus() end) end
                            pcall(function() app:activate() end)
                        end)
                    end
                end)
        -- END 1. State & Config --

        -- 2. Settings, Profiles & UI --
            ms.app = function() return hs.application.frontmostApplication():name() end

            ms._menubar = ms._menubar or hs.menubar.new()
            ms._menubar:setClickCallback(function() ms.ui.toggle() end)
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
                                            print("ms.key dispatch: firing " .. (binding.system and "SYSTEM" or "normal") .. " bind, BindValidity=" .. BindValidity)
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


                ms.press = function(key, mods, hidinject)
                    if ms.dev then spoon.MsDevTools:flushAll() end
                    if ms.dev._watcherPanel and not spoon.MsDevTools:getTraceSuppress() then
                        local modsStr = (mods and #mods > 0) and (" [" .. table.concat(mods, "+") .. "]") or ""
                        spoon.MsDevTools:watcherStep("↓ " .. tostring(key) .. modsStr)
                    end
                    if ms.dev then
                        local modsStr = (mods and #mods > 0) and (" [" .. table.concat(mods, "+") .. "]") or ""
                        spoon.MsDevTools:macroLog("↓ " .. tostring(key) .. modsStr)
                    end
                    local keyCode = getCode(key)
                    if not keyCode then
                        print("Error: Could not find keyCode for " .. tostring(key))
                        return
                    end
                    ms._macroHeldKeys[keyCode] = { mods = mods or {}, hidinject = hidinject }
                    local ev = hs.eventtap.event.newKeyEvent(mods or {}, keyCode, true)
                    if hidinject then
                        local app = hs.application.get("Roblox")
                        if app then ev:post(app); return end
                    end
                    ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                    ev:post()
                end

                ms.release = function(key, mods, hidinject)
                    if ms.dev then spoon.MsDevTools:flushAll() end
                    if ms.dev._watcherPanel and not spoon.MsDevTools:getTraceSuppress() then
                        spoon.MsDevTools:watcherStep("↑ " .. tostring(key))
                    end
                    if ms.dev then
                        spoon.MsDevTools:macroLog("↑ " .. tostring(key))
                    end
                    local keyCode = getCode(key)
                    if not keyCode then return end
                    ms._macroHeldKeys[keyCode] = nil
                    local ev = hs.eventtap.event.newKeyEvent(mods or {}, keyCode, false)
                    if hidinject then
                        local app = hs.application.get("Roblox")
                        if app then ev:post(app); return end
                    end
                    ev:setProperty(hs.eventtap.event.properties.eventSourceUserData, 999)
                    ev:post()
                end

                ms.type = function(key, mods, hidinject, holdMs)
                    if ms.dev then spoon.MsDevTools:flushAll() end
                    if ms.dev._watcherPanel then
                        local modsStr = (mods and #mods > 0) and (" [" .. table.concat(mods, "+") .. "]") or ""
                        spoon.MsDevTools:watcherStep("type " .. tostring(key) .. modsStr)
                    end
                    if ms.dev then
                        local modsStr = (mods and #mods > 0) and (" [" .. table.concat(mods, "+") .. "]") or ""
                        spoon.MsDevTools:macroLog("type " .. tostring(key) .. modsStr)
                    end
                    local _saved = spoon.MsDevTools:getTraceSuppress()
                    spoon.MsDevTools:setTraceSuppress(true)
                    ms.press(key, mods, hidinject)
                    ms.wait(holdMs or 15)
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
                                local app = hs.application.get("Roblox")
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
                if ms.dev._watcherPanel then
                    spoon.MsDevTools:watcherStep("Mouse " .. tostring(operation) .. " " .. tostring(button))
                end
                if ms.dev then
                    spoon.MsDevTools:macroLog("Mouse " .. tostring(operation) .. " " .. tostring(button))
                end
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

                local btn  = BTNS[button]
                local _app = hidinject and hs.application.get("Roblox") or nil

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

            ms.cam = setmetatable({}, {
                __call = function(_, dx, dy)
                    dx = math.floor(dx + 0.5)
                    dy = math.floor(dy + 0.5)
                    local pos = hs.mouse.absolutePosition()
                    local ev  = hs.eventtap.event.newMouseEvent(_camEvType, pos)
                    ev:setProperty(_camBtn, 5)
                    ev:setProperty(_camDx, dx)
                    ev:setProperty(_camDy, dy)
                    ev:post()
                    if not _camRebalancing then
                        _camTotalX = _camTotalX + dx
                        _camTotalY = _camTotalY + dy
                    end
                end,
            })

            ms.cam.rebalance = function()
                if _camTotalX == 0 and _camTotalY == 0 then return end
                _camRebalancing = true
                ms.cam(-_camTotalX, -_camTotalY)
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
                return hs.timer.doAfter(ms_time / 1000, fn)
            end

            ms.wait = function(ms_time)
                local co = coroutine.running()
                if co then
                    local ctx = ms._coroContext[co]
                    if ms.dev then spoon.MsDevTools:flushCam() end

                    if ms.dev then
                        spoon.MsDevTools:accWait(tonumber(ms_time) or 0)
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
                            if ms.dev then spoon.MsDevTools:flushAll() end
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
                local win = ms.getRobloxWin() or hs.window.find("Roblox")
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
                    if appName == "Roblox" then
                        local fromDialog = ms._inputOpen
                        ms._inputOpen = false
                        ms._robloxActive = true
                        ms.dev.log({ type = "system", event = "roblox_focus", fromDialog = fromDialog or false })
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
                        ms.dev.log({ type = "system", event = "roblox_blur", to = appName })
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

            hs.hotkey.bind({ "alt" }, "F10", function()
                if not ms._loadComplete then return end
                if not ms._robloxActive then return end
                ms.setMacros(0)
            end)

            hs.hotkey.bind({"alt"}, "[", function()
                if not ms._loadComplete then return end
                ms.quickReload()
            end)

            hs.hotkey.bind({"alt"}, "]", function()
                if not ms._loadComplete then return end
                hs.reload()
            end)

            hs.hotkey.bind({ "alt" }, "p", function()
                if not ms._loadComplete then return end
                if not ms._robloxActive then return end
                ms.ui.toggle()
            end)
        -- END 7. Macro Bind Controller --

        -- 8. Utilities --
            ms.fn = function(fn, async)
                assert(type(fn) == "function", "ms.fn: fn must be a function")
                if async == false then return fn end

                return function(...)
                    local ctx = {
                        cancelled = false,
                        paused    = false,
                        label     = ms._pendingLabel or "macro",
                    }
                    local label = ms._pendingLabel or "macro"
                    ms._pendingLabel = nil

                    local coBody = function(...)
                        local xok, xerr = xpcall(fn, debug.traceback, ...)
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
                        if ms.dev then spoon.MsDevTools:flushAll() end
                    end
                end
            end

            ms.pause = function(id)
                if not id then
                    for _, ctx in pairs(ms._activeContexts) do ctx.paused = true end
                    return
                end
                for _, ctx in pairs(ms._activeContexts) do
                    if ctx.label == id then ctx.paused = true; return end
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
                        print("═══ ms.resume error [" .. (ctx.label or "?") .. "] ═══\n" .. tostring(err))
                    end
                    if coroutine.status(co) == "dead" then
                        if ms.dev then spoon.MsDevTools:stopTrace(co) end
                        ms._coroContext[co] = nil
                        ms._activeContexts[ctx] = nil
                        if ms.dev then spoon.MsDevTools:flushAll() end
                    end
                end
                if not id then
                    for co in pairs(ms._coroContext) do _resume(co) end
                    return
                end
                for co, ctx in pairs(ms._coroContext) do
                    if ctx.label == id then _resume(co); return end
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
                        local app = hs.application.get("Roblox")
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
            ms._discoverSounds = function()
                if not ms._soundsDirty then return end
                ms._soundsDirty = false
                ms.sounds      = {}
                ms.macroSounds = {}

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
                            ms.dev.log({ type = "sound", msg = fname, category = "macro" })
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
                startup      = { "LoadStart", "Load Start" },
                load         = { "LoadEnd",   "Load End"   },
                launch       = { "Launch" },
                themeLoaded  = { "ThemeLoaded", "Theme Loaded" },
                updateAvailable = { "UpdateAvailable", "Update Available" },
            }
            ms.playSlot = function(slotId)
                if not ms.soundEnabled then return false end
                if not ms._startupSoundDone and slotId ~= "load" and slotId ~= "startup" and slotId ~= "themeLoaded" and slotId ~= "updateAvailable" then return false end
                ms._slotHandles = ms._slotHandles or {}
                -- Stop any currently-playing instance of this slot and replay on top
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
                        ms.systemBinds._handles[id] = ms.key(c.mods, c.key, false, function()
                            if not ms._robloxActive then return end
                            local co = coroutine.create(action)
                            local ok, err = coroutine.resume(co)
                            if not ok then print("ms.systemBind error: " .. tostring(err)) end
                        end, nil, true)
                    elseif c.type == "mouse" then
                        ms.systemBinds._handles[id] = ms.mouse(c.button, false, function()
                            if not ms._robloxActive then return end
                            local co = coroutine.create(action)
                            local ok, err = coroutine.resume(co)
                            if not ok then print("ms.systemBind error: " .. tostring(err)) end
                        end, true)
                    elseif c.type == "scroll" then
                        ms.systemBinds._handles[id] = ms.scrollBind(c.direction, function()
                            if not ms._robloxActive then return end
                            local co = coroutine.create(action)
                            local ok, err = coroutine.resume(co)
                            if not ok then print("ms.systemBind error: " .. tostring(err)) end
                        end)
                    elseif c.type == "gamepad" then
                        ms.systemBinds._handles[id] = ms.gamepadBind(c.button, function()
                            if not ms._robloxActive then return end
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
                        ms._systemBindHandles[id] = ms.key(c.mods, c.key, false, function()
                            if not ms._robloxActive then return end
                            local co = coroutine.create(fn)
                            local ok, err = coroutine.resume(co)
                            if not ok then print("ms.systemBind error: " .. tostring(err)) end
                        end, nil, true)
                    elseif c.type == "mouse" then
                        ms._systemBindHandles[id] = ms.mouse(c.button, false, function()
                            if not ms._robloxActive then return end
                            local co = coroutine.create(fn)
                            local ok, err = coroutine.resume(co)
                            if not ok then print("ms.systemBind error: " .. tostring(err)) end
                        end, true)
                    elseif c.type == "scroll" then
                        ms._systemBindHandles[id] = ms.scrollBind(c.direction, function()
                            if not ms._robloxActive then return end
                            local co = coroutine.create(fn)
                            local ok, err = coroutine.resume(co)
                            if not ok then print("ms.systemBind error: " .. tostring(err)) end
                        end)
                    elseif c.type == "gamepad" then
                        ms._systemBindHandles[id] = ms.gamepadBind(c.button, function()
                            if not ms._robloxActive then return end
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
                            while leftPhysicallyHeld and BindValidity == 1 do ms.wait(10) end
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
                            while rightPhysicallyHeld and BindValidity == 1 do ms.wait(10) end
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
            do
                local _busSubs = {}  -- [topic] = { [fn] = true, ... }

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
                    local subs = _busSubs[topic]
                    if not subs then return end
                    for fn, _ in pairs(subs) do
                        local ok, err = pcall(fn, payload)
                        if not ok then
                            print("ms.bus handler error [" .. topic .. "]: " .. tostring(err))
                        end
                    end
                end

                ms.bus._subscribers = _busSubs  -- privileged debug accessor
            end
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
                local _shellView     = nil   -- hs.webview instance
                local _shellChannel  = nil   -- hs.webview.usercontent instance
                local _shellReady    = false
                local _shellEvalQ    = {}    -- queued JS calls before ready

                ms.shell = {}

                -- ms.shell.eval(js) — push JS into the shell webview
                -- Replaces per-Spoon panel:evaluateJavaScript(...) pattern
                ms.shell.eval = function(js)
                    if type(js) ~= "string" then return end
                    if _shellView and _shellReady then
                        pcall(function() _shellView:evaluateJavaScript(js) end)
                    else
                        _shellEvalQ[#_shellEvalQ + 1] = js
                    end
                end

                -- ms.shell.isReady() — check if shell webview has loaded
                ms.shell.isReady = function()
                    return _shellReady
                end

                -- ms.shell.webview() — get the raw hs.webview (privileged)
                ms.shell.webview = function()
                    return _shellView
                end

                -- ms.shell.init() — create the shell webview + channel (hidden)
                ms.shell.init = function()
                    if _shellView then return end
                    require("hs.webview")
                    require("hs.webview.usercontent")

                    _shellChannel = hs.webview.usercontent.new("msShell")
                    _shellChannel:setCallback(function(message)
                        local ok, data = pcall(hs.json.decode, message.body)
                        if not ok or type(data) ~= "table" then return end
                        local panel  = data.panel  or "_shell"
                        local action = data.action or "unknown"
                        local body   = data.body
                        -- Route ready signal
                        if panel == "_shell" and action == "ready" then
                            _shellReady = true
                            -- Flush queued JS
                            for _, js in ipairs(_shellEvalQ) do
                                pcall(function() _shellView:evaluateJavaScript(js) end)
                            end
                            _shellEvalQ = {}
                        end
                        -- Route pop-out/pop-in requests from JS
                        if panel == "_shell" and action == "popOut" and body and body.panel then
                            pcall(function() ms.shell.popOut(body.panel) end)
                            return
                        end
                        if panel == "_shell" and action == "popIn" and body and body.panel then
                            pcall(function() ms.shell.popIn(body.panel) end)
                            return
                        end
                        -- Emit on the bus: ui:<panel>:<action>
                        if ms.bus then
                            ms.bus.emit("ui:" .. panel .. ":" .. action, body)
                        end
                    end)

                    local sf = hs.screen.mainScreen():frame()
                    local w, h = 900, 600
                    local x = sf.x + math.floor((sf.w - w) / 2)
                    local y = sf.y + math.floor((sf.h - h) / 2)

                    _shellView = hs.webview.new({ x = x, y = y, w = w, h = h }, {}, _shellChannel)
                    pcall(function() _shellView:windowStyle(1 + 2 + 4) end)  -- titled + closable + miniaturizable
                    pcall(function() _shellView:level(hs.canvas.windowLevels.normal or 4) end)
                    pcall(function() _shellView:allowTextEntry(true) end)
                    pcall(function() _shellView:shadow(true) end)
                    _shellView:alpha(0)

                    local htmlPath = hs.configdir .. "/ui/ms_shell.html"
                    local baseURL  = "file://" .. hs.configdir .. "/ui/"
                    local f = io.open(htmlPath, "r")
                    if f then
                        local html = f:read("*all"); f:close()
                        _shellView:html(html, baseURL)
                    else
                        print("ms.shell: cannot open " .. htmlPath)
                    end

                    -- Inject theme
                    hs.timer.doAfter(0.05, function()
                        if not _shellView then return end
                        local themeJson = hs.json.encode(ms._theme or {})
                        _shellView:evaluateJavaScript("applyTheme(" .. themeJson .. ")")
                    end)
                end

                -- ms.shell.show() / hide() / toggle()
                ms.shell.show = function()
                    if not _shellView then ms.shell.init() end
                    _shellView:show()
                    _shellView:alpha(1)
                    if ms.bus then ms.bus.emit("macroLab:toggled", { visible = true }) end
                end

                ms.shell.hide = function()
                    if _shellView then
                        _shellView:hide()
                        _shellView:alpha(0)
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

                -- ms.shell.destroy() — tear down the shell webview
                ms.shell.destroy = function()
                    if _shellView then
                        pcall(function() _shellView:delete() end)
                        _shellView = nil
                    end
                    _shellChannel  = nil
                    _shellReady    = false
                    _shellEvalQ    = {}
                end

                -- Panel Registry & Mounting --

                local _panelRegistry = {}  -- [id] = config
                local _popouts      = {}  -- [id] = { view, channel }

                -- ms.shell.registerPanel(id, config)
                -- Register a panel module with the shell.
                -- config: { title, icon, htmlPath (relative to ui/), onLoad, onUnload }
                ms.shell.registerPanel = function(id, config)
                    assert(type(id) == "string", "registerPanel: id must be string")
                    assert(type(config) == "table", "registerPanel: config must be table")
                    config.id = id
                    _panelRegistry[id] = config
                    -- Tell the shell to add a rail item if it's ready
                    if _shellReady then
                        -- Build JSON manually (config may contain non-serializable functions)
                        local railJson = '{"id":' .. hs.json.encode(id)
                            .. ',"title":' .. hs.json.encode(config.title or id)
                            .. ',"icon":' .. hs.json.encode(config.icon or "▪") .. '}'
                        ms.shell.eval("PanelManager.addRailItem(" .. railJson .. ")")
                    end
                end

                -- ms.shell.mountPanel(id)
                -- Mount a registered panel into the shell content area.
                -- Loads the panel's HTML into an iframe inside its slot.
                ms.shell.mountPanel = function(id)
                    local cfg = _panelRegistry[id]
                    if not cfg then
                        print("ms.shell.mountPanel: unknown panel '" .. tostring(id) .. "'")
                        return false
                    end

                    -- Read panel HTML
                    local htmlContent = nil
                    if cfg.htmlPath then
                        local fullPath = hs.configdir .. "/ui/" .. cfg.htmlPath
                        local fh = io.open(fullPath, "r")
                        if fh then
                            htmlContent = fh:read("*all")
                            fh:close()
                        else
                            print("ms.shell.mountPanel: cannot read " .. fullPath)
                            return false
                        end
                    end

                    -- Escape HTML for safe JS embedding via JSON encoding
                    local baseURL     = "file://" .. hs.configdir .. "/ui/"
                    local idJson      = hs.json.encode(id)
                    local htmlJson    = htmlContent and hs.json.encode(htmlContent) or "\"\""
                    local baseURLJson = hs.json.encode(baseURL)
                    local js = "PanelManager.mount(" .. idJson .. "," .. htmlJson .. "," .. baseURLJson .. ")"
                    ms.shell.eval(js)

                    -- Call onLoad callback
                    if cfg.onLoad then pcall(cfg.onLoad) end

                    -- Emit bus event
                    if ms.bus then ms.bus.emit("panel:opened", { id = id }) end
                    return true
                end

                -- ms.shell.unmountPanel(id)
                -- Unmount a panel from the shell content area.
                ms.shell.unmountPanel = function(id)
                    local cfg = _panelRegistry[id]
                    if not cfg then return false end

                    ms.shell.eval("PanelManager.unmount(" .. hs.json.encode(id) .. ")")

                    if cfg.onUnload then pcall(cfg.onUnload) end
                    if ms.bus then ms.bus.emit("panel:closed", { id = id }) end
                    return true
                end

                -- Panel name → HTML file mapping for built-in panels
                local _builtinPanels = {
                    console  = "ms_console.html",
                    watcher  = "ms_watcher.html",
                    keys     = "ms_keys.html",
                    window   = "ms_window.html",
                    settings = "ms_settings_ui.html",
                    macros   = nil,  -- macros is shell-internal, no standalone HTML
                }

                -- ms.shell.popOut(panelId)
                -- Unmount from shell, create a standalone webview with the same HTML.
                ms.shell.popOut = function(panelId)
                    -- Auto-register built-in panels if not explicitly registered
                    if not _panelRegistry[panelId] and _builtinPanels[panelId] then
                        _panelRegistry[panelId] = {
                            id = panelId,
                            title = panelId,
                            icon = "▪",
                            htmlPath = _builtinPanels[panelId],
                        }
                    end

                    local cfg = _panelRegistry[panelId]
                    if not cfg then
                        print("ms.shell.popOut: unknown panel '" .. tostring(panelId) .. "'")
                        return false
                    end
                    if not cfg.htmlPath then
                        print("ms.shell.popOut: panel '" .. tostring(panelId) .. "' has no standalone HTML")
                        return false
                    end
                    if _popouts[panelId] then
                        -- Already popped out — just focus it
                        pcall(function() _popouts[panelId].view:show() end)
                        return true
                    end

                    -- Unmount from shell first
                    ms.shell.unmountPanel(panelId)

                    -- Create standalone webview
                    require("hs.webview")
                    require("hs.webview.usercontent")

                    local popChannel = hs.webview.usercontent.new("msShell")
                    popChannel:setCallback(function(message)
                        local ok, data = pcall(hs.json.decode, message.body)
                        if not ok or type(data) ~= "table" then return end
                        local panel  = data.panel  or panelId
                        local action = data.action or "unknown"
                        local body   = data.body
                        if ms.bus then
                            ms.bus.emit("ui:" .. panel .. ":" .. action, body)
                        end
                    end)

                    local sf = hs.screen.mainScreen():frame()
                    local w, h = 800, 500
                    local x = sf.x + math.floor((sf.w - w) / 2) + 40
                    local y = sf.y + math.floor((sf.h - h) / 2) + 40

                    local popView = hs.webview.new({ x = x, y = y, w = w, h = h }, {}, popChannel)
                    pcall(function() popView:windowStyle(1 + 2 + 4) end)
                    pcall(function() popView:level(hs.canvas.windowLevels.normal or 4) end)
                    pcall(function() popView:allowTextEntry(true) end)
                    pcall(function() popView:shadow(true) end)

                    local htmlPath = hs.configdir .. "/ui/" .. (cfg.htmlPath or "")
                    local baseURL  = "file://" .. hs.configdir .. "/ui/"
                    local fh = io.open(htmlPath, "r")
                    if fh then
                        local html = fh:read("*all"); fh:close()
                        popView:html(html, baseURL)
                    end

                    -- Inject theme
                    hs.timer.doAfter(0.05, function()
                        if not popView then return end
                        local themeJson = hs.json.encode(ms._theme or {})
                        pcall(function() popView:evaluateJavaScript("applyTheme(" .. themeJson .. ")") end)
                    end)

                    popView:show()
                    popView:alpha(1)

                    _popouts[panelId] = { view = popView, channel = popChannel }

                    -- Notify shell that panel was popped out
                    ms.shell.eval("PanelManager.markPoppedOut(" .. hs.json.encode(panelId) .. ", true)")

                    if ms.bus then ms.bus.emit("panel:poppedOut", { id = panelId }) end
                    return true
                end

                -- ms.shell.popIn(panelId)
                -- Destroy standalone webview, remount in shell.
                ms.shell.popIn = function(panelId)
                    local pop = _popouts[panelId]
                    if not pop then
                        print("ms.shell.popIn: panel '" .. tostring(panelId) .. "' is not popped out")
                        return false
                    end

                    -- Destroy standalone webview
                    pcall(function() pop.view:delete() end)
                    _popouts[panelId] = nil

                    -- Notify shell
                    ms.shell.eval("PanelManager.markPoppedOut(" .. hs.json.encode(panelId) .. ", false)")

                    -- Remount in shell
                    ms.shell.mountPanel(panelId)

                    if ms.bus then ms.bus.emit("panel:poppedIn", { id = panelId }) end
                    return true
                end

                -- ms.shell.isPoppedOut(panelId) — check if panel is in standalone mode
                ms.shell.isPoppedOut = function(panelId)
                    return _popouts[panelId] ~= nil
                end
            end
        -- END 12. Shell Infrastructure (ms.shell) --

        -- 12b. Visual Macro Compiler (ms.compiler) --
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

                emitters["if"] = function(step, lvl)
                    local cond = step.condition or "true"
                    local lines = {}
                    lines[#lines + 1] = indent(lvl) .. "if " .. cond .. " then"
                    if step.then_steps then
                        for _, s in ipairs(step.then_steps) do
                            lines[#lines + 1] = emitStep(s, lvl + 1)
                        end
                    end
                    if step.else_steps then
                        lines[#lines + 1] = indent(lvl) .. "else"
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
                    lines[#lines + 1] = indent(lvl) .. "for " .. varName .. " = " .. forArgs .. " do"
                    if step.body then
                        for _, s in ipairs(step.body) do
                            lines[#lines + 1] = emitStep(s, lvl + 1)
                        end
                    end
                    lines[#lines + 1] = indent(lvl) .. "end"
                    return table.concat(lines, "\n")
                end

                emitters["while"] = function(step, lvl)
                    local cond = step.condition or "true"
                    local lines = {}
                    lines[#lines + 1] = indent(lvl) .. "while " .. cond .. " do"
                    if step.body then
                        for _, s in ipairs(step.body) do
                            lines[#lines + 1] = emitStep(s, lvl + 1)
                        end
                    end
                    lines[#lines + 1] = indent(lvl) .. "end"
                    return table.concat(lines, "\n")
                end

                emitters["repeat"] = function(step, lvl)
                    local cond = step.condition or "true"
                    local lines = {}
                    lines[#lines + 1] = indent(lvl) .. "repeat"
                    if step.body then
                        for _, s in ipairs(step.body) do
                            lines[#lines + 1] = emitStep(s, lvl + 1)
                        end
                    end
                    lines[#lines + 1] = indent(lvl) .. "until " .. cond
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
                    lines[#lines + 1] = "end)"
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
        -- END 12b. Visual Macro Compiler (ms.compiler) --
        -- 12c. Macro Lab Shell ↔ Compiler bridge --
            do
                -- This bridge handles messages from the Step Canvas in ms_shell.html
                -- and routes them to ms.compiler, pushing results back to JS.
                -- It must run AFTER both ms.compiler and ms.bus are initialized.

                local function _macroShellEval(js)
                    if ms.shell and ms.shell.eval then
                        ms.shell.eval(js)
                    end
                end

                -- listMacros → push array of IDs back to JS
                if ms.bus then
                    ms.bus.on("ui:macros:listMacros", function(body)
                        local ids = ms.compiler.list()
                        local json = hs.json.encode(ids)
                        _macroShellEval("if(window.macroLab)macroLab.setMacroList(" .. json .. ")")
                    end)

                    -- getMacro → push full definition back to JS
                    ms.bus.on("ui:macros:getMacro", function(body)
                        if not body or not body.id then return end
                        local def = ms.compiler.get(body.id)
                        if def then
                            local json = hs.json.encode(def)
                            _macroShellEval("if(window.macroLab)macroLab.setMacroDef(" .. json .. ")")
                        end
                    end)

                    -- saveMacro → write to compiler and confirm
                    ms.bus.on("ui:macros:saveMacro", function(body)
                        if not body or not body.id or not body.def then return end
                        local ok, err = pcall(ms.compiler.write, body.id, body.def)
                        if ok then
                            _macroShellEval("shellDispatch('macros','macroSaved',{})")
                        else
                            print("ms.compiler.saveMacro error: " .. tostring(err))
                        end
                    end)

                    -- deleteMacro → remove and confirm
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
        -- END 12c. Macro Lab Shell ↔ Compiler bridge --

        -- 12d. Test Run & Record Mode --
            do
                local function _testShellEval(js)
                    if ms.shell and ms.shell.eval then
                        ms.shell.eval(js)
                    end
                end

                -- ── Test Run ──────────────────────────────────────────────
                -- Compiles and executes a macro definition in the sandbox.
                -- Returns (ok:bool, err:string|nil)

                ms.shell._testRun = function(macroDef)
                    if not macroDef or type(macroDef) ~= "table" then
                        return false, "Invalid macro definition"
                    end
                    if not macroDef.id or type(macroDef.id) ~= "string" then
                        -- Generate a temporary id for test runs
                        macroDef.id = "_testRun_" .. tostring(math.random(100000, 999999))
                    end
                    if not macroDef.steps then macroDef.steps = {} end

                    -- Compile
                    local compileOk, src = pcall(ms.compiler.compile, macroDef)
                    if not compileOk then
                        return false, "Compile error: " .. tostring(src)
                    end

                    -- Load into sandbox
                    local sandbox = ms._macroSandbox
                    if not sandbox then
                        return false, "Macro sandbox not initialized"
                    end

                    local chunk, loadErr
                    if _VERSION and _VERSION >= "Lua 5.2" or not setfenv then
                        chunk, loadErr = load(src, "@testRun_" .. macroDef.id, "bt", sandbox)
                    else
                        chunk, loadErr = loadstring(src, "@testRun_" .. macroDef.id)
                        if chunk then setfenv(chunk, sandbox) end
                    end
                    if not chunk then
                        return false, "Load error: " .. tostring(loadErr)
                    end

                    -- Execute (pcall-wrapped)
                    local runOk, runErr = pcall(chunk)
                    if not runOk then
                        return false, "Runtime error: " .. tostring(runErr)
                    end

                    return true, nil
                end

                -- ── Record Mode ──────────────────────────────────────────

                local _recordTap      = nil
                local _recording      = false
                local _lastEventTime  = nil
                local _waitThreshold  = 0.05  -- 50ms default
                local _recordMouseMoves = false  -- off by default

                -- Key code → ms key name (macOS virtual key codes)
                local _keyCodeMap = {
                    [0x00] = "a", [0x01] = "s", [0x02] = "d", [0x03] = "f",
                    [0x04] = "h", [0x05] = "g", [0x06] = "z", [0x07] = "x",
                    [0x08] = "c", [0x09] = "v", [0x0B] = "b", [0x0C] = "q",
                    [0x0D] = "w", [0x0E] = "e", [0x0F] = "r", [0x10] = "y",
                    [0x11] = "t", [0x12] = "1", [0x13] = "2", [0x14] = "3",
                    [0x15] = "4", [0x16] = "6", [0x17] = "5", [0x18] = "=",
                    [0x19] = "9", [0x1A] = "7", [0x1B] = "-", [0x1C] = "8",
                    [0x1D] = "0", [0x1E] = "]", [0x1F] = "o", [0x20] = "u",
                    [0x21] = "[", [0x22] = "i", [0x23] = "p", [0x25] = "l",
                    [0x26] = "j", [0x27] = "'", [0x28] = "k", [0x29] = ";",
                    [0x2A] = "\\", [0x2B] = ",", [0x2C] = "/", [0x2D] = "n",
                    [0x2E] = "m", [0x2F] = ".", [0x32] = "`",
                    [0x24] = "return", [0x30] = "tab", [0x31] = "space",
                    [0x33] = "delete", [0x35] = "escape",
                    [0x7A] = "f1",  [0x78] = "f2",  [0x63] = "f3",
                    [0x76] = "f4",  [0x60] = "f5",  [0x61] = "f6",
                    [0x62] = "f7",  [0x64] = "f8",  [0x65] = "f9",
                    [0x6D] = "f10", [0x67] = "f11", [0x6F] = "f12",
                    [0x72] = "help",    [0x73] = "home",     [0x74] = "pageup",
                    [0x75] = "forwarddelete", [0x77] = "end", [0x79] = "pagedown",
                    [0x7B] = "left",    [0x7C] = "right",
                    [0x7D] = "down",    [0x7E] = "up",
                }

                -- Extract modifier names from event flags
                local function _extractMods(flags)
                    local mods = {}
                    -- Use rawFlagMasks for reliable detection
                    if flags.ctrl   then mods[#mods + 1] = "ctrl"  end
                    if flags.alt    then mods[#mods + 1] = "alt"   end
                    if flags.shift  then mods[#mods + 1] = "shift" end
                    if flags.cmd    then mods[#mods + 1] = "cmd"   end
                    return mods
                end

                -- Send a recorded step to JS
                local function _sendRecordStep(step)
                    local json = hs.json.encode(step)
                    _testShellEval("shellDispatch('macros','recordStep'," .. json .. ")")
                end

                -- Auto-insert ms.wait if time gap exceeds threshold
                local function _checkAutoWait()
                    if not _lastEventTime then return end
                    local now = hs.timer.secondsSinceEpoch()
                    local elapsed = now - _lastEventTime
                    if elapsed >= _waitThreshold then
                        local waitMs = math.floor(elapsed * 1000)
                        _sendRecordStep({ action = "ms.wait", params = { ms = waitMs } })
                    end
                end

                -- Start recording
                ms.shell._startRecording = function(opts)
                    if _recording then return true end
                    opts = opts or {}

                    _recording = true
                    _lastEventTime = hs.timer.secondsSinceEpoch()
                    _waitThreshold = (opts.waitThreshold or 50) / 1000  -- convert ms to seconds
                    _recordMouseMoves = opts.recordMouseMoves or false

                    local eventTypes = {
                        hs.eventtap.event.types.keyDown,
                        hs.eventtap.event.types.leftMouseDown,
                        hs.eventtap.event.types.rightMouseDown,
                        hs.eventtap.event.types.otherMouseDown,
                        hs.eventtap.event.types.leftMouseDragged,
                        hs.eventtap.event.types.scrollWheel,
                    }

                    _recordTap = hs.eventtap.new(eventTypes, function(event)
                        local eventType = event:getType()
                        local now = hs.timer.secondsSinceEpoch()

                        -- Auto-insert wait before each action
                        _checkAutoWait()
                        _lastEventTime = now

                        if eventType == hs.eventtap.event.types.keyDown then
                            local keyCode = event:getKeyCode()
                            local flags = event:getFlags()
                            local keyName = _keyCodeMap[keyCode]
                            if not keyName then
                                keyName = "key" .. tostring(keyCode)
                            end

                            -- Skip modifier-only keys
                            if keyName == "ctrl" or keyName == "alt"
                               or keyName == "shift" or keyName == "cmd" then
                                return false
                            end

                            local mods = _extractMods(flags)
                            _sendRecordStep({
                                action = "ms.type",
                                params = { key = keyName, mods = mods },
                            })

                        elseif eventType == hs.eventtap.event.types.leftMouseDown then
                            local pos = hs.mouse.absolutePosition()
                            _sendRecordStep({
                                action = "ms.Mouse",
                                params = {
                                    operation = "Click",
                                    button    = "Left",
                                    reference = "Mouse",
                                    x = math.floor(pos.x),
                                    y = math.floor(pos.y),
                                },
                            })

                        elseif eventType == hs.eventtap.event.types.rightMouseDown then
                            local pos = hs.mouse.absolutePosition()
                            _sendRecordStep({
                                action = "ms.Mouse",
                                params = {
                                    operation = "Click",
                                    button    = "Right",
                                    reference = "Mouse",
                                    x = math.floor(pos.x),
                                    y = math.floor(pos.y),
                                },
                            })

                        elseif eventType == hs.eventtap.event.types.otherMouseDown then
                            local pos = hs.mouse.absolutePosition()
                            local btnNum = event:getProperty(
                                hs.eventtap.event.properties.mouseEventButtonNumber)
                            local btnName = "Button" .. tostring(btnNum + 1)
                            _sendRecordStep({
                                action = "ms.Mouse",
                                params = {
                                    operation = "Click",
                                    button    = btnName,
                                    reference = "Mouse",
                                    x = math.floor(pos.x),
                                    y = math.floor(pos.y),
                                },
                            })

                        elseif eventType == hs.eventtap.event.types.leftMouseDragged then
                            local pos = hs.mouse.absolutePosition()
                            _sendRecordStep({
                                action = "ms.Mouse",
                                params = {
                                    operation = "Drag",
                                    button    = "Left",
                                    reference = "Mouse",
                                    x = math.floor(pos.x),
                                    y = math.floor(pos.y),
                                },
                            })

                        elseif eventType == hs.eventtap.event.types.scrollWheel then
                            local dy = event:getProperty(
                                hs.eventtap.event.properties.scrollWheelEventDeltaAxis1)
                            if dy and dy ~= 0 then
                                local direction = dy > 0 and "up" or "down"
                                local clicks = math.min(math.abs(dy), 10)
                                _sendRecordStep({
                                    action = "ms.scroll",
                                    params = {
                                        direction = direction,
                                        clicks = clicks,
                                    },
                                })
                            end
                        end

                        return false  -- don't swallow events
                    end)

                    _recordTap:start()
                    return true
                end

                -- Stop recording
                ms.shell._stopRecording = function()
                    if not _recording then return true end
                    _recording = false
                    if _recordTap then
                        _recordTap:stop()
                        _recordTap = nil
                    end
                    _lastEventTime = nil
                    return true
                end

                -- Is currently recording?
                ms.shell._isRecording = function()
                    return _recording
                end

                -- ── Bus Wiring ───────────────────────────────────────────

                if ms.bus then
                    -- Test Run
                    ms.bus.on("ui:macros:testRun", function(body)
                        if not body then
                            _testShellEval("shellDispatch('macros','testRunResult',{ok:false,err:'No macro data received'})")
                            return
                        end
                        local ok, err = ms.shell._testRun(body)
                        if ok then
                            _testShellEval("shellDispatch('macros','testRunResult',{ok:true})")
                        else
                            local safeErr = tostring(err or "unknown error")
                                :gsub("\\", "\\\\"):gsub("'", "\\'"):gsub("\n", "\\n")
                            _testShellEval("shellDispatch('macros','testRunResult',{ok:false,err:'" .. safeErr .. "'})")
                        end
                    end)

                    -- Start Recording
                    ms.bus.on("ui:macros:startRecording", function(body)
                        local ok, result = pcall(ms.shell._startRecording, body)
                        if not ok then
                            print("ms.shell._startRecording error: " .. tostring(result))
                            local safeErr = tostring(result):gsub("\\", "\\\\"):gsub("'", "\\'"):gsub("\n", "\\n")
                            _testShellEval("shellDispatch('macros','testRunResult',{ok:false,err:'Recording failed: " .. safeErr .. "'})")
                        elseif result ~= true then
                            _testShellEval("shellDispatch('macros','testRunResult',{ok:false,err:'Recording failed to start'})")
                        end
                    end)

                    -- Stop Recording
                    ms.bus.on("ui:macros:stopRecording", function(body)
                        local ok, err = pcall(ms.shell._stopRecording)
                        if not ok then
                            print("ms.shell._stopRecording error: " .. tostring(err))
                        end
                    end)
                end
            end
        -- END 12d. Test Run & Record Mode --

        -- 13. Safety Nets --
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
                sensitivity  = 1.5,
                trackpadMode = false,
                socdEnabled  = false,
                socdMode     = "lastWins",
                macros = {
                    spawnAlt = { enabled = false },
                },
            }
        -- END 13. Safety Nets --
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
        ms._skipDevPrewarm   = false  -- overridden by loadSettings() if previously saved
        ms._devArchiveLimit   = 15     -- overridden by loadSettings() if previously saved
        ms._loadComplete   = false  -- gates macro activation; set to true by _announceLoad
        ms.loadSettings()            -- load first so importedSounds/soundAssign are available
        -- If custom themes disabled, clear loading sound presets at startup
        if ms._customThemeDisabled then
            local loadSlots = { "startup", "themeLoaded", "load", "launch" }
            for _, sid in ipairs(loadSlots) do
                ms.soundAssign[sid] = nil
            end
        end
        ms._soundsDirty = true       -- force re-scan after settings (may have new importedSounds)
        ms._discoverSounds()
        ms.loadTheme()
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
                    if data.action == "toggleSkipPreload" then
                        ms._skipDevPrewarm = not ms._skipDevPrewarm
                        pcall(function() ms.saveSettings() end)
                        if ms._skipDevPrewarm and not _lFadingOut then
                            _lUpdate(100, "Developer tools skipped.")
                            hs.timer.doAfter(0.8, _lFadeOut)
                        end
                    end
                end)

                local htmlPath = hs.configdir .. "/ui/ms_loading.html"
                local baseURL  = "file://" .. hs.configdir .. "/ui/"

                _lWebView = hs.webview.new({ x=lx, y=ly, w=lw, h=lh }, {}, _ucLoad)
                pcall(function() _lWebView:windowStyle(0) end)
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
                    _lWebView:evaluateJavaScript(
                        "setSkipPreloadState(" .. (ms._skipDevPrewarm and "true" or "false") .. ")")
                    -- Replay buffered messages
                    for _, entry in ipairs(_lMsgBuffer) do
                        local encoded = entry.msg and ('"' .. entry.msg:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n') .. '"') or "null"
                        _lWebView:evaluateJavaScript(string.format("setProgress(%d, %s)", entry.pct, encoded))
                    end
                    _lMsgBuffer = {}
                    -- Fade in
                    _lWebView:show()
                    pcall(function() ms.sound(SoundDefaultsDir .. "Reset.wav") end)
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

            -- Set profile name on loading screen
            if ms.macroMeta and ms.macroMeta.name and _lWebView then
                _lWebView:evaluateJavaScript("setProfileName(" ..
                    '"' .. ms.macroMeta.name:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"' .. ")")
            end

            _G._timers = {}
            -- Timing: when dev tools are skipped, compress the chain
            local _skip = ms._skipDevPrewarm
            local t1 = _skip and 0.2 or 0.3
            local t2 = _skip and 0.3 or 0.5
            local t3 = _skip and 0.5 or 0.8
            local t4 = _skip and 0.7 or 1.3
            local t5 = _skip and 1.0 or 2.0
            local t6 = _skip and 1.0 or 2.6   -- same as t5 when skipped
            local t7 = _skip and 1.0 or 3.2
            local t8 = _skip and 1.0 or 3.8
            local t9 = _skip and 1.2 or 4.2
            local t10 = _skip and 1.5 or 4.6
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
                if ms._skipDevPrewarm then return end
                _lUpdate(62, "Loading console\u{2026}")
                _G._timers[60] = hs.timer.doAfter(0, function()
                    if not ms._skipDevPrewarm then pcall(function() ms.dev.prewarmStep("console") end) end
                end)
            end)
            _G._timers[7] = hs.timer.doAfter(t6, function()
                print("[startup] t=" .. t6 .. ": watcher")
                if ms._skipDevPrewarm then return end
                _lUpdate(72, "Loading macro monitor\u{2026}")
                _G._timers[70] = hs.timer.doAfter(0, function()
                    if not ms._skipDevPrewarm then pcall(function() ms.dev.prewarmStep("watcher") end) end
                end)
            end)
            _G._timers[8] = hs.timer.doAfter(t7, function()
                print("[startup] t=" .. t7 .. ": keys")
                if ms._skipDevPrewarm then return end
                _lUpdate(82, "Loading input monitor\u{2026}")
                _G._timers[80] = hs.timer.doAfter(0, function()
                    if not ms._skipDevPrewarm then pcall(function() ms.dev.prewarmStep("keys") end) end
                end)
            end)
            _G._timers[9] = hs.timer.doAfter(t8, function()
                print("[startup] t=" .. t8 .. ": window")
                if ms._skipDevPrewarm then return end
                _lUpdate(90, "Loading window monitor\u{2026}")
                _G._timers[90] = hs.timer.doAfter(0, function()
                    if not ms._skipDevPrewarm then pcall(function() ms.dev.prewarmStep("window") end) end
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
