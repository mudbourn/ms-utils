-- MsDevTools --

local MsDevTools = {}

    MsDevTools.name    = "MsDevTools"
    MsDevTools.version = "1.0"

    MsDevTools.archiveLimit = 15
    MsDevTools.logDir       = "~/Documents/ms_dev_logs/"
    MsDevTools.branchTrace  = true

-- END --

-- State --

    local _home       = os.getenv("HOME")
    local _devLogDir  = _home .. "/Documents/"
    local _devBaseDir = _devLogDir .. "ms_dev_logs/"
    local _devArchDir = _devBaseDir .. "backups/"
    local _devBase    = "file://" .. _home .. "/.hammerspoon/ui/"

    local _jsonDir, _readDir
    local _catPaths, _readablePaths

    local _typeToCategory = {
        key       = "input",
        mouse     = "input",
        scroll    = "input",
        mousemove = "input",
        macro     = "macro",
        system    = "system",
        error     = "error",
        warn      = "error",
        print     = "console",
        result    = "console",
    }

    local _devBusy            = false
    local _devLastConsoleType = nil

    local _consolePanel, _watcherPanel, _keysPanel, _windowPanel
    local _consolePanelPos, _watcherPanelPos, _keysPanelPos, _windowPanelPos
    local _consoleOpen, _watcherOpen, _keysOpen, _windowOpen
    local _keysReady, _activeKeys, _activeButtons, _coordMode
    local _mousePos, _mousePoller, _windowPoller
    local _windowHistory, _windowLast, _windowMaxHistory
    local _pushMouseState

    local _camMoveAccum  = 0
    local _waitAccum     = 0
    local _waitDuration  = 0
    local _traceSuppress = false
    local _branchState   = {}

    local _devFadeTimers = {}

-- END --

-- Lifecycle --

    function MsDevTools:init()
        _jsonDir = _devBaseDir .. "json/"
        _readDir = _devBaseDir .. "readable/"

        _catPaths = {}
        _readablePaths = {}

        for _, cat in ipairs({"input", "macro", "system", "error", "console"}) do
            _catPaths[cat]      = _jsonDir .. "ms_dev_" .. cat .. ".log"
            _readablePaths[cat] = _readDir .. "ms_dev_" .. cat .. ".txt"
        end

        self:_archiveOnReload()

        _activeKeys       = {}
        _activeButtons    = {}
        _coordMode        = "screen"
        _keysReady        = false
        _windowHistory    = {}
        _windowLast       = nil
        _windowMaxHistory = 80
    end

    function MsDevTools:start()
        if not ms then return end

        ms.dev = {
            _consolePanel    = nil,
            _watcherPanel    = nil,
            _keysPanel       = nil,
            _consolePanelPos = nil,
            _watcherPanelPos = nil,
            _keysPanelPos    = nil,
            _activeKeys      = _activeKeys,
            _activeButtons   = _activeButtons,
            _coordMode       = _coordMode,
            _keysReady       = false,
        }

        setmetatable(ms.dev, {
            __index = function(t, k)
                if     k == "_consolePanel" then return _consolePanel
                elseif k == "_watcherPanel" then return _watcherPanel
                elseif k == "_keysPanel"    then return _keysPanel
                elseif k == "_keysReady"    then return _keysReady
                end
            end,
        })

        ms.dev.log = function(entry)
            self:log(entry)
        end

        ms.dev._onMacroFire = function(...)
            self:onMacroFire(...)
        end

        ms.dev._onKeyEvent = function(...)
            self:onKeyEvent(...)
        end

        ms.dev._onMouseEvent = function(...)
            self:onMouseEvent(...)
        end

        ms.dev.console = {}
        ms.dev.console.show   = function() self:showConsole() end
        ms.dev.console.hide   = function() self:hideConsole() end
        ms.dev.console.toggle = function() self:toggleConsole() end

        ms.dev.watcher = {}
        ms.dev.watcher.show   = function() self:showWatcher() end
        ms.dev.watcher.hide   = function() self:hideWatcher() end
        ms.dev.watcher.toggle = function() self:toggleWatcher() end

        ms.dev.keys = {}
        ms.dev.keys.show   = function() self:showKeys() end
        ms.dev.keys.hide   = function() self:hideKeys() end
        ms.dev.keys.toggle = function() self:toggleKeys() end

        ms.dev.window = {}
        ms.dev.window.show   = function() self:showWindow() end
        ms.dev.window.hide   = function() self:hideWindow() end
        ms.dev.window.toggle = function() self:toggleWindow() end

        ms.dev.prewarm     = function() self:prewarm() end
        ms.dev.prewarmStep = function(which) self:prewarmStep(which) end
        ms.dev.step        = function(msg) self:step(msg) end

        ms.dev._pushMouseState = function(x, y)
            self:pushMouseState(x, y)
        end

        self._origPrint = print

        _G.print = function(...)
            self._origPrint(...)

            local parts = {}

            for i = 1, select('#', ...) do
                parts[i] = tostring(select(i, ...))
            end

            self:log({
                type = "print",
                msg  = table.concat(parts, "\t"),
            })
        end
    end

-- END --

-- Archive Helpers --

    function MsDevTools:_archiveLog(path, stamp, subdir)
        if not hs.fs.attributes(path) then return end

        local sessionDir = _devArchDir .. "session_" .. stamp .. "/"
        local destDir    = sessionDir .. subdir .. "/"

        hs.fs.mkdir(_devBaseDir)
        hs.fs.mkdir(_devArchDir)
        hs.fs.mkdir(sessionDir)
        hs.fs.mkdir(destDir)

        local filename = path:match("([^/]+)$")

        if filename then
            os.rename(path, destDir .. filename)
        end
    end

    function MsDevTools:_pruneSessionArchives(limit)
        if not hs.fs.attributes(_devArchDir) then return end

        local list = {}

        for name in hs.fs.dir(_devArchDir) do
            if name:match("^session_%d%d%d%d%-%d%d%-%d%d_%d%d%d%d%d%d$") then
                table.insert(list, name)
            end
        end

        table.sort(list)

        -- Cap at 5 folders per reload so we never block the main thread.
        local pruned = 0

        while #list > limit and pruned < 5 do
            local dir = _devArchDir .. list[1]

            for _, sub in ipairs({"json", "readable"}) do
                local sp = dir .. "/" .. sub

                if hs.fs.attributes(sp) then
                    for fname in hs.fs.dir(sp) do
                        if fname ~= "." and fname ~= ".." then
                            os.remove(sp .. "/" .. fname)
                        end
                    end

                    hs.fs.rmdir(sp)
                end
            end

            hs.fs.rmdir(dir)
            table.remove(list, 1)
            pruned = pruned + 1
        end
    end

    function MsDevTools:_archiveOnReload()
        -- Prune first so we never accumulate unbounded folders.
        local limit = (type(self.archiveLimit) == "number" and self.archiveLimit >= 0)
            and self.archiveLimit or 15

        self:_pruneSessionArchives(limit)

        local stamp = os.date("%Y-%m-%d_%H%M%S")

        hs.fs.mkdir(_jsonDir)
        hs.fs.mkdir(_readDir)

        for _, p in pairs(_catPaths) do
            self:_archiveLog(p, stamp, "json")
        end

        for _, p in pairs(_readablePaths) do
            self:_archiveLog(p, stamp, "readable")
        end
    end

-- END --

-- Core Logging --

    function MsDevTools:_devWrite(entry)
        if _devBusy then return end

        _devBusy = true
        entry.ts = os.date("%H:%M:%S")

        if not entry.category then
            entry.category = _typeToCategory[entry.type] or "system"
        end

        if not entry.msg or entry.msg == "" then
            local headline = entry.event or entry.key or entry.type or "log"
            local details  = {}

            if entry.source then table.insert(details, "  source: " .. entry.source) end
            if entry.reason then table.insert(details, "  reason: " .. entry.reason) end
            if entry.output then table.insert(details, "  output: " .. tostring(entry.output):sub(1, 200)) end

            if #details > 0 then
                entry.msg = headline .. "\n" .. table.concat(details, "\n")
            else
                entry.msg = headline
            end
        end

        local ok, json = pcall(hs.json.encode, entry)

        if not ok then
            _devBusy = false
            return
        end

        local catPath = _catPaths[entry.category]

        if catPath then
            pcall(function()
                hs.fs.mkdir(_devBaseDir)
                hs.fs.mkdir(_jsonDir)

                local f = io.open(catPath, "a")

                if f then
                    f:write(json .. "\n")
                    f:close()
                end
            end)
        end

        local readPath = _readablePaths[entry.category]

        if readPath then
            pcall(function()
                hs.fs.mkdir(_devBaseDir)
                hs.fs.mkdir(_readDir)

                local f = io.open(readPath, "a")

                if f then
                    local t    = entry.type
                    local line

                    if t == "key" then
                        local arrow = entry.down and "\226\134\147" or "\226\134\145"

                        line = "[" .. entry.ts .. "] " .. arrow .. " "
                            .. (entry.key or "?") .. " (" .. tostring(entry.keyCode or "?") .. ")"

                    elseif t == "mouse" then
                        local arrow = entry.down and "\226\134\147" or "\226\134\145"
                        local pos   = ""

                        if entry.x and entry.y then
                            pos = "  " .. entry.x .. "," .. entry.y
                        end

                        line = "[" .. entry.ts .. "] " .. arrow .. " mouse:"
                            .. tostring(entry.button or "?") .. pos

                    elseif t == "scroll" then
                        line = "[" .. entry.ts .. "] \226\134\165 scroll " .. (entry.direction or "")

                    elseif t == "mousemove" then
                        line = "[" .. entry.ts .. "] \226\134\146 " .. (entry.x or "?") .. ", " .. (entry.y or "?")

                    else
                        local parts = {}

                        local function add(label, val)
                            if val ~= nil and val ~= "" then
                                parts[#parts + 1] = "  " .. label .. ": " .. tostring(val)
                            end
                        end

                        local headline = entry.msg or entry.label or entry.event or entry.type or "log"
                        local first, rest = headline:match("^([^\n]+)\n(.*)$")

                        if first then
                            headline = first
                            add("detail", rest:gsub("\n", " | "))
                        end

                        add("fromDialog", entry.fromDialog)
                        add("to",          entry.to)
                        add("status",      entry.status)
                        add("cur",         entry.cur)
                        add("trusted",     entry.trusted)
                        add("code",        entry.code)
                        add("version",     entry.version)
                        add("channel",     entry.channel)
                        add("target",      entry.target)
                        add("format",      entry.format)
                        add("id",          entry.id)
                        add("label",       entry.label)
                        add("parent",      entry.parentLabel)
                        add("trigger",     entry.trigger)

                        line = "[" .. entry.ts .. "] " .. headline

                        if #parts > 0 then
                            line = line .. "\n" .. table.concat(parts, "\n")
                        end
                    end

                    f:write(line .. "\n")
                    f:close()
                end
            end)
        end

        local t = entry.type

        if _consolePanel and t ~= "mousemove" then
            local send = false

            if t == "key" or t == "mouse" or t == "macro" then
                if _devLastConsoleType ~= t then
                    _devLastConsoleType = t
                    send = true
                end
            else
                _devLastConsoleType = nil
                send = true
            end

            if send then
                pcall(function()
                    _consolePanel:evaluateJavaScript("appendEntry(" .. json .. ")")
                end)
            end
        end

        if _watcherPanel and (t == "macro" or t == "print" or t == "error" or t == "system") then
            pcall(function()
                _watcherPanel:evaluateJavaScript("appendEntry(" .. json .. ")")
            end)
        end

        if _keysPanel and _keysReady
            and (t == "key" or t == "mouse" or t == "scroll" or t == "mousemove") then
            pcall(function()
                _keysPanel:evaluateJavaScript("appendEntry(" .. json .. ")")
            end)
        end

        _devBusy = false
    end

    function MsDevTools:log(entry)
        self:_devWrite(entry)
    end

-- END --

-- Event Hooks --

    function MsDevTools:onMacroFire(id, label, parentId, parentLabel, trigger)
        self:_devWrite({
            type        = "macro",
            id          = id,
            label       = label or id,
            parentLabel = parentLabel,
            trigger     = trigger,
        })
    end

    function MsDevTools:onKeyEvent(keyCode, keyName, isDown)
        self:_devWrite({
            type    = "key",
            key     = keyName or ("code:" .. tostring(keyCode)),
            keyCode = keyCode,
            down    = isDown,
        })

        if isDown then
            _activeKeys[keyCode] = keyName or tostring(keyCode)
        else
            _activeKeys[keyCode] = nil
        end

        if _keysPanel then
            local active = {}

            for code, name in pairs(_activeKeys) do
                table.insert(active, {
                    name = name,
                    code = code,
                })
            end

            local aok, aj = pcall(hs.json.encode, active)

            if aok then
                pcall(function()
                    _keysPanel:evaluateJavaScript("updateActiveKeys(" .. aj .. ")")
                end)
            end
        end
    end

    function MsDevTools:onMouseEvent(button, isDown, x, y)
        self:_devWrite({
            type   = "mouse",
            button = button,
            down   = isDown,
            x      = x,
            y      = y,
        })

        if isDown then
            _activeButtons[button] = true
        else
            _activeButtons[button] = nil
        end

        if _keysPanel and _keysReady then
            local active = {}

            for btn in pairs(_activeButtons) do
                table.insert(active, btn)
            end

            local aok, aj = pcall(hs.json.encode, {
                x       = x,
                y       = y,
                buttons = active,
            })

            if aok then
                pcall(function()
                    _keysPanel:evaluateJavaScript("updateMouseState(" .. aj .. ")")
                end)
            end
        end
    end

-- END --

-- Watcher Helpers --

    function MsDevTools:watcherStep(msg)
        if not _watcherPanel then return end

        local co  = coroutine.running()
        local ctx = co and ms._coroContext[co]

        if ctx and ctx.cancelled then return end

        local label = (ctx and ctx.label) or "macro"

        local ok, j = pcall(hs.json.encode, {
            type = "step",
            ts   = os.time(),
            msg  = "[" .. label .. "] " .. msg,
        })

        if ok then
            pcall(function()
                _watcherPanel:evaluateJavaScript("appendEntry(" .. j .. ")")
            end)
        end
    end

    function MsDevTools:macroLog(msg)
        local co  = coroutine.running()
        local ctx = co and ms._coroContext[co]

        if ctx and ctx.cancelled then return end

        local label = (ctx and ctx.label) or ms._pendingLabel or "macro"

        self:log({
            type     = "step",
            category = "macro",
            msg      = "[" .. label .. "] " .. msg,
        })
    end

    function MsDevTools:flushCam()
        if _camMoveAccum > 0 then
            if _watcherPanel then
                self:watcherStep("cam.move \195\151" .. _camMoveAccum)
            end

            self:macroLog("cam.move \195\151" .. _camMoveAccum)
            _camMoveAccum = 0
        end
    end

    function MsDevTools:flushWait()
        if _waitAccum > 0 then
            local msg = "wait " .. _waitDuration .. "ms"

            if _waitAccum > 1 then
                msg = msg .. " \195\151" .. _waitAccum
            end

            if _watcherPanel then
                self:watcherStep(msg)
            end

            self:macroLog(msg)
            _waitAccum = 0
        end
    end

    function MsDevTools:flushAll()
        self:flushCam()
        self:flushWait()
    end

    function MsDevTools:accCamMove()
        _camMoveAccum = _camMoveAccum + 1
    end

    function MsDevTools:accWait(duration)
        if _waitAccum > 0 and duration == _waitDuration then
            _waitAccum = _waitAccum + 1
        else
            self:flushWait()
            _waitAccum    = 1
            _waitDuration = duration
        end
    end

    function MsDevTools:setTraceSuppress(val)
        _traceSuppress = val
    end

    function MsDevTools:getTraceSuppress()
        return _traceSuppress
    end

-- END --

-- Branch Tracing --

    function MsDevTools:_traceLog(co, msg)
        local st = _branchState[co]

        if not st then return end

        table.insert(st.buffer, "[" .. os.date("%H:%M:%S") .. "] [" .. st.label .. "] " .. msg)
    end

    function MsDevTools:flushTraceBuffer(co)
        local st = _branchState[co]

        if not st or #st.buffer == 0 then return end

        pcall(function()
            hs.fs.mkdir(_devBaseDir)
            hs.fs.mkdir(_readDir)

            local f = io.open(_readablePaths["macro"], "a")

            if f then
                for _, line in ipairs(st.buffer) do
                    f:write(line .. "\n")
                end

                f:close()
            end
        end)

        if _watcherPanel then
            for _, line in ipairs(st.buffer) do
                local ok, j = pcall(hs.json.encode, {
                    type = "step",
                    ts   = os.time(),
                    msg  = line,
                })

                if ok then
                    pcall(function()
                        _watcherPanel:evaluateJavaScript("appendEntry(" .. j .. ")")
                    end)
                end
            end
        end

        st.buffer = {}
    end

    function MsDevTools:startTrace(co, label)
        if not co then return end

        _branchState[co] = {
            label  = label or "macro",
            buffer = {},
        }
    end

    function MsDevTools:stopTrace(co)
        self:flushTraceBuffer(co)

        _branchState[co] = nil
    end

-- END --

-- Panel Helpers --

    local _HIST_MAX = 300

    local function _loadDevHistory(panel, categories)
        local entries = {}

        for _, cat in ipairs(categories) do
            local path = _catPaths[cat]

            if path then
                local f = io.open(path, "r")

                if f then
                    for line in f:lines() do
                        local ok, entry = pcall(hs.json.decode, line)

                        if ok and entry then
                            entries[#entries + 1] = entry
                        end
                    end

                    f:close()
                end
            end
        end

        if #entries == 0 then return end

        table.sort(entries, function(a, b)
            return (a.ts or "") < (b.ts or "")
        end)

        while #entries > _HIST_MAX do
            table.remove(entries, 1)
        end

        local ok, json = pcall(hs.json.encode, entries)

        if ok then
            pcall(function()
                panel:evaluateJavaScript("loadHistory(" .. json .. ")")
            end)
        end
    end

    local function _devThemeJS()
        local t     = ms._theme or {}
        local parts = {}

        local function sv(prop, key)
            local val = t[key]

            if type(val) == "string" then
                if val:match("^#[0-9a-fA-F]+$") then
                    table.insert(parts, string.format("r.setProperty('%s','%s')", prop, val))
                end
            end
        end

        sv("--bg",       "bg")
        sv("--surface",  "surface")
        sv("--surface2", "surface2")
        sv("--accent",   "accent")
        sv("--text",     "text")
        sv("--mouse",    "warning")

        if type(t.radius) == "number" then
            table.insert(parts, string.format("r.setProperty('--radius','%dpx')", math.max(0, t.radius)))
        end

        local font = t.font

        if type(font) == "string" and font ~= "" and not font:match("%.[ot]tf$") and not font:match("%.woff") then
            table.insert(parts, string.format("document.body.style.fontFamily=\"'%s',Palatino,Georgia,serif\"", font))
        end

        if #parts == 0 then return "" end

        return "(function(){var r=document.documentElement.style;" .. table.concat(parts, ";") .. "})()"
    end

    local function _makeDevPanel(ucName, w, h, xOff, yOff)
        local uc     = hs.webview.usercontent.new(ucName)
        local screen = hs.screen.mainScreen():frame()
        local x      = screen.x + screen.w - w - xOff
        local y      = screen.y + yOff
        local panel  = hs.webview.new(
            { x = x, y = y, w = w, h = h },
            { developerExtrasEnabled = true },
            uc
        )

        if not panel then return nil, uc end

        pcall(function() panel:windowStyle(0) end)
        pcall(function() panel:level(hs.canvas.windowLevels.floating) end)
        pcall(function() panel:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces) end)
        pcall(function() panel:allowTextEntry(true) end)
        pcall(function() panel:shadow(true) end)

        return panel, uc, { x = x, y = y, w = w, h = h }
    end

    local function _devFadeIn(panel, key)
        if _devFadeTimers[key] then
            _devFadeTimers[key]:stop()
            _devFadeTimers[key] = nil
        end

        pcall(function() panel:alpha(0) end)

        local step, steps = 0, 6

        _devFadeTimers[key] = hs.timer.doEvery((ms._theme.fadeMs or 150) / 1000 / steps, function()
            step = step + 1

            pcall(function() panel:alpha(step / steps) end)

            if step >= steps then
                _devFadeTimers[key]:stop()
                _devFadeTimers[key] = nil
            end
        end)
    end

    local function _devFadeOut(panel, key, onDone)
        if _devFadeTimers[key] then
            _devFadeTimers[key]:stop()
            _devFadeTimers[key] = nil
        end

        local step, steps = 0, 6

        _devFadeTimers[key] = hs.timer.doEvery((ms._theme.fadeMs or 150) / 1000 / steps, function()
            step = step + 1

            pcall(function() panel:alpha(1 - (step / steps)) end)

            if step >= steps then
                _devFadeTimers[key]:stop()
                _devFadeTimers[key] = nil

                if onDone then onDone() end
            end
        end)
    end

    function MsDevTools:pushMouseState(x, y)
        if not _keysPanel then return end

        local _x   = x or (_mousePos and _mousePos.x) or 0
        local _y   = y or (_mousePos and _mousePos.y) or 0
        local mode = _coordMode or "screen"
        local tx, ty = _x, _y

        if mode == "window" or mode == "windowTR" or mode == "windowBL"
            or mode == "windowBR" or mode == "windowCenter" or mode == "ref" then

            local win = ms.getTargetWin()

            if win then
                local f = win:frame()

                if mode == "window" then
                    tx = _x - f.x
                    ty = _y - f.y

                elseif mode == "windowTR" then
                    tx = _x - (f.x + f.w)
                    ty = _y - f.y

                elseif mode == "windowBL" then
                    tx = _x - f.x
                    ty = _y - (f.y + f.h)

                elseif mode == "windowBR" then
                    tx = _x - (f.x + f.w)
                    ty = _y - (f.y + f.h)

                elseif mode == "windowCenter" then
                    tx = _x - (f.x + f.w / 2)
                    ty = _y - (f.y + f.h / 2)

                elseif mode == "ref" then
                    tx = _x - f.x
                    ty = _y - f.y
                    tx = math.floor(tx * (1680 / f.w) + 0.5)
                    ty = math.floor(ty * (1044 / f.h) + 0.5)
                end
            end

        elseif mode == "screenCenter" then
            local sf = hs.screen.mainScreen():frame()

            tx = _x - math.floor(sf.w / 2)
            ty = _y - math.floor(sf.h / 2)
        end

        local j = string.format('{"x":%d,"y":%d}', math.floor(tx), math.floor(ty))

        pcall(function()
            _keysPanel:evaluateJavaScript("updateMouseState(" .. j .. ")")
        end)
    end

-- END --

-- Console Panel --

    function MsDevTools:_buildConsolePanel()
        local ucCon = hs.webview.usercontent.new("msConsole")

        ucCon:setCallback(function(msg)
            local ok, data = pcall(hs.json.decode, msg.body)

            if not ok or type(data) ~= "table" then return end

            if data.action == "execute" and data.code then
                local fn, err = load("return " .. data.code)

                if not fn then fn, err = load(data.code) end

                if not fn then
                    self:_devWrite({
                        type = "error",
                        msg  = err or "syntax error",
                    })
                else
                    local res     = table.pack(pcall(fn))
                    local success = table.remove(res, 1)

                    if not success then
                        self:_devWrite({
                            type = "error",
                            msg  = tostring(res[1]),
                        })
                    elseif #res > 0 then
                        local parts = {}

                        for _, v in ipairs(res) do
                            parts[#parts + 1] = tostring(v)
                        end

                        self:_devWrite({
                            type = "result",
                            msg  = table.concat(parts, "\t"),
                        })
                    end
                end

            elseif data.action == "clear" then
                for _, cat in ipairs({"macro", "console", "error", "system", "input"}) do
                    local p = _catPaths[cat]
                    if p then local f = io.open(p, "w"); if f then f:close() end end

                    local r = _readablePaths[cat]
                    if r then local f = io.open(r, "w"); if f then f:close() end end
                end

            elseif data.action == "close" then
                self:hideConsole()

            elseif data.action == "openWatcher" then
                self:showWatcher()

            elseif data.action == "openKeys" then
                self:showKeys()

            elseif data.action == "move" and _consolePanelPos then
                _consolePanelPos.x = _consolePanelPos.x + (data.dx or 0)
                _consolePanelPos.y = _consolePanelPos.y + (data.dy or 0)

                if _consolePanel then
                    pcall(function() _consolePanel:frame(_consolePanelPos) end)
                end

            elseif data.action == "playSlot" and data.slot then
                ms.playSlot(data.slot)
            end
        end)

        local screen = hs.screen.mainScreen():frame()
        local w, h   = 360, 480
        local x      = screen.x + screen.w - w - 20
        local y      = screen.y + 20

        local panel = hs.webview.new(
            { x = x, y = y, w = w, h = h },
            { developerExtrasEnabled = true },
            ucCon
        )

        if not panel then return nil end

        pcall(function() panel:windowStyle(0) end)
        pcall(function() panel:level(hs.canvas.windowLevels.floating) end)
        pcall(function() panel:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces) end)
        pcall(function() panel:allowTextEntry(true) end)
        pcall(function() panel:shadow(true) end)

        local f = io.open(_home .. "/.hammerspoon/ui/ms_console.html", "r")

        if f then
            panel:html(f:read("*all"), _devBase)
            f:close()
        end

        _consolePanelPos = { x = x, y = y, w = w, h = h }

        panel:navigationCallback(function(_, action)
            if action == "navigating" then return end

            hs.timer.doAfter(0, function()
                local tj = _devThemeJS()

                if tj ~= "" then
                    pcall(function() panel:evaluateJavaScript(tj) end)
                end
            end)
        end)

        return panel
    end

    function MsDevTools:showConsole()
        if not _consolePanel then
            _consolePanel = self:_buildConsolePanel()

            if not _consolePanel then return end
        end

        _consoleOpen = true

        ms.playSlot("settingsOpen")

        _consolePanel:show()

        pcall(function() _consolePanel:bringToFront(true) end)

        _devFadeIn(_consolePanel, "console")

        hs.timer.doAfter(0.1, function()
            if not _consolePanel or not _consoleOpen then return end

            _loadDevHistory(_consolePanel, {"macro", "console", "error", "system", "input"})

            local tj = _devThemeJS()

            if tj ~= "" then
                pcall(function() _consolePanel:evaluateJavaScript(tj) end)
            end
        end)
    end

    function MsDevTools:hideConsole()
        _consoleOpen = false

        if _consolePanel then
            ms.playSlot("settingsClose")

            _devFadeOut(_consolePanel, "console", function()
                if _consolePanel then _consolePanel:hide() end
            end)
        end
    end

    function MsDevTools:toggleConsole()
        if _consoleOpen then
            self:hideConsole()
        else
            self:showConsole()
        end
    end

-- END --

-- Watcher Panel --

    function MsDevTools:_buildWatcherPanel()
        local ucWatcher = hs.webview.usercontent.new("msWatcher")

        ucWatcher:setCallback(function(msg)
            local ok, data = pcall(hs.json.decode, msg.body)

            if not ok or type(data) ~= "table" then return end

            if data.action == "clear" then
                for _, cat in ipairs({"macro", "error", "system"}) do
                    local p = _catPaths[cat]
                    if p then local f = io.open(p, "w"); if f then f:close() end end

                    local r = _readablePaths[cat]
                    if r then local f = io.open(r, "w"); if f then f:close() end end
                end

            elseif data.action == "close" then
                self:hideWatcher()

            elseif data.action == "move" and _watcherPanelPos then
                _watcherPanelPos.x = _watcherPanelPos.x + (data.dx or 0)
                _watcherPanelPos.y = _watcherPanelPos.y + (data.dy or 0)

                if _watcherPanel then
                    pcall(function() _watcherPanel:frame(_watcherPanelPos) end)
                end

            elseif data.action == "playSlot" and data.slot then
                ms.playSlot(data.slot)
            end
        end)

        local screen = hs.screen.mainScreen():frame()
        local w, h   = 360, 480
        local x      = screen.x + screen.w - w - 50
        local y      = screen.y + 44

        local panel = hs.webview.new(
            { x = x, y = y, w = w, h = h },
            { developerExtrasEnabled = true },
            ucWatcher
        )

        if not panel then return nil end

        pcall(function() panel:windowStyle(0) end)
        pcall(function() panel:level(hs.canvas.windowLevels.floating) end)
        pcall(function() panel:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces) end)
        pcall(function() panel:shadow(true) end)

        local f = io.open(_home .. "/.hammerspoon/ui/ms_watcher.html", "r")

        if f then
            panel:html(f:read("*all"), _devBase)
            f:close()
        end

        _watcherPanelPos = { x = x, y = y, w = w, h = h }

        panel:navigationCallback(function(_, action)
            if action == "navigating" then return end

            hs.timer.doAfter(0, function()
                local tj = _devThemeJS()

                if tj ~= "" then
                    pcall(function() panel:evaluateJavaScript(tj) end)
                end
            end)
        end)

        return panel
    end

    function MsDevTools:showWatcher()
        if not _watcherPanel then
            _watcherPanel = self:_buildWatcherPanel()

            if not _watcherPanel then return end
        end

        _watcherOpen = true

        ms.playSlot("settingsOpen")

        _watcherPanel:show()

        pcall(function() _watcherPanel:bringToFront(true) end)

        _devFadeIn(_watcherPanel, "watcher")

        hs.timer.doAfter(0.1, function()
            if not _watcherPanel or not _watcherOpen then return end

            _loadDevHistory(_watcherPanel, {"macro", "error", "system"})

            local tj = _devThemeJS()

            if tj ~= "" then
                pcall(function() _watcherPanel:evaluateJavaScript(tj) end)
            end
        end)
    end

    function MsDevTools:hideWatcher()
        _watcherOpen = false

        if _watcherPanel then
            ms.playSlot("settingsClose")

            _devFadeOut(_watcherPanel, "watcher", function()
                if _watcherPanel then _watcherPanel:hide() end
            end)
        end
    end

    function MsDevTools:toggleWatcher()
        if _watcherOpen then
            self:hideWatcher()
        else
            self:showWatcher()
        end
    end

-- END --

-- Keys Panel --

    function MsDevTools:_buildKeysPanel()
        local ucKeys = hs.webview.usercontent.new("msKeys")

        ucKeys:setCallback(function(msg)
            local ok, data = pcall(hs.json.decode, msg.body)

            if not ok or type(data) ~= "table" then return end

            if data.action == "clear" then
                local p = _catPaths["input"]
                if p then local f = io.open(p, "w"); if f then f:close() end end

                local r = _readablePaths["input"]
                if r then local f = io.open(r, "w"); if f then f:close() end end

            elseif data.action == "close" then
                self:hideKeys()

            elseif data.action == "ready" then
                if not _keysReady then
                    _keysReady = true

                    local _p = hs.mouse.absolutePosition()

                    _mousePos = {
                        x = math.floor(_p.x),
                        y = math.floor(_p.y),
                    }
                end

            elseif data.action == "setCoordMode" then
                _coordMode = data.mode or "screen"

                hs.timer.doAfter(0.01, function()
                    if _keysPanel then
                        pcall(function() _pushMouseState() end)
                    end
                end)

            elseif data.action == "move" and _keysPanelPos then
                _keysPanelPos.x = _keysPanelPos.x + (data.dx or 0)
                _keysPanelPos.y = _keysPanelPos.y + (data.dy or 0)

                if _keysPanel then
                    pcall(function() _keysPanel:frame(_keysPanelPos) end)
                end

            elseif data.action == "playSlot" and data.slot then
                ms.playSlot(data.slot)
            end
        end)

        local screen = hs.screen.mainScreen():frame()
        local w, h   = 360, 480
        local x      = screen.x + screen.w - w - 80
        local y      = screen.y + 68

        local panel = hs.webview.new(
            { x = x, y = y, w = w, h = h },
            { developerExtrasEnabled = true },
            ucKeys
        )

        if not panel then return nil end

        pcall(function() panel:windowStyle(0) end)
        pcall(function() panel:level(hs.canvas.windowLevels.floating) end)
        pcall(function() panel:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces) end)
        pcall(function() panel:shadow(true) end)

        local f = io.open(_home .. "/.hammerspoon/ui/ms_keys.html", "r")

        if not f then return nil end

        panel:html(f:read("*all"), _devBase)
        f:close()

        _keysPanelPos = { x = x, y = y, w = w, h = h }
        _keysReady    = false

        panel:navigationCallback(function(_, action)
            if action ~= "didNavigate" then return end

            if not _keysReady then
                _keysReady = true

                local _p = hs.mouse.absolutePosition()

                _mousePos = {
                    x = math.floor(_p.x),
                    y = math.floor(_p.y),
                }
            end
        end)

        return panel
    end

    function MsDevTools:showKeys()
        if not _keysPanel then
            _keysPanel = self:_buildKeysPanel()

            if not _keysPanel then return end
        end

        _keysOpen  = true
        _keysReady = true

        ms.playSlot("settingsOpen")

        _keysPanel:show()

        pcall(function() _keysPanel:bringToFront(true) end)

        _devFadeIn(_keysPanel, "keys")

        hs.timer.doAfter(0.1, function()
            if not _keysPanel or not _keysOpen then return end

            _loadDevHistory(_keysPanel, {"input"})

            pcall(function() _pushMouseState() end)

            local tj = _devThemeJS()

            if tj ~= "" then
                pcall(function() _keysPanel:evaluateJavaScript(tj) end)
            end
        end)

        if _mousePoller then _mousePoller:stop() end

        _mousePoller = hs.timer.doEvery(0.1, function()
            if not _keysPanel then
                if _mousePoller then
                    _mousePoller:stop()
                    _mousePoller = nil
                end

                return
            end

            local _p      = hs.mouse.absolutePosition()
            local _x, _y  = math.floor(_p.x), math.floor(_p.y)
            local prev    = _mousePos

            if not prev or _x ~= prev.x or _y ~= prev.y then
                _mousePos = { x = _x, y = _y }

                _pushMouseState(_x, _y)
            end
        end)
    end

    function MsDevTools:hideKeys()
        if _mousePoller then
            _mousePoller:stop()
            _mousePoller = nil
        end

        _keysReady = false
        _keysOpen  = false

        if _keysPanel then
            ms.playSlot("settingsClose")

            _devFadeOut(_keysPanel, "keys", function()
                if _keysPanel then _keysPanel:hide() end
            end)
        end
    end

    function MsDevTools:toggleKeys()
        if _keysOpen then
            self:hideKeys()
        else
            self:showKeys()
        end
    end

-- END --

-- Window Panel --

    function MsDevTools:_pushWindowEvent(entry)
        table.insert(_windowHistory, entry)

        if #_windowHistory > _windowMaxHistory then
            table.remove(_windowHistory, 1)
        end

        if _windowPanel then
            local ok, j = pcall(hs.json.encode, entry)

            if ok then
                pcall(function()
                    _windowPanel:evaluateJavaScript(
                        "appendEntry(" .. j .. ");updateCurrentWindow(" .. j .. ")"
                    )
                end)
            end
        end
    end

    function MsDevTools:_buildWindowPanel()
        local ucWindow = hs.webview.usercontent.new("msWindow")

        ucWindow:setCallback(function(msg)
            local ok, data = pcall(hs.json.decode, msg.body)

            if not ok or type(data) ~= "table" then return end

            if data.action == "clear" then
                _windowHistory = {}

            elseif data.action == "close" then
                self:hideWindow()

            elseif data.action == "move" and _windowPanelPos then
                _windowPanelPos.x = _windowPanelPos.x + (data.dx or 0)
                _windowPanelPos.y = _windowPanelPos.y + (data.dy or 0)

                if _windowPanel then
                    pcall(function() _windowPanel:frame(_windowPanelPos) end)
                end

            elseif data.action == "playSlot" and data.slot then
                ms.playSlot(data.slot)
            end
        end)

        local screen = hs.screen.mainScreen():frame()
        local w, h   = 360, 480
        local x      = screen.x + screen.w - w - 110
        local y      = screen.y + 68

        local panel = hs.webview.new(
            { x = x, y = y, w = w, h = h },
            { developerExtrasEnabled = true },
            ucWindow
        )

        if not panel then return nil end

        pcall(function() panel:windowStyle(0) end)
        pcall(function() panel:level(hs.canvas.windowLevels.floating) end)
        pcall(function() panel:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces) end)
        pcall(function() panel:shadow(true) end)

        local f = io.open(_home .. "/.hammerspoon/ui/ms_window.html", "r")

        if f then
            panel:html(f:read("*all"), _devBase)
            f:close()
        end

        _windowPanelPos = { x = x, y = y, w = w, h = h }

        panel:navigationCallback(function(_, action)
            if action == "navigating" then return end

            hs.timer.doAfter(0, function()
                local tj = _devThemeJS()

                if tj ~= "" then
                    pcall(function() panel:evaluateJavaScript(tj) end)
                end

                if #_windowHistory > 0 then
                    local ok, j = pcall(hs.json.encode, _windowHistory)

                    if ok then
                        pcall(function() panel:evaluateJavaScript("loadHistory(" .. j .. ")") end)
                    end
                end

                local win = hs.window.focusedWindow()

                if win then
                    local app   = (win:application() and win:application():name()) or "?"
                    local title = win:title() or ""
                    local wf    = win:frame()

                    local ok2, j2 = pcall(hs.json.encode, {
                        type  = "focus",
                        ts    = os.time(),
                        app   = app,
                        title = title,
                        w     = math.floor(wf.w),
                        h     = math.floor(wf.h),
                        x     = math.floor(wf.x),
                        y     = math.floor(wf.y),
                    })

                    if ok2 then
                        pcall(function() panel:evaluateJavaScript("updateCurrentWindow(" .. j2 .. ")") end)
                    end
                end
            end)
        end)

        return panel
    end

    function MsDevTools:showWindow()
        if not _windowPanel then
            _windowPanel = self:_buildWindowPanel()

            if not _windowPanel then return end
        end

        _windowOpen = true

        ms.playSlot("settingsOpen")

        _windowPanel:show()

        pcall(function() _windowPanel:bringToFront(true) end)

        _devFadeIn(_windowPanel, "window")

        if _windowPoller then _windowPoller:stop() end

        _windowPoller = hs.timer.doEvery(0.4, function()
            if not _windowOpen or not _windowPanel then
                if _windowPoller then
                    _windowPoller:stop()
                    _windowPoller = nil
                end

                return
            end

            local win = hs.window.focusedWindow()

            if not win then return end

            local winId = win:id()

            if winId == _windowLast then return end

            _windowLast = winId

            local app   = (win:application() and win:application():name()) or "?"
            local title = win:title() or ""
            local f     = win:frame()

            self:_pushWindowEvent({
                type  = "focus",
                ts    = os.time(),
                app   = app,
                title = title,
                w     = math.floor(f.w),
                h     = math.floor(f.h),
                x     = math.floor(f.x),
                y     = math.floor(f.y),
            })
        end)
    end

    function MsDevTools:hideWindow()
        if _windowPoller then
            _windowPoller:stop()
            _windowPoller = nil
        end

        _windowOpen = false

        if _windowPanel then
            ms.playSlot("settingsClose")

            local panel = _windowPanel

            _windowPanel = nil

            _devFadeOut(panel, "window", function()
                if panel then panel:hide() end
            end)
        end
    end

    function MsDevTools:toggleWindow()
        if _windowOpen then
            self:hideWindow()
        else
            self:showWindow()
        end
    end

-- END --

-- Prewarm --

    function MsDevTools:prewarm()
        if not _consolePanel then _consolePanel = self:_buildConsolePanel() end
        if not _watcherPanel then _watcherPanel = self:_buildWatcherPanel() end
        if not _keysPanel    then _keysPanel    = self:_buildKeysPanel() end
        if not _windowPanel  then _windowPanel  = self:_buildWindowPanel() end
    end

    function MsDevTools:prewarmStep(which)
        if     which == "console" and not _consolePanel then
            _consolePanel = self:_buildConsolePanel()

        elseif which == "watcher" and not _watcherPanel then
            _watcherPanel = self:_buildWatcherPanel()

        elseif which == "keys" and not _keysPanel then
            _keysPanel = self:_buildKeysPanel()

        elseif which == "window" and not _windowPanel then
            _windowPanel = self:_buildWindowPanel()
        end
    end

    function MsDevTools:step(msg)
        local entry = {
            type = "step",
            ts   = os.date("%H:%M:%S"),
            msg  = tostring(msg or ""),
        }

        self:log(entry)

        if _watcherPanel then
            local ok, j = pcall(hs.json.encode, entry)

            if ok then
                pcall(function()
                    _watcherPanel:evaluateJavaScript("appendEntry(" .. j .. ")")
                end)
            end
        end
    end

-- END --

-- Public Accessors --

    function MsDevTools:getPanel(name)
        if     name == "console" then return _consolePanel
        elseif name == "watcher" then return _watcherPanel
        elseif name == "keys"    then return _keysPanel
        elseif name == "window"  then return _windowPanel
        end
    end

-- END --

return MsDevTools
