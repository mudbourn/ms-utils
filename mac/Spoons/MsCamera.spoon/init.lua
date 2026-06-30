-- MsCamera --

    local MsCamera = {}

    MsCamera.name    = "MsCamera"
    MsCamera.version = "1.0"

    MsCamera.anchor     = nil
    MsCamera.button     = 5
    MsCamera.cachedMult = 1.0

-- END MsCamera --

-- State --

    local _lastFrame      = nil
    local _updateTimer    = nil
    local _enabled        = false
    local _uiWatcher      = nil
    local _startAttempts  = 0
    local _ratioWarnTimer = nil
    local _lastRatio      = nil

-- END State --

-- Helpers --

    function MsCamera.updateMultiplier()
        local curSens = (CUR_CAM_SENS and CUR_CAM_SENS > 0) and CUR_CAM_SENS or 1.5
        local win = ms.getRobloxWin()

        if not win then
            MsCamera.cachedMult = 1.0
            return
        end

        local f = win:frame()
        _lastRatio = f.w / f.h

        local refSens = (REF_SENS and REF_SENS > 0) and REF_SENS or 1.5
        MsCamera.cachedMult = refSens / curSens
    end

    function MsCamera.updateAnchor()
        local win = ms.getRobloxWin()
        if not win then return end

        local f = win:frame()
        if _lastFrame and math.abs(f.x - _lastFrame.x) < 2 and math.abs(f.y - _lastFrame.y) < 2
            and math.abs(f.w - _lastFrame.w) < 2 and math.abs(f.h - _lastFrame.h) < 2 then
            return
        end

        local sizeChanged = _lastFrame ~= nil
            and (math.abs(f.w - _lastFrame.w) >= 2 or math.abs(f.h - _lastFrame.h) >= 2)

        _lastFrame = { x = f.x, y = f.y, w = f.w, h = f.h }
        MsCamera.anchor = { x = f.x + (f.w / 2), y = f.y + (f.h / 2) }
        MsCamera.updateMultiplier()

        if sizeChanged then
            if _lastRatio and _lastRatio < 4/3 and not _ratioWarnTimer then
                ms.alert("Warning: Aspect ratio too narrow.\nMacros may not function correctly. Widen your Roblox window, or increase your screen resolution.", 13)
                _ratioWarnTimer = hs.timer.doAfter(15, function()
                    _ratioWarnTimer = nil
                end)
            elseif _lastRatio and loadfinish > 0 then
                ms.alert("Current aspect ratio: (" .. string.format("%.2f", _lastRatio) .. ").\nRecommended aspect ratio: >=1.33.", 8)
            end
        end
    end

    function MsCamera.scheduleUpdate()
        if _updateTimer then _updateTimer:stop() end

        _updateTimer = hs.timer.doAfter(0.5, function()
            MsCamera.updateAnchor()
        end)
    end

-- END Helpers --

-- Lifecycle --

    function MsCamera.enable()
        if _enabled then return end
        _enabled = true

        local cx, cy = ms.winCenter()

        if cx == 0 and cy == 0 then
            _startAttempts = _startAttempts + 1

            if _startAttempts < 10 then
                _enabled = false
                hs.timer.doAfter(1, function() MsCamera.enable() end)
            else
                _startAttempts = 0
                print("cam.enable: gave up after 10 attempts")
            end

            return
        end

        _startAttempts = 0
        MsCamera.updateAnchor()

        hs.timer.doAfter(0.3, function()
            if not _enabled then return end

            local currentPos = hs.mouse.absolutePosition()
            local lock   = hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.otherMouseDown, { x = currentPos.x, y = currentPos.y })
            local unlock = hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.otherMouseUp,   { x = currentPos.x, y = currentPos.y })

            if lock then
                lock:setProperty(hs.eventtap.event.properties.mouseEventButtonNumber, MsCamera.button)
                unlock:setProperty(hs.eventtap.event.properties.mouseEventButtonNumber, MsCamera.button)
                lock:post()
                hs.timer.usleep(10000)
                unlock:post()
            end
        end)
    end

    function MsCamera.disable()
        _enabled = false

        if _uiWatcher then
            _uiWatcher:stop()
            _uiWatcher = nil
        end

        if _updateTimer then
            _updateTimer:stop()
            _updateTimer = nil
        end

        MsCamera.anchor = nil
        _lastFrame      = nil
    end

    function MsCamera.move(dy, dx)
        spoon.MsDevTools:accCamMove()

        if not MsCamera.anchor then
            ms.wait(2)
            return
        end

        local m      = MsCamera.cachedMult
        local final1 = math.floor((dx * m) + (dx >= 0 and 0.5 or -0.5))
        local final2 = math.floor((dy * m) + (dy >= 0 and 0.5 or -0.5))
        local drag   = hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.otherMouseDragged, MsCamera.anchor)

        if drag then
            drag:setProperty(hs.eventtap.event.properties.mouseEventButtonNumber, MsCamera.button)
            drag:setProperty(hs.eventtap.event.properties.mouseEventDeltaX, final1)
            drag:setProperty(hs.eventtap.event.properties.mouseEventDeltaY, final2)
            drag:post()
        end
    end

-- END Lifecycle --

-- Watcher --

    function MsCamera._setupWatcher()
        local robloxApp = hs.application.get("Roblox") or hs.application.get(ms._targetApp)
        if not robloxApp then return end

        if _uiWatcher then _uiWatcher:stop() end

        _uiWatcher = robloxApp:newWatcher(function(el, event)
            MsCamera.scheduleUpdate()
        end)

        _uiWatcher:start({
            hs.uielement.watcher.windowCreated,
            hs.uielement.watcher.windowMoved,
            hs.uielement.watcher.windowResized,
            hs.uielement.watcher.mainWindowChanged,
        })
    end

-- END Watcher --

return MsCamera