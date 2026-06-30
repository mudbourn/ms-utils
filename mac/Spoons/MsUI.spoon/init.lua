-- MsUI --
    local MsUI = {}

    MsUI.name    = "MsUI"
    MsUI.version = "1.0"
-- END MsUI --

-- Init --
    function MsUI:init()
    end
-- END Init --

-- Start --
    function MsUI:start()
        if not _G.ms then return end
        local ms = _G.ms

        -- Run the webview panel initialization
        self:_initPanel(ms)
    end
-- END Start --

-- Webview Panel --
    function MsUI:_initPanel(ms)
    require("hs.webview")
    require("hs.webview.usercontent")
    -- Panel State & Builders --
        ms.ui = {
            _panel         = nil,
            _open          = false,
            _modalCallback = nil,
            _panelPos      = nil,
            _uiFadeTimer   = nil,
        }

        local uiHTMLPath   = os.getenv("HOME") .. "/.hammerspoon/ui/ms_settings_ui.html"
        local uiBasePath    = "file://" .. os.getenv("HOME") .. "/.hammerspoon/ui/"
        local panelW, panelH = 360, 640  -- 9:16 portrait

        local function _loadPanelHTML()
            local f = io.open(uiHTMLPath, "r")
            if not f then
                return "<body style='background:#1c1c1e;color:#fff;font:13px -apple-system, sans-serif;padding:20px'>"
                    .. "Could not read ms_settings_ui.html.<br><br>Expected at:<br>" .. uiHTMLPath .. "</body>"
            end
            local html = f:read("*all")
            f:close()
            return html
        end

        local function _bindDisplay(c)
            if not c then return nil end
            if c.type == "mouse" then return "Mouse " .. tostring(c.button) end
            local parts = {}
            for _, m in ipairs(c.mods or {}) do
                table.insert(parts, m:sub(1, 1):upper() .. m:sub(2))
            end
            table.insert(parts, (c.key or ""):upper())
            return table.concat(parts, "+")
        end

        local function _buildUIState()
            local macros = {}

            local childrenOf = {}
            for _, id in ipairs(ms.registry._defList or {}) do
                local def = ms.registry._defs[id]
                if def and def.sub then
                    childrenOf[def.sub] = childrenOf[def.sub] or {}
                    table.insert(childrenOf[def.sub], id)
                end
            end

            for _, id in ipairs(ms.registry._defList or {}) do
                local def = ms.registry._defs[id]
                if def and not def.sub and (def.group == "main" or def.group == "optional" or def.group == "system") then
                    local enabled = ms.binds[id]
                    if enabled == nil then enabled = def.enabled end
                    local subs = {}
                    for _, subId in ipairs(childrenOf[id] or {}) do
                        local subDef = ms.registry._defs[subId]
                        if subDef then
                            local subsubs = {}
                            for _, ss in ipairs(childrenOf[subId] or {}) do
                                local ssDef = ms.registry._defs[ss]
                                if ssDef then
                                    table.insert(subsubs, {
                                        id    = ss,
                                        label = ssDef.label or ss,
                                        mod   = ms.modConfig[ss] or ssDef.mod or "",
                                        bind  = _bindDisplay(ms.subBinds[ss]),
                                    })
                                end
                            end
                            table.insert(subs, {
                                id      = subId,
                                label   = subDef.label or subId,
                                mod     = ms.modConfig[subId] or subDef.mod or "",
                                bind    = _bindDisplay(ms.subBinds[subId]),
                                subsubs = #subsubs > 0 and subsubs or nil,
                            })
                        end
                    end
                    table.insert(macros, {
                        id        = id,
                        label     = def.label,
                        group     = def.group,
                        bind      = _bindDisplay(ms.effectiveBind(id)),
                        enabled   = enabled and true or false,
                        subs      = subs,
                    })
                end
            end
            for _, id in ipairs({"enable", "disable", "toggle"}) do
                local def = ms.systemBinds._defs[id]
                if def then
                    table.insert(macros, {
                        id         = id,
                        label      = def.label,
                        group      = "system",
                        bind       = _bindDisplay(ms.systemBinds.effective(id)),
                        systemBind = true,
                    })
                end
            end

            ms._discoverSounds()
            local soundNames = {}
            for name in pairs(ms.sounds or {}) do table.insert(soundNames, name) end
            table.sort(soundNames)

            -- Build loading sound presets from numbered variants.
            -- Slots in the preset group: startup, themeLoaded, load, launch
            -- Looks for base names (Launch, LoadEnd, etc.) and groups
            -- numbered variants (Launch2, LoadEnd2, …) into presets.
            local presetSlots = {
                { id = "startup",     bases = { "LoadStart", "Load Start" } },
                { id = "themeLoaded", bases = { "ThemeLoaded", "Theme Loaded" } },
                { id = "load",        bases = { "LoadEnd", "Load End" } },
                { id = "launch",      bases = { "Launch" } },
            }
            local presetMap = {}  -- presetNum → { slotId → soundName }
            for _, ps in ipairs(presetSlots) do
                for _, base in ipairs(ps.bases) do
                    -- Find all sounds starting with this base name
                    for sname in pairs(ms.sounds or {}) do
                        local num = sname:match("^" .. base .. "(%d*)$")
                        if num then
                            num = num == "" and "1" or num
                            presetMap[num] = presetMap[num] or {}
                            presetMap[num][ps.id] = sname
                        end
                    end
                end
            end
            -- Convert to sorted array
            local soundPresets = {}
            for num, assigns in pairs(presetMap) do
                table.insert(soundPresets, { num = tonumber(num), assigns = assigns })
            end
            table.sort(soundPresets, function(a, b) return a.num < b.num end)

            local status, curHash = ms.integrity.check()
            local meta = ms.macroMeta or {}

            local userSoundSlots = {}
            for _, def in ipairs(ms._userSettingDefs) do
                if def.type == "soundSlot" then
                    table.insert(userSoundSlots, { key = def.key, label = def.label or def.key })
                end
            end
            for _, menuDef in ipairs(ms._userMenuDefs) do
                for _, item in ipairs(menuDef.items or {}) do
                    if item.type == "soundSlot" then
                        table.insert(userSoundSlots, { key = item.key, label = item.label or item.key })
                    end
                end
            end

            local function _serItem(d)
                local it = {
                    type    = d.type,
                    key     = d.key,
                    label   = d.label,
                    hint    = d.hint,
                }
                if d.type == "slider" then
                    it.min  = d.min;  it.max  = d.max
                    it.step = d.step; it.unit = d.unit
                elseif d.type == "seg" then
                    it.options = d.options
                elseif d.type == "action" then
                    it.btnLabel = d.btnLabel; it.danger = d.danger
                elseif d.type == "group" then
                    local subs = {}
                    for _, sd in ipairs(d.items or {}) do
                        local si = {
                            type    = sd.type,
                            key     = sd.key,
                            label   = sd.label,
                            hint    = sd.hint,
                        }
                        if sd.type == "slider" then
                            si.min  = sd.min;  si.max  = sd.max
                            si.step = sd.step; si.unit = sd.unit
                        elseif sd.type == "seg"    then si.options  = sd.options
                        elseif sd.type == "action" then
                            si.btnLabel = sd.btnLabel; si.danger = sd.danger
                        end
                        if sd.key and sd.type ~= "action"
                            and sd.type ~= "divider" and sd.type ~= "groupLabel" then
                            si.value   = ms.settings.get(sd.key)
                            si.default = sd.default
                        end
                        table.insert(subs, si)
                    end
                    it.items = subs
                end
                if d.key and d.type ~= "action"
                    and d.type ~= "divider" and d.type ~= "groupLabel"
                    and d.type ~= "group" then
                    it.value   = ms.settings.get(d.key)
                    it.default = d.default
                end
                return it
            end

            local userSettings = {}
            local userCalibrationSettings = {}
            for _, def in ipairs(ms._userSettingDefs) do
                local item = _serItem(def)
                if (def.section or "settings") == "calibration" then
                    table.insert(userCalibrationSettings, item)
                else
                    table.insert(userSettings, item)
                end
            end
            local userMenus = {}
            for _, menuDef in ipairs(ms._userMenuDefs) do
                local items = {}
                for _, item in ipairs(menuDef.items) do
                    local entry = {
                        type  = item.type,
                        key   = item.key,
                        label = item.label,
                        hint  = item.hint,
                    }
                    if item.type == "slider" then
                        entry.min  = item.min;  entry.max  = item.max
                        entry.step = item.step; entry.unit = item.unit
                    elseif item.type == "seg" then
                        entry.options = item.options
                    elseif item.type == "action" then
                        entry.btnLabel = item.btnLabel; entry.danger = item.danger
                    end
                    if item.key then
                        entry.value   = ms.settings.get(item.key)
                        entry.default = item.default
                    end
                    table.insert(items, entry)
                end
                table.insert(userMenus, {
                    id    = menuDef.id,
                    title = menuDef.title,
                    icon  = menuDef.icon,
                    items = items,
                })
            end

            local themeOut = {}
            for k, v in pairs(ms._theme) do
                if k ~= "_uifcW" and k ~= "_uifcH" then themeOut[k] = v end
            end
            if themeOut.font and themeOut.font:match("%.[ot]tf$")
                or (themeOut.font and themeOut.font:match("%.woff2?$"))
            then
                local fp = os.getenv("HOME") .. "/.hammerspoon/" .. themeOut.font
                if hs.fs.attributes(fp) then
                    themeOut.fontURL  = "file://" .. fp
                    themeOut.font = themeOut.font:match("([^/\\]+)%.[^%.]+$") or themeOut.font
                end
            end

            return {
                macrosEnabled           = (BindValidity == 1),
                macros                  = macros,
                sensitivity             = CUR_CAM_SENS or 1.5,
                trackpadMode            = ms.trackpadMode or false,
                socdEnabled             = ms.socdEnabled or false,
                socdMode                = ms.socdMode or "lastWins",
                independentBindsEnabled = ms.independentBindsEnabled or false,
                soundEnabled            = ms.soundEnabled,
                soundVolume             = ms.soundVolume or 100,
                soundAssign             = ms.soundAssign or {},
                soundNames              = soundNames,
                soundPresets            = soundPresets,
                currentProfile          = meta.name and ms.sanitizeName(meta.name) or "",
                profiles                = ms.getProfiles(),
                integrityStatus         = status,
                integrityHash           = curHash,
                macroMeta               = {
                    name    = meta.name,
                    author  = meta.author,
                    website = meta.website,
                },
                docsURL                 = ms._docsURL,
                updateManifestURL       = ms._updateManifestURL,
                userSettings            = userSettings,
                userCalibrationSettings = userCalibrationSettings,
                userSoundSlots          = userSoundSlots,
                userMenus               = userMenus,
                hiddenFeatures          = ms._hiddenFeatures,
                preloadDevTools         = not (ms._skipDevPrewarm or false),
                customThemeEnabled      = not (ms._customThemeDisabled or false),
                devArchiveLimit         = ms._devArchiveLimit or 15,
                updateChannel           = ms._updateChannel or "stable",
                qrOptions               = ms._qrOptions or {
                    macros   = true,
                    theme    = true,
                    settings = true,
                    ui       = true,
                },
                theme                   = themeOut,
                msVersion               = (function()
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
                end)(),
            }
        end
    -- END Panel State & Builders --

    -- UI State Cache --
        local _uiStateDirty = true   -- true = cache needs rebuilding
        local _uiStateJSON  = nil    -- "receiveState(...)" ready to eval

        local function _rebuildUICache()
            local ok, json = pcall(hs.json.encode, _buildUIState())
            if ok then
                _uiStateJSON  = "receiveState(" .. json .. ");"
                _uiStateDirty = false
            end
        end

        ms.ui.markDirty = function() _uiStateDirty = true end

        ms.ui.refresh = function()
            if not ms.ui._panel then return end
            if _uiStateDirty or not _uiStateJSON then _rebuildUICache() end
            if _uiStateJSON then
                pcall(function()
                    ms.ui._panel:evaluateJavaScript(_uiStateJSON)
                end)
            end
        end

        ms.ui.prebuild = function()
            if _uiStateDirty or not _uiStateJSON then _rebuildUICache() end
        end

        local function _emptyToNil(s) if s == nil or s == "" then return nil end; return s end

        ms.ui._actions = {
            ready = function() ms.ui.refresh() end,

            setMacros = function(data)
                ms.setMacros(tonumber(data.value) == 1 and 1 or 0)
                ms.ui.refresh()
            end,

            playSlot = function(data) if data.slot then ms.playSlot(data.slot) end end,

            alert = function(data)
                if data.msg then
                    ms.alert(tostring(data.msg), tonumber(data.duration) or 3, data.noSound == true)
                end
            end,

            close = function() ms.ui.hide() end,

            moveWindow = function(data)
                if not ms.ui._panel then return end
                pcall(function()
                    local dx = tonumber(data.dx) or 0
                    local dy = tonumber(data.dy) or 0
                    if not ms.ui._panelPos then
                        local f = ms.ui._panel:frame()
                        ms.ui._panelPos = {
                            x = f.x,
                            y = f.y,
                            w = f.w,
                            h = f.h,
                        }
                    end
                    ms.ui._panelPos.x = ms.ui._panelPos.x + dx
                    ms.ui._panelPos.y = ms.ui._panelPos.y + dy
                    ms.ui._panel:frame(ms.ui._panelPos)
                end)
            end,

            reloadMacros = function()
                ms.bind.teardown()
                ms.registry       = { _defs = {}, _defList = {} }
                ms.bind._wires    = {}
                ms.bind._autoCount = 0
                ms.macroMeta       = nil
                ms._userSettingDefs  = {}
                ms._userSettingIndex = {}
                ms._userSettingVals  = {}

                local macrosPath = os.getenv("HOME") .. "/.hammerspoon/ms_macros.lua"
                local af = io.open(macrosPath, "r")
                if not af then
                    ms.alert("Reload failed:\nCannot open ms_macros.lua.", 6)
                    return
                end
                local rawSrc = af:read("*all"); af:close()
                local auditErrs = ms.auditMacros(rawSrc)
                if #auditErrs > 0 then
                    ms.alert("Reload blocked — audit failed.", 6)
                    return
                end
                local chunk, loadErr = load(
                    rawSrc,
                    "@ms_macros.lua",
                    "bt",
                    ms._macroSandbox
                )
                if not chunk then
                    ms.alert("Reload failed:\n" .. tostring(loadErr), 6)
                    return
                end
                local ok, runErr = pcall(chunk)
                if not ok then
                    ms.alert("Reload failed:\n" .. tostring(runErr), 6)
                    return
                end
                if not next(ms.registry._defs) then
                    ms.alert("Reload failed:\nNo ms.bind.define calls found.", 6)
                    return
                end
                for _, id in ipairs(ms.registry._defList) do
                    local def = ms.registry._defs[id]
                    if def and not def.sub and ms.binds[id] == nil then
                        ms.binds[id] = def.enabled
                    end
                end
                ms._systemActions = {}
                if ms._userSettingIndex["showTamperWarning"] then
                    ms._systemActions["showTamperWarning"] = function()
                        ms.showGuardian()
                    end
                end
                ms.loadSettings()
                if not ms.registry._defs["__panicButton"] then ms.bind._registerSystemBinds() end
                ms.bind.rebind()
                ms.cam.updateAnchor()
                ms.cam.updateMultiplier()
                ms.socdApply()
                if not ms._quickReloading then
                    ms.playSlot("update")
                    ms.alert("Macros reloaded.", 4, true)
                end
                -- Roblox unfocus/refocus (macro-specific)
                hs.timer.doAfter(0.15, function()
                    pcall(function()
                        local app = ms._targetApp and hs.application.get(ms._targetApp)
                        if app then
                            app:hide()
                            hs.timer.doAfter(0.15, function()
                                pcall(function() app:activate() end)
                            end)
                        end
                    end)
                end)
            end,

            reloadSettings = function()
                ms.loadSettings()
                ms.bind.rebind()
                ms.cam.updateAnchor()
                ms.cam.updateMultiplier()
                ms.socdApply()
                ms.playSlot("update")
                ms.alert("Settings reloaded.", 4, true)
                ms.ui.refresh()
            end,

            reloadTheme = function()
                ms.loadTheme()
                pcall(function() ms.alert:recolor() end)
                pcall(function() ms.dev:recolor() end)
                ms.playSlot("update")
                ms.alert("Theme reloaded.", 4, true)
                ms.ui.hide()
                hs.timer.doAfter(0.15, function() ms.ui.show() end)
            end,

            reloadUI = function()
                ms.reloadUI()
            end,

            reloadAll = function() hs.reload() end,

            quickReload = function()
                ms.quickReload()
            end,

            setQROption = function(data)
                if data.key and ms._qrOptions then
                    ms._qrOptions[data.key] = (data.value == true)
                    ms.saveSettings()
                    ms.playSlot("interact")
                end
            end,

            setPreloadDevTools = function(data)
                ms._skipDevPrewarm = not (data.value and true or false)
                ms.saveSettings()
                ms.playSlot("update")
                ms.ui.refresh()
            end,

            setCustomTheme = function(data)
                ms._customThemeDisabled = not (data.value and true or false)
                ms.saveSettings()
                if ms._customThemeDisabled then
                    -- Revert to defaults
                    for k, v in pairs(ms._themeDefaults) do ms._theme[k] = v end
                else
                    -- Reload custom theme
                    ms.loadTheme()
                end
                -- Re-discover sounds BEFORE playing so paths resolve correctly
                ms._soundsDirty = true
                ms._discoverSounds()
                -- Recolor existing toasts to match new theme
                pcall(function() ms.alert:recolor() end)
                pcall(function() ms.dev:recolor() end)
                ms.playSlot("update")
                ms.ui.refresh()
            end,

            setDevArchiveLimit = function(data)
                local n = tonumber(data.value)
                if n and n >= 0 and n <= 50 then
                    ms._devArchiveLimit = math.floor(n)
                    ms.saveSettings()
                    ms.playSlot("update")
                end
                ms.ui.refresh()
            end,

            setUpdateChannel = function(data)
                local ch = data.value
                if ch == "testing" or ch == "stable" then
                    ms._updateChannel = ch
                    ms.saveSettings()
                    ms.playSlot("update")
                end
                ms.ui.refresh()
            end,

            setMacroEnabled = function(data)
                if not data.id then return end
                local def = ms.registry._defs[data.id]
                if def and def.system then return end  -- system binds cannot be disabled
                ms.binds[data.id] = (data.value == true)
                ms.saveSettings()
                ms.bind.rebind()
                ms.playSlot("update")
                ms.ui.refresh()
            end,

            setSensitivity = function(data)
                local num = tonumber(data.value)
                if num and num >= 0.1 and num <= 4 then
                    CUR_CAM_SENS = num
                    ms.saveSettings()
                    ms.cam.updateMultiplier()
                    ms.playSlot("update")
                end
                ms.ui.refresh()
            end,

            setTrackpadMode = function(data)
                ms.trackpadMode = (data.value == true)
                ms.saveSettings()
                ms.bind.rebind()
                ms.playSlot("update")
                ms.ui.refresh()
            end,

            setSocdEnabled = function(data)
                ms.socdEnabled = (data.value == true)
                ms.saveSettings()
                ms.socdApply()
                ms.playSlot("update")
                ms.ui.refresh()
            end,

            setSocdMode = function(data)
                if data.value == "lastWins" or data.value == "neutral" or data.value == "firstWins" then
                    ms.socdMode = data.value
                    ms.saveSettings()
                    ms.playSlot("update")
                end
                ms.ui.refresh()
            end,

            setIndependentBinds = function(data)
                local turningOn = (data.value == true)
                ms.independentBindsEnabled = turningOn
                if turningOn then
                    local function bindKey(c)
                        if not c then return nil end
                        if c.type == "mouse" then return "mouse:" .. tostring(c.button) end
                        local mods = {}
                        for _, m in ipairs(c.mods or {}) do table.insert(mods, m) end
                        table.sort(mods)
                        return "key:" .. table.concat(mods, ",") .. ":" .. (c.key or "")
                    end
                    local usedKeys = {}
                    for _, id in ipairs(ms.registry._defList or {}) do
                        local def = ms.registry._defs[id]
                        if def and not def.sub then
                            local k = bindKey(ms.effectiveBind(id))
                            if k then usedKeys[k] = id end
                        end
                    end
                    for subId, c in pairs(ms.subBinds or {}) do
                        local k = bindKey(c)
                        if k then
                            if usedKeys[k] then
                                ms.subBinds[subId] = nil
                            else
                                usedKeys[k] = subId
                            end
                        end
                    end
                end
                ms.saveSettings()
                ms.bind.rebind()
                ms.playSlot("update")
                ms.ui.refresh()
            end,

            saveDefault = function()
                ms.saveDefault()
                ms.ui.refresh()
            end,

            resetToDefault = function()
                if ms.resetToDefault() then ms.playSlot("reset") end
                ms.ui.refresh()
            end,

            setSoundEnabled = function(data)
                ms.soundEnabled = (data.value == true)
                ms.saveSettings()
                ms.playSlot("update")
                ms.ui.refresh()
            end,

            setSoundVolume = function(data)
                local num = tonumber(data.value)
                if num and num >= 0 and num <= 100 then
                    ms.soundVolume = math.floor(num)
                    ms.saveSettings()
                    ms.playSlot("update")
                end
                ms.ui.refresh()
            end,

            setSoundAssign = function(data)
                if not data.slot then return end
                ms.soundAssign = ms.soundAssign or {}
                ms.soundAssign[data.slot] = _emptyToNil(data.name)
                ms.saveSettings()
                ms.playSlot("update")
                ms.ui.refresh()
            end,

            setSoundPreset = function(data)
                if not data.assigns then return end
                ms.soundAssign = ms.soundAssign or {}
                -- Clear all loading slots first so missing slots get reset
                local loadSlots = { "startup", "themeLoaded", "load", "launch" }
                for _, sid in ipairs(loadSlots) do
                    ms.soundAssign[sid] = nil
                end
                -- Apply preset assignments
                for slotId, soundName in pairs(data.assigns) do
                    ms.soundAssign[slotId] = soundName
                end
                ms.saveSettings()
                ms.playSlot("update")
                ms.ui.refresh()
            end,

            clearSoundPreset = function(data)
                if not data.slots then return end
                ms.soundAssign = ms.soundAssign or {}
                for _, slotId in ipairs(data.slots) do
                    ms.soundAssign[slotId] = nil
                end
                ms.saveSettings()
                ms.playSlot("update")
                ms.ui.refresh()
            end,

            switchProfile = function(data) if data.name then ms.switchProfile(data.name) end end,

            deleteProfile = function(data)
                if not data.name then return end
                local targetName = ms.sanitizeName(data.name)
                local activeName = ms.macroMeta and ms.sanitizeName(ms.macroMeta.name or "") or ""
                if targetName == "" or targetName == activeName then return end
                local dir = profilesPath .. targetName
                if not hs.fs.attributes(dir) then return end
                local sq = function(s) return "'" .. s:gsub("'", "'\\''" ) .. "'" end
                os.execute("rm -rf " .. sq(dir))
                ms._profilesDirty = true
                ms.ui.markDirty()
                ms.playSlot("reset")
                hs.timer.doAfter(0.05, function()
                    ms.alert("Profile \"" .. data.name .. "\" deleted.", 2, true)
                    ms.ui.refresh()
                end)
            end,

            clearProfiles = function()
                local activeName = ms.macroMeta and ms.sanitizeName(ms.macroMeta.name or "") or ""
                if activeName == "" then return end
                if not hs.fs.attributes(profilesPath) then return end
                local sq = function(s) return "'" .. s:gsub("'", "'\\''" ) .. "'" end
                local deleted = 0
                for entry in hs.fs.dir(profilesPath) do
                    if entry ~= "." and entry ~= ".." then
                        local safe = ms.sanitizeName(entry)
                        if safe ~= "" and safe ~= activeName then
                            local dir = profilesPath .. entry
                            local attr = hs.fs.attributes(dir)
                            if attr and attr.mode == "directory" then
                                os.execute("rm -rf " .. sq(dir))
                                deleted = deleted + 1
                            end
                        end
                    end
                end
                ms._profilesDirty = true
                ms.ui.markDirty()
                ms.playSlot("reset")
                hs.timer.doAfter(0.05, function()
                    ms.alert(deleted .. " profile" .. (deleted == 1 and "" or "s") .. " deleted.", 3, true)
                    ms.ui.refresh()
                end)
            end,

            importProfile     = function() ms.importProfile() end,
            importProfilePkg  = function() ms.importProfilePkg() end,
            exportProfilePkg  = function() ms.exportProfilePkg() end,
            createNewProfile  = function() ms.createNewProfile() end,
            saveCurrentProfile = function() ms.saveCurrentProfile() end,

            importSounds = function()
                ms.playSlot("alert")
                local slibDir = SoundLib:match("^(.-)[/\\]*$") or SoundLib
                local result = hs.dialog.chooseFileOrFolder(
                    "Select one or more sound files to add to your library",
                    hs.fs.attributes(slibDir) and SoundLib or os.getenv("HOME"),
                    true, false, true
                )
                local paths = {}
                for _, v in pairs(result or {}) do
                    if type(v) == "string" then table.insert(paths, v) end
                end
                if #paths == 0 then ms.ui.show(); return end
                if not hs.fs.attributes(slibDir) then
                    hs.execute("mkdir -p '" .. SoundLib .. "'")
                end
                if not hs.fs.attributes(slibDir) then
                    ms.ui.show()
                    ms.alert("Could not create sounds folder:\n" .. SoundLib, 4)
                    return
                end
                local function sq(s) return "'" .. s:gsub("'", "'\\''" ) .. "'" end
                local added, failed = {}, {}
                for _, srcPath in ipairs(paths) do
                    local filename   = srcPath:match("([^/]+)$")
                    local importName = filename and (filename:match("^(.+)%.[^%.]+$") or filename)
                    if not filename or not importName then
                        table.insert(failed, srcPath)
                    else
                        local dst    = SoundLib .. filename
                        local copied = false
                        if srcPath ~= dst then
                            local f = io.open(srcPath, "rb")
                            if f then
                                local content = f:read("*all"); f:close()
                                local g = io.open(dst, "wb")
                                if g then g:write(content); g:close(); copied = true end
                            end
                            if not copied then
                                local _, st = hs.execute("/bin/cp " .. sq(srcPath) .. " " .. sq(dst))
                                copied = (st == true) or (hs.fs.attributes(dst) ~= nil)
                            end
                            if not copied then table.insert(failed, importName) end
                        else
                            copied = true
                        end
                        if copied then
                            ms.importedSounds = ms.importedSounds or {}
                            ms.importedSounds[importName] = filename
                            table.insert(added, importName)
                        end
                    end
                end
                if #added > 0 then
                    ms.saveSettings()
                    ms._soundsDirty = true
                    ms._discoverSounds()
                end
                ms.ui.show()
                hs.timer.doAfter(0.15, function()
                    if #added > 0 then ms.playSlot("update") end
                    if #added > 0 and #failed == 0 then
                        local label = #added == 1
                            and ("Sound \"" .. added[1] .. "\" added.")
                            or  (#added .. " sounds added.")
                        ms.alert(label, 3, true)
                    elseif #added > 0 then
                        ms.alert(
                            #added .. " added, " .. #failed .. " failed.",
                            3,
                            true
                        )
                    else
                        ms.alert("Import failed.\nGrant Hammerspoon Full Disk Access if importing from outside ~/.hammerspoon.", 5)
                    end
                    ms.ui.refresh()
                end)
            end,

            importSoundForSlot = function(data)
                if not data.slot then return end
                local slot = data.slot
                ms.playSlot("alert")
                local slibDir = SoundLib:match("^(.-)[/\\]*$") or SoundLib
                local result = hs.dialog.chooseFileOrFolder(
                    "Select a sound file for \"" .. (data.label or slot) .. "\"",
                    hs.fs.attributes(slibDir) and SoundLib or os.getenv("HOME"),
                    true, false, false
                )
                local selectedPath
                for _, v in pairs(result or {}) do
                    if type(v) == "string" then selectedPath = v; break end
                end
                if not selectedPath then ms.ui.show(); return end
                if not hs.fs.attributes(slibDir) then
                    hs.execute("mkdir -p '" .. SoundLib .. "'")
                end
                local function sq(s) return "'" .. s:gsub("'", "'\\''" ) .. "'" end
                local filename   = selectedPath:match("([^/]+)$")
                local importName = filename and (filename:match("^(.+)%.[^%.]+$") or filename)
                if not filename or not importName then
                    ms.ui.show(); ms.alert("Could not read filename.", 3); return
                end
                local dst    = SoundLib .. filename
                local copied = false
                if selectedPath ~= dst then
                    local f = io.open(selectedPath, "rb")
                    if f then
                        local content = f:read("*all"); f:close()
                        local g = io.open(dst, "wb")
                        if g then g:write(content); g:close(); copied = true end
                    end
                    if not copied then
                        local _, st = hs.execute("/bin/cp " .. sq(selectedPath) .. " " .. sq(dst))
                        copied = (st == true) or (hs.fs.attributes(dst) ~= nil)
                    end
                else
                    copied = true
                end
                ms.ui.show()
                if not copied then
                    hs.timer.doAfter(0.15, function()
                        ms.alert("Import failed.\nGrant Hammerspoon Full Disk Access if needed.", 5)
                    end)
                    return
                end
                ms.importedSounds = ms.importedSounds or {}
                ms.importedSounds[importName] = filename
                ms.soundAssign = ms.soundAssign or {}
                ms.soundAssign[slot] = importName
                ms.saveSettings()
                ms._soundsDirty = true
                ms._discoverSounds()
                ms.playSlot("update")
                hs.timer.doAfter(0.15, function()
                    ms.alert("\"" .. importName .. "\" imported and assigned.", 3, true)
                    ms.ui.refresh()
                end)
            end,

            openWindowMonitor = function() if ms.dev and ms.dev.window then ms.dev.window.toggle() end end,

            openConsole = function() hs.openConsole() end,

            editMacros = function()
                os.execute("open " .. os.getenv("HOME") .. "/.hammerspoon/ms_macros.lua")
            end,

            editTheme = function()
                os.execute("open " .. themePath)
            end,

            openDevLogs = function()
                local logDir = os.getenv("HOME") .. "/Documents/ms_dev_logs/"
                hs.fs.mkdir(logDir)
                os.execute("open " .. logDir)
            end,

            trustCurrentVersion = function()
                ms.integrity.trustCurrent()
                ms.ui.refresh()
            end,

            deleteTrustedHash = function()
                ms.integrity.deleteTrustedHash()
                ms.alert("Trusted hash deleted.\nTamper protection is now OFF until you re-trust.", 5)
                ms.ui.refresh()
            end,

            checkIntegrity = function()
                local status, cur, trusted = ms.integrity.check()
                if status == "trusted" then
                    ms.alert("\xe2\x9c\x93 ms_core.lua matches trusted hash.\n" .. (cur and cur:sub(1, 16) or "?") .. "\xe2\x80\xa6", 5, true)
                    ms.ui.refresh()
                elseif status == "mismatch" then
                    hs.reload()
                else
                    ms.alert("No trusted hash on record.\nUse \"Trust Current Version\" to seed trust.", 5)
                    ms.ui.refresh()
                end
            end,

            openURL = function(data) if data.url then hs.urlevent.openURL(data.url) end end,

            checkForUpdate = function()
                if ms._updateChannel == "testing" then
                    ms.integrity.updateBeta()
                else
                    ms.integrity.update()
                end
            end,

            openConsole       = function() ms.dev.console.toggle()  end,
            openWatcher       = function() ms.dev.watcher.toggle()  end,
            openKeys          = function() ms.dev.keys.toggle()     end,
            openWindowMonitor = function() ms.dev.window.toggle()   end,

            startRebind = function(data)
                if not data.id then return end

                if data.systemBind then
                    local sysDef = ms.systemBinds._defs[data.id]
                    if not sysDef then return end
                    local label = sysDef.label
                    local curBind = ms.systemBinds.effective(data.id)

                    local function bindDisplay(c)
                        if not c then return "unset" end
                        if c.type == "mouse" then return "Mouse " .. tostring(c.button) end
                        local parts = {}
                        for _, m in ipairs(c.mods or {}) do table.insert(parts, m) end
                        table.insert(parts, c.key or "")
                        return table.concat(parts, "+")
                    end

                    ms.alert("Rebinding: " .. label
                        .. "\nCurrent: " .. bindDisplay(curBind)
                        .. "\nPress your new key or mouse button.\nEscape to cancel.", 15, false, { id = "_rebind" })

                    ms._inputOpen = true
                    ms.ui._open   = false

                    local capture
                    local cancelTimer

                    local function restorePanel()
                        ms.ui._open = true
                        local roblox = hs.application.get(ms._targetApp or "Roblox")
                        if roblox then
                            hs.timer.doAfter(0.05, function()
                                local ok, win = pcall(function() return roblox:mainWindow() end)
                                if ok and win then pcall(function() win:focus() end) end
                                pcall(function() roblox:activate() end)
                            end)
                        end
                    end

                    capture = hs.eventtap.new({
                        hs.eventtap.event.types.keyDown,
                        hs.eventtap.event.types.leftMouseDown,
                        hs.eventtap.event.types.rightMouseDown,
                        hs.eventtap.event.types.otherMouseDown,
                    }, function(event)
                        capture:stop(); capture = nil; cancelTimer:stop()

                        local parsed, bindStr2
                        local t = event:getType()

                        if t == hs.eventtap.event.types.keyDown then
                            local keyCode = event:getKeyCode()
                            local flags = event:getFlags()
                            if keyCode == 53 and not (flags.cmd or flags.alt or flags.ctrl or flags.shift) then
                                ms._inputOpen = false
                                ms.alert("Rebind cancelled.", 2, false, { id = "_rebind" })
                                restorePanel()
                                return true
                            end
                            local mods = {}
                            if flags.cmd   then table.insert(mods, "cmd")   end
                            if flags.alt   then table.insert(mods, "alt")   end
                            if flags.ctrl  then table.insert(mods, "ctrl")  end
                            if flags.shift then table.insert(mods, "shift") end
                            local keyStr = hs.keycodes.map[keyCode]
                            if keyStr then
                                parsed   = {
                                    type = "key",
                                    mods = mods,
                                    key  = keyStr,
                                }
                                local parts = {}
                                for _, m in ipairs(mods) do table.insert(parts, m) end
                                table.insert(parts, keyStr)
                                bindStr2 = table.concat(parts, "+")
                            end
                        else
                            local btn
                            if     t == hs.eventtap.event.types.leftMouseDown  then btn = 0
                            elseif t == hs.eventtap.event.types.rightMouseDown then btn = 1
                            else btn = event:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber) end
                            parsed   = { type="mouse", button=btn }
                            bindStr2 = "Mouse " .. btn
                        end

                        if parsed then
                            ms.playSlot("interact")
                            ms._inputOpen = false
                            ms.ui.modal({
                                title   = "Confirm Rebind",
                                msg     = "Set \"" .. label .. "\" to:  " .. bindStr2,
                                confirm = "Confirm",
                                cancel  = "Cancel",
                            }, function(r)
                                if r.confirmed then
                                    ms.systemBinds._config[data.id] = parsed
                                    ms.saveSettings()
                                    ms.playSlot("update")
                                    ms.systemBinds.rebind()
                                    restorePanel()
                                    hs.timer.doAfter(0.2, function()
                                        ms.alert(label .. " rebound to: " .. bindStr2, 3, true, { id = "_rebind" })
                                        ms.ui.refresh()
                                    end)
                                else
                                    ms.alert("Rebind cancelled.", 2, false, { id = "_rebind" })
                                    restorePanel()
                                    ms.ui.refresh()
                                end
                            end)
                        else
                            ms._inputOpen = false
                            ms.alert("Could not read input. Try again.", 2, false, { id = "_rebind" })
                            restorePanel()
                        end
                        return true
                    end)

                    capture:start()
                    cancelTimer = hs.timer.doAfter(15, function()
                        if capture then
                            capture:stop(); capture = nil
                            ms._inputOpen = false
                            ms.alert("Rebind timed out.", 2, false, { id = "_rebind" })
                            restorePanel()
                            ms.ui.refresh()
                        end
                    end)
                    return
                end

                local def = ms.registry._defs[data.id]
                if not def then return end
                local label = def.label or data.id

                local function bindDisplay(c)
                    if not c then return "unset" end
                    if c.type == "mouse" then return "Mouse " .. tostring(c.button) end
                    local parts = {}
                    for _, m in ipairs(c.mods or {}) do table.insert(parts, m) end
                    table.insert(parts, c.key or "")
                    return table.concat(parts, "+")
                end

                ms.alert("Rebinding: " .. label
                    .. "\nCurrent: " .. bindDisplay(ms.effectiveBind(data.id))
                    .. "\nPress your new key or mouse button.\nEscape to cancel.", 15, false, { id = "_rebind" })

                ms._inputOpen = true
                ms.ui._open   = false

                local capture
                local cancelTimer

                local function restorePanel()
                    ms.ui._open = true
                    local roblox = hs.application.get(ms._targetApp or "Roblox")
                    if roblox then
                        hs.timer.doAfter(0.05, function()
                            local ok, win = pcall(function() return roblox:mainWindow() end)
                            if ok and win then pcall(function() win:focus() end) end
                            pcall(function() roblox:activate() end)
                        end)
                    end
                end

                capture = hs.eventtap.new({
                    hs.eventtap.event.types.keyDown,
                    hs.eventtap.event.types.leftMouseDown,
                    hs.eventtap.event.types.rightMouseDown,
                    hs.eventtap.event.types.otherMouseDown,
                }, function(event)
                    capture:stop(); capture = nil; cancelTimer:stop()

                    local parsed, bindStr2
                    local t = event:getType()

                    if t == hs.eventtap.event.types.keyDown then
                        local keyCode = event:getKeyCode()
                        local flags = event:getFlags()
                        if keyCode == 53 and not (flags.cmd or flags.alt or flags.ctrl or flags.shift) then
                            ms._inputOpen = false
                            ms.alert("Rebind cancelled.", 2, false, { id = "_rebind" })
                            restorePanel()
                            return true
                        end
                        local mods = {}
                        if flags.cmd   then table.insert(mods, "cmd")   end
                        if flags.alt   then table.insert(mods, "alt")   end
                        if flags.ctrl  then table.insert(mods, "ctrl")  end
                        if flags.shift then table.insert(mods, "shift") end
                        local keyStr = hs.keycodes.map[keyCode]
                        if keyStr then
                            parsed   = {
                                type = "key",
                                mods = mods,
                                key  = keyStr,
                            }
                            local parts = {}
                            for _, m in ipairs(mods) do table.insert(parts, m) end
                            table.insert(parts, keyStr)
                            bindStr2 = table.concat(parts, "+")
                        end
                    else
                        local btn
                        if     t == hs.eventtap.event.types.leftMouseDown  then btn = 0
                        elseif t == hs.eventtap.event.types.rightMouseDown then btn = 1
                        else btn = event:getProperty(hs.eventtap.event.properties.mouseEventButtonNumber) end
                        parsed   = { type="mouse", button=btn }
                        bindStr2 = "Mouse " .. btn
                    end

                    if parsed then
                        local conflictId = ms.bind.siblingConflict(data.id, parsed)
                        if conflictId then
                            local cLabel = (ms.registry._defs[conflictId] and ms.registry._defs[conflictId].label) or conflictId
                            ms.playSlot("alert")
                            ms._inputOpen = false
                            ms.alert("Bind Conflict: \"" .. bindStr2 .. "\" is already used by \"" .. cLabel .. "\".\nChoose a different input.", 4, false, { id = "_rebind" })
                            restorePanel()
                            return true
                        end
                        ms.playSlot("interact")
                        ms._inputOpen = false
                        ms.ui.modal({
                            title   = "Confirm Rebind",
                            msg     = "Set \"" .. label .. "\" to:  " .. bindStr2,
                            confirm = "Confirm",
                            cancel  = "Cancel",
                        }, function(r)
                            if r.confirmed then
                                if def.sub then
                                    ms.subBinds[data.id] = parsed
                                else
                                    ms.bindConfig[data.id] = parsed
                                end
                                ms.saveSettings()
                                ms.playSlot("update")
                                ms.bind.rebind()
                                restorePanel()
                                hs.timer.doAfter(0.2, function()
                                    ms.alert(label .. " rebound to: " .. bindStr2, 3, true, { id = "_rebind" })
                                    ms.ui.refresh()
                                end)
                            else
                                ms.alert("Rebind cancelled.", 2, false, { id = "_rebind" })
                                restorePanel()
                                ms.ui.refresh()
                            end
                        end)
                    else
                        ms._inputOpen = false
                        ms.alert("Could not read input. Try again.", 2, false, { id = "_rebind" })
                        restorePanel()
                    end
                    return true
                end)

                capture:start()
                cancelTimer = hs.timer.doAfter(15, function()
                    if capture then
                        capture:stop(); capture = nil
                        ms._inputOpen = false
                        ms.alert("Rebind timed out.", 2, false, { id = "_rebind" })
                        restorePanel()
                        ms.ui.refresh()
                    end
                end)
            end,

            resetSetting = function(data)
                local key = data.key
                local def = ms.macroDefaults or {}
                if key == "sensitivity" then
                    CUR_CAM_SENS = tonumber(def.sensitivity) or 1.5
                    ms.saveSettings(); ms.cam.updateMultiplier()
                elseif key == "trackpadMode" then
                    ms.trackpadMode = (def.trackpadMode == true)
                    ms.saveSettings(); ms.bind.rebind()
                elseif key == "socdEnabled" then
                    ms.socdEnabled = (def.socdEnabled == true)
                    ms.saveSettings(); ms.socdApply()
                elseif key == "socdMode" then
                    ms.socdMode = def.socdMode or "lastWins"
                    ms.saveSettings()
                elseif key == "independentBinds" then
                    ms.independentBindsEnabled = (def.independentBinds == true)
                    ms.saveSettings(); ms.bind.rebind()
                elseif key == "soundEnabled" then
                    ms.soundEnabled = true
                    ms.saveSettings()
                elseif key == "soundVolume" then
                    ms.soundVolume = 100
                    ms.saveSettings()
                end
                ms.playSlot("reset")
                ms.ui.refresh()
            end,

            userSettingChange = function(data)
                if not data.key then return end
                ms.settings.set(data.key, data.value)
                ms.playSlot("update")
                ms.ui.refresh()
            end,

            userSettingAction = function(data)
                if not data.key then return end
                local def = ms._userSettingIndex[data.key]
                if def and def.type == "action" and type(def.onAction) == "function" then
                    pcall(def.onAction)
                end
                local sysAction = ms._systemActions and ms._systemActions[data.key]
                if type(sysAction) == "function" then pcall(sysAction) end
                ms.ui.refresh()
            end,

            resetUserSetting = function(data)
                if not data.key then return end
                local def = ms._userSettingIndex[data.key]
                if not def or def.default == nil then return end
                ms.settings.set(data.key, def.default)
                ms.playSlot("reset")
                ms.ui.refresh()
            end,

            modalResult = function(data)
                if ms.ui._modalCallback then
                    local cb = ms.ui._modalCallback
                    ms.ui._modalCallback = nil
                    pcall(cb, {
                        confirmed = data.confirmed == true,
                        value     = type(data.value) == "string" and data.value or "",
                    })
                end
            end,

            resetBind = function(data)
                if not data.id then return end

                if data.systemBind then
                    ms.systemBinds._config[data.id] = nil
                    ms.saveSettings()
                    ms.systemBinds.rebind()
                    ms.playSlot("reset")
                    local def = ms.systemBinds._defs[data.id]
                    hs.timer.doAfter(0.1, function()
                        ms.alert((def and def.label or data.id) .. " reset to default.", 2, true)
                        ms.ui.refresh()
                    end)
                    return
                end

                local def = ms.registry._defs[data.id]
                if not def then return end
                if def.sub then
                    ms.subBinds[data.id] = nil
                    if ms.independentBindsEnabled then
                        ms.binds[data.id] = false
                    end
                else
                    ms.bindConfig[data.id] = nil
                end
                ms.saveSettings()
                ms.bind.rebind()
                ms.playSlot("reset")
                hs.timer.doAfter(0.1, function()
                    ms.alert((def.label or data.id) .. " reset to default.", 2, true)
                    ms.ui.refresh()
                end)
            end,

            setModifier = function(data)
                if not data.id then return end
                local key = type(data.key) == "string" and data.key:match("^%s*(.-)%s*$") or ""
                ms.modConfig[data.id] = (key ~= "") and key or nil
                ms.saveSettings()
                ms.bind.rebind()
                ms.playSlot("update")
                ms.ui.refresh()
            end,

            clearModifier = function(data)
                if not data.id then return end
                ms.modConfig[data.id] = ""
                ms.saveSettings()
                ms.bind.rebind()
                ms.playSlot("reset")
                ms.ui.refresh()
            end,

            startModRebind = function(data)
                if not data.id then return end
                local def = ms.registry._defs[data.id]
                if not def or not def.sub then return end
                local label = def.label or data.id
                local cur   = ms.getMod(data.id)

                ms.alert("Modifier for \"" .. label .. "\""
                    .. "\nCurrent: " .. (cur or "unset")
                    .. "\nPress a key  —  Backspace to clear  —  Escape to cancel.", 15, false, { id = "_rebind" })

                ms._inputOpen = true
                ms.ui._open   = false

                local capture, cancelTimer
                local prevFlags = {}

                local function finish(newKey, cancelled)
                    ms._inputOpen = false
                    if not cancelled then
                        ms.modConfig[data.id] = newKey  -- nil = cleared
                        ms.saveSettings()
                        ms.bind.rebind()
                        ms.playSlot(newKey and "update" or "reset")
                    end
                    ms.ui.show()
                    hs.timer.doAfter(0.1, function()
                        if not cancelled then
                            if newKey then
                                ms.alert("Modifier set to: " .. newKey, 3, true, { id = "_rebind" })
                            else
                                ms.alert("Modifier cleared.", 3, true, { id = "_rebind" })
                            end
                        else
                            ms.alert("Modifier rebind cancelled.", 2, false, { id = "_rebind" })
                        end
                        ms.ui.refresh()
                    end)
                end

                capture = hs.eventtap.new({
                    hs.eventtap.event.types.keyDown,
                    hs.eventtap.event.types.flagsChanged,
                }, function(event)
                    local t     = event:getType()
                    local flags = event:getFlags()

                    if t == hs.eventtap.event.types.flagsChanged then
                        local newMod = nil
                        if flags.shift and not prevFlags.shift then newMod = "shift"
                        elseif flags.alt   and not prevFlags.alt   then newMod = "alt"
                        elseif flags.ctrl  and not prevFlags.ctrl  then newMod = "ctrl"
                        elseif flags.cmd   and not prevFlags.cmd   then newMod = "cmd" end
                        prevFlags = flags
                        if not newMod then return false end  -- modifier released
                        capture:stop(); capture = nil; cancelTimer:stop()
                        finish(newMod, false)
                        return false
                    end

                    capture:stop(); capture = nil; cancelTimer:stop()
                    local keyCode = event:getKeyCode()
                    if keyCode == 53 and not (flags.cmd or flags.alt or flags.ctrl or flags.shift) then
                        finish(nil, true)   -- bare Escape = cancel
                    elseif keyCode == 51 then
                        finish(nil, false)  -- Backspace = clear
                    else
                        local keyName = hs.keycodes.map[keyCode]
                        finish(keyName or nil, keyName == nil)
                    end
                    return true
                end)

                capture:start()
                cancelTimer = hs.timer.doAfter(15, function()
                    if capture then
                        capture:stop(); capture = nil
                        finish(nil, true)
                    end
                end)
            end,
        }

        do
            local _backing = ms.ui._actions
            ms.ui._actions = setmetatable({}, {
                __index    = _backing,
                __newindex = function(_, k)
                    error("ms.ui._actions is read-only (attempted write to '" .. tostring(k) .. "')", 2)
                end,
                __len      = function() return #_backing end,
            })
        end
        local _ucMS = hs.webview.usercontent.new("ms")
        _ucMS:setCallback(function(message)
            local ok, data = pcall(hs.json.decode, message.body)
            if not ok or type(data) ~= "table" or not data.action then
                print("ms.ui: malformed message from panel: " .. tostring(message.body))
                return
            end
            local handler = ms.ui._actions[data.action]
            if not handler then
                print("ms.ui: unknown action from panel: " .. tostring(data.action))
                return
            end
            local ok2, err = pcall(handler, data)
            if not ok2 then
                print("ms.ui: action '" .. data.action .. "' error: " .. tostring(err))
            end
        end)

        local function _panelFrame()
            local screen = hs.screen.mainScreen():frame()
            local w, h = panelW, panelH
            local x = screen.x + math.floor((screen.w / 2 - w) / 2)
            local y = screen.y + math.floor((screen.h - h) / 2)
            h = math.min(h, (screen.y + screen.h) - y - 20)
            return {
                x = x,
                y = y,
                w = w,
                h = h,
            }
        end

        local function _buildPanel()
            local panel = hs.webview.new(_panelFrame(), { developerExtrasEnabled = true }, _ucMS)
            if not panel then return nil end
            pcall(function() panel:windowStyle(0) end)
            pcall(function() panel:level(hs.canvas.windowLevels.floating) end)
            pcall(function() panel:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces) end)
            pcall(function() panel:allowTextEntry(true) end)
            pcall(function() panel:shadow(true) end)
            pcall(function() panel:closeOnEscape(true) end)
            pcall(function()
                panel:windowCallback(function(action)
                    if action == "closing" then
                        ms.ui.hide()
                    end
                end)
            end)
            panel:html(_loadPanelHTML(), uiBasePath)
            return panel
        end

        ms.ui.show = function()
            if ms.ui._uiFadeTimer then ms.ui._uiFadeTimer:stop(); ms.ui._uiFadeTimer = nil end
            if not ms.ui._panel then
                ms.ui._panel = _buildPanel()
                if not ms.ui._panel then
                    ms.alert("Settings panel failed to load — check the Hammerspoon Console.", 5)
                    return
                end
            end
            local _pf = _panelFrame()
            ms.ui._panelPos = {
                x = _pf.x,
                y = _pf.y,
                w = _pf.w,
                h = _pf.h,
            }
            pcall(function() ms.ui._panel:frame(_pf) end)
            ms.ui._open = true
            ms.playSlot("settingsOpen")
            pcall(function() ms.ui._panel:alpha(0) end)
            ms.ui._panel:show()
            pcall(function() ms.ui._panel:bringToFront(true) end)
            ms.ui.refresh()
            -- Capture panel ref locally so the timer survives _panel being
            -- swapped or nilled by a concurrent hide().
            local panel = ms.ui._panel
            local step, steps = 0, 6
            ms.ui._uiFadeTimer = hs.timer.doEvery((ms._theme.fadeMs or 150) / 1000 / steps, function()
                step = step + 1
                pcall(function() panel:alpha(step / steps) end)
                if step >= steps then
                    if ms.ui._uiFadeTimer then ms.ui._uiFadeTimer:stop(); ms.ui._uiFadeTimer = nil end
                end
            end)
        end

        ms.ui.hide = function()
            if ms.ui._uiFadeTimer then ms.ui._uiFadeTimer:stop(); ms.ui._uiFadeTimer = nil end
            if ms.ui._open then ms.playSlot("settingsClose") end
            ms.ui._open = false
            local panel = ms.ui._panel
            if panel then
                -- Capture current alpha so fade-out starts from wherever we are,
                -- not from an assumed 1.0 (which would flash a transparent panel).
                local startAlpha = 1
                pcall(function() startAlpha = panel:alpha() or 1 end)
                local step, steps = 0, 6
                ms.ui._uiFadeTimer = hs.timer.doEvery((ms._theme.fadeMs or 150) / 1000 / steps, function()
                    step = step + 1
                    pcall(function() panel:alpha(startAlpha * (1 - (step / steps))) end)
                    if step >= steps then
                        if ms.ui._uiFadeTimer then ms.ui._uiFadeTimer:stop(); ms.ui._uiFadeTimer = nil end
                        pcall(function() panel:hide() end)
                    end
                end)
            end
            ms._inputOpen = true
            local roblox = hs.application.get("Roblox")
            if roblox then
                hs.timer.doAfter(0.05, function()
                    local ok, win = pcall(function() return roblox:mainWindow() end)
                    if ok and win then pcall(function() win:focus() end) end
                    pcall(function() roblox:activate() end)
                end)
            end
        end

        ms.ui.toggle = function()
            if ms.ui._open then ms.ui.hide() else ms.ui.show() end
        end

        ms.ui.prewarm = function()
            if not ms.ui._panel then
                ms.ui._panel = _buildPanel()
            end
            hs.timer.doAfter(2, function()
                if ms.ui._panel and not ms.ui._open then
                    ms.ui.refresh()
                end
            end)
        end
    -- END UI State Cache --

    -- ms.ui.modal --
        ms.ui.modal = function(data, callback)
            if not callback then return end
            if not ms.ui._panel then
                pcall(callback, { confirmed = false })
                return
            end
            ms.ui._modalCallback = callback
            if not ms.ui._open then ms.ui.show() end
            local ok, json = pcall(hs.json.encode, {
                title   = data.title   or "",
                msg     = data.msg     or "",
                confirm = data.confirm or "OK",
                cancel  = data.cancel  or "Cancel",
            })
            if not ok then pcall(callback, { confirmed = false }); return end
            hs.timer.doAfter(0.05, function()
                pcall(function()
                    ms.ui._panel:evaluateJavaScript("openLuaModal(" .. json .. ")")
                end)
            end)
        end
    -- END ms.ui.modal --

    -- ms.ui.prompt --
        ms.ui.prompt = function(data, callback)
            if not callback then return end
            if not ms.ui._panel then
                pcall(callback, { confirmed = false, value = "" })
                return
            end
            ms.ui._modalCallback = callback
            if not ms.ui._open then ms.ui.show() end
            local ok, json = pcall(hs.json.encode, {
                title        = data.title   or "",
                msg          = data.msg     or "",
                confirm      = data.confirm or "OK",
                cancel       = data.cancel  or "Cancel",
                hasInput     = true,
                inputDefault = data.default or "",
            })
            if not ok then pcall(callback, { confirmed = false, value = "" }); return end
            hs.timer.doAfter(0.05, function()
                pcall(function()
                    ms.ui._panel:evaluateJavaScript("openLuaModal(" .. json .. ")")
                end)
            end)
        end
    -- END ms.ui.prompt --

    end
-- END Webview Panel --

return MsUI
