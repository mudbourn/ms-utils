-- MsAlert --
    local MsAlert = {}

    MsAlert.name    = "MsAlert"
    MsAlert.version = "1.0"

    MsAlert.maxAlerts    = 4
    MsAlert.bottomY      = 150
    MsAlert.animDuration = 0.25
    MsAlert.animSteps    = 20
-- END MsAlert --

-- State --
    local queue = {}
-- END State --

-- Helpers --
    local function screenBounds()
        local f = hs.screen.mainScreen():frame()

        return f.x, f.y, f.w, f.y + f.h
    end

    local function hexToColor(hex, default)
        if type(hex) ~= "string" then return default end

        local h = hex:match("^#?([0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])")

        if not h then return default end

        return {
            red   = tonumber(h:sub(1, 2), 16) / 255,
            green = tonumber(h:sub(3, 4), 16) / 255,
            blue  = tonumber(h:sub(5, 6), 16) / 255,
            alpha = 1,
        }
    end
-- END Helpers --

-- Canvas --
    local function makeCanvas(msg, x, y, w, alpha)
        local padding = 16
        local lineH   = 20
        local closeW  = 22

        local lines = {}

        for line in (msg .. "\n"):gmatch("([^\n]*)\n") do
            table.insert(lines, line)
        end

        local longestLine = 0

        for _, line in ipairs(lines) do
            if #line > longestLine then longestLine = #line end
        end

        local charW = 8
        local cw    = math.max(200, math.min(600, longestLine * charW + padding * 2)) + closeW
        local textH = #lines * lineH
        local ch    = textH + padding * 2
        local cx    = x + (w - cw) / 2

        local theme      = ms._theme or {}
        local bgColor     = hexToColor(theme.surface2, { red = 0.11, green = 0.063, blue = 0.047, alpha = 1 })
        local txtColor    = hexToColor(theme.text,     { red = 0.94, green = 0.87, blue = 0.69, alpha = 1 })
        local accentColor = hexToColor(theme.accent,   { red = 0.77, green = 0.10, blue = 0.10, alpha = 1 })
        local radius      = type(theme.radius) == "number" and math.max(0, theme.radius) or 3

        local font = "Helvetica"

        if type(theme.font) == "string" and #theme.font > 0
            and not theme.font:find("[/\\]") then
            font = theme.font
        end

        bgColor.alpha = 0.88

        local c = hs.canvas.new({ x = cx, y = y, w = cw, h = ch })

        c:level(hs.canvas.windowLevels.popUpMenu or hs.canvas.windowLevels.status or 25)
        c:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
        c:alpha(alpha or 0)

        c:appendElements(
            {
                type                = "rectangle",
                action              = "strokeAndFill",
                fillColor           = bgColor,
                strokeColor         = accentColor,
                strokeWidth         = 1,
                roundedRectRadii    = { xRadius = radius, yRadius = radius },
                trackMouseEnterExit = true,
            },
            {
                type          = "text",
                text          = msg,
                textFont      = font,
                textSize      = 13,
                textColor     = txtColor,
                textAlignment = "center",
                frame         = { x = 0, y = padding + 4, w = cw, h = textH },
            },
            {
                type          = "text",
                text          = "\xe2\x9c\x95",
                textFont      = "Helvetica",
                textSize      = 10,
                textColor     = { red = txtColor.red, green = txtColor.green, blue = txtColor.blue, alpha = 0 },
                textAlignment = "center",
                frame         = { x = cw - closeW, y = 5, w = closeW - 4, h = 14 },
                trackMouseDown = true,
            }
        )

        c:show()

        local xShowColor = { red = txtColor.red, green = txtColor.green, blue = txtColor.blue, alpha = 0.45 }
        local xHideColor = { red = txtColor.red, green = txtColor.green, blue = txtColor.blue, alpha = 0 }

        local function showX()
            pcall(function() c:elementAttribute(3, "textColor", xShowColor) end)
        end

        local function hideX()
            pcall(function() c:elementAttribute(3, "textColor", xHideColor) end)
        end

        return c, ch, showX, hideX
    end
-- END Canvas --

-- Animation --
    local function animateEntry(entry, fromY, toY, fromAlpha, toAlpha, onDone)
        local step = 0

        if entry._animTimer then entry._animTimer:stop() end

        entry._animTimer = hs.timer.doEvery(MsAlert.animDuration / MsAlert.animSteps, function()
            step = step + 1

            local t    = step / MsAlert.animSteps
            local ease = 1 - (1 - t) ^ 3
            local y     = fromY     + (toY     - fromY)     * ease
            local alpha = fromAlpha + (toAlpha - fromAlpha) * ease

            if entry.canvas then
                local f = entry.canvas:frame()

                entry.canvas:frame({ x = f.x, y = y, w = f.w, h = f.h })
                entry.canvas:alpha(alpha)
            end

            if step >= MsAlert.animSteps then
                entry._animTimer:stop()
                entry._animTimer = nil

                if onDone then onDone() end
            end
        end)
    end

    local function fadeOut(entry, onDone)
        if not entry.canvas then
            if onDone then onDone() end

            return
        end

        local f = entry.canvas:frame()

        animateEntry(entry, f.y, f.y, 1, 0, onDone)
    end
-- END Animation --

-- Dismiss --
    -- Forward-declared so redraw's mouseCallback closure can reference it.
    local dismissEntry

    dismissEntry = function(entry)
        if entry.timer then entry.timer:stop(); entry.timer = nil end

        for i, e in ipairs(queue) do
            if e == entry then
                table.remove(queue, i)

                fadeOut(e, function()
                    if e.canvas then e.canvas:delete() end
                end)

                MsAlert:_redraw(nil)

                break
            end
        end
    end

    function MsAlert:dismissAll()
        for i = #queue, 1, -1 do
            local e = queue[i]

            if e.timer      then e.timer:stop();      e.timer      = nil end
            if e._animTimer then e._animTimer:stop(); e._animTimer = nil end
            if e.canvas     then pcall(function() e.canvas:delete() end); e.canvas = nil end
        end

        queue = {}
    end

    function MsAlert:recolor()
        local theme      = ms._theme or {}
        local bgColor    = hexToColor(theme.surface2, { red = 0.11, green = 0.063, blue = 0.047, alpha = 1 })
        local txtColor   = hexToColor(theme.text,     { red = 0.94, green = 0.87, blue = 0.69, alpha = 1 })
        local accentColor = hexToColor(theme.accent,   { red = 0.77, green = 0.10, blue = 0.10, alpha = 1 })
        bgColor.alpha = 0.88

        for _, e in ipairs(queue) do
            if e.canvas then
                pcall(function() e.canvas:elementAttribute(1, "fillColor", bgColor) end)
                pcall(function() e.canvas:elementAttribute(1, "strokeColor", accentColor) end)
                pcall(function() e.canvas:elementAttribute(2, "textColor", txtColor) end)
            end
        end
    end

    function MsAlert:dismissById(id)
        for i = #queue, 1, -1 do
            local e = queue[i]

            if e.id == id then
                if e.timer      then e.timer:stop();      e.timer      = nil end
                if e._animTimer then e._animTimer:stop(); e._animTimer = nil end
                if e.canvas     then pcall(function() e.canvas:delete() end); e.canvas = nil end

                table.remove(queue, i)
            end
        end
    end

    function MsAlert:updateById(id, msg, duration)
        for i = #queue, 1, -1 do
            local e = queue[i]

            if e.id == id then
                if e.canvas then pcall(function() e.canvas:delete() end); e.canvas = nil end

                e.msg = msg

                -- Move to top only if not low-priority
                if e.priority ~= "low" then
                    table.remove(queue, i)
                    table.insert(queue, e)
                end

                self:_redraw(e)

                if e.timer then e.timer:stop() end

                e.timer = hs.timer.doAfter(duration, function()
                    dismissEntry(e)
                end)

                return true
            end
        end

        return false
    end
-- END Dismiss --

-- Redraw --
    function MsAlert:_redraw(newEntry)
        local sx, sy, sw, sBottom = screenBounds()

        for _, entry in ipairs(queue) do
            if not entry.h then
                local lines = {}

                for line in (entry.msg .. "\n"):gmatch("([^\n]*)\n") do
                    table.insert(lines, line)
                end

                entry.h = #lines * 20 + 32
            end
        end

        local currentY = sBottom - self.bottomY

        for i = #queue, 1, -1 do
            local entry   = queue[i]
            local targetY = currentY - entry.h

            currentY = targetY - 8

            if entry == newEntry then
                if not entry.canvas then
                    local c, h, showX, hideX = makeCanvas(entry.msg, sx, sBottom - self.bottomY, sw, 0)

                    entry.canvas = c
                    entry.h      = h
                    entry._showX = showX
                    entry._hideX = hideX

                    c:mouseCallback(function(cvs, msg, id, cx, cy)
                        if msg == "mouseEnter" then
                            entry._hovered = true

                            if entry.timer then entry.timer:stop(); entry.timer = nil end
                            if entry._showX then entry._showX() end

                        elseif msg == "mouseExit" and id == 1 then
                            entry._hovered = false

                            if entry._hideX then entry._hideX() end

                            if not entry.timer then
                                entry.timer = hs.timer.doAfter(2, function()
                                    dismissEntry(entry)
                                end)
                            end

                        elseif msg == "mouseDown" and id == 3 then
                            dismissEntry(entry)
                        end
                    end)
                end

                animateEntry(entry, sBottom - self.bottomY, targetY, 0, 1, nil)
            else
                if entry.canvas then
                    local f = entry.canvas:frame()

                    animateEntry(entry, f.y, targetY, 1, 1, nil)
                end
            end
        end
    end
-- END Redraw --

-- Call --
    function MsAlert:__call(msg, duration, noDefaultSound, opts)
        -- Suppress all toasts until loading screen completes
        if not ms._startupSoundDone then return end

        duration = duration or 5

        local src = opts and opts.source or "system"
        local id  = opts and opts.id or nil

        -- Auto-replace: if a toast with this id already exists, update it in-place
        if id then
            if self:updateById(id, msg, duration) then return end
        end

        if ms.dev and ms.dev.log and id ~= "_state" then
            local isError = msg and (
                msg:find("[Ff]ailed") or msg:find("[Ee]rror")
                or msg:find("[Cc]ould not") or msg:find("[Cc]annot")
                or msg:find("[Rr]ejected") or msg:find("[Dd]enied")
                or msg:find("[Aa]borted")
            )

            ms.dev.log({
                type   = isError and "error" or "system",
                event  = "alert",
                source = src,
                msg    = (msg or ""):sub(1, 200),
            })
        end

        if loadfinish == 1 and not noDefaultSound then
            ms.playSlot("alert")
        end

        if #queue >= self.maxAlerts then
            local oldest = queue[1]

            if oldest._animTimer then oldest._animTimer:stop() end
            if oldest.timer then oldest.timer:stop() end

            fadeOut(oldest, function()
                if oldest.canvas then oldest.canvas:delete() end
            end)

            table.remove(queue, 1)
        end

        local entry = {
            msg      = msg,
            canvas   = nil,
            timer    = nil,
            h        = nil,
            id       = opts and opts.id or nil,
            source   = src,
            priority = opts and opts.priority or "normal",
        }

        -- Low-priority toasts go to the bottom of the queue
        -- _redraw iterates #queue→1, positioning from bottom to top
        -- queue[1]=bottom, queue[#queue]=top
        if entry.priority == "low" then
            table.insert(queue, entry)
        else
            table.insert(queue, 1, entry)
        end
        self:_redraw(entry)

        entry.timer = hs.timer.doAfter(duration, function()
            dismissEntry(entry)
        end)
    end
-- END Call --

-- Make callable --
    setmetatable(MsAlert, {
        __call = function(self, ...)
            return self:__call(...)
        end,
    })
-- END Make callable --

return MsAlert