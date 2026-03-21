-- Voice Dictation Module for Hammerspoon
-- Hotkeys:
--   Caps Lock tap (<300ms): Toggle mode (start/stop)
--   Caps Lock hold (>300ms): Push-to-talk (hold to record)
--   Ctrl+Shift+Space: Toggle mode (legacy)
--
-- Requires: Caps Lock remapped to F18 via hidutil (see setup-capslock.sh)
-- Requires: dictate-daemon running in background

local module = {}

function module.setup()
    local controlFile = "/tmp/dictation_control"
    local pidFile = "/tmp/dictation.pid"
    local daemonPid = "/tmp/dictation_daemon.pid"

    local HOLD_THRESHOLD = 0.3  -- seconds
    local f18Down = false
    local f18DownTime = nil
    local f18Timer = nil
    local pushToTalkActive = false

    local function isDaemonRunning()
        local daemon = io.open(daemonPid, "r")
        if daemon then
            daemon:close()
            return true
        end
        return false
    end

    local function isRecording()
        local recording = io.open(pidFile, "r")
        if recording then
            recording:close()
            return true
        end
        return false
    end

    local function sendControl(action)
        local f = io.open(controlFile, "w")
        if f then
            f:write(action)
            f:close()
            return true
        end
        return false
    end

    local function toggleRecording()
        if not isDaemonRunning() then
            hs.alert.show("Start daemon first:\ndictate-daemon &")
            return
        end

        if isRecording() then
            hs.alert.show("Stopping...")
            sendControl("stop")
        else
            hs.alert.show("Recording...")
            sendControl("start")
        end
    end

    local function startPushToTalk()
        if not isDaemonRunning() then
            hs.alert.show("Start daemon first:\ndictate-daemon &")
            return
        end
        pushToTalkActive = true
        hs.alert.show("Push-to-talk...")
        sendControl("start")
    end

    local function stopPushToTalk()
        if pushToTalkActive and isDaemonRunning() then
            hs.alert.show("Stopping...")
            sendControl("stop")
        end
        pushToTalkActive = false
    end

    -- F18 (Caps Lock): Tap vs Hold detection
    local f18Tap = hs.eventtap.new({hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp}, function(event)
        local keyCode = event:getKeyCode()
        local eventType = event:getType()

        -- F18 keyCode is 79
        if keyCode ~= 79 then
            return false
        end

        if eventType == hs.eventtap.event.types.keyDown then
            if f18Down then
                return true  -- Suppress repeated keyDown events
            end

            f18Down = true
            f18DownTime = hs.timer.secondsSinceEpoch()
            pushToTalkActive = false

            f18Timer = hs.timer.doAfter(HOLD_THRESHOLD, function()
                if f18Down then
                    startPushToTalk()
                end
            end)

            return true

        elseif eventType == hs.eventtap.event.types.keyUp then
            f18Down = false

            if f18Timer then
                f18Timer:stop()
                f18Timer = nil
            end

            if pushToTalkActive then
                stopPushToTalk()
            else
                toggleRecording()
            end

            return true
        end

        return false
    end)

    f18Tap:start()

    -- Restart eventtap after sleep/wake (macOS can disable it)
    local sleepWatcher = hs.caffeinate.watcher.new(function(event)
        if event == hs.caffeinate.watcher.systemDidWake
           or event == hs.caffeinate.watcher.screensDidUnlock then
            hs.timer.doAfter(1, function()
                if not f18Tap:isEnabled() then
                    f18Tap:start()
                    print("Dictation: restarted eventtap after wake")
                end
            end)
        end
    end)
    sleepWatcher:start()

    -- Legacy hotkey: Ctrl+Shift+Space
    hs.hotkey.bind({"ctrl", "shift"}, "space", toggleRecording)

    print("Dictation module loaded:")
    print("  Caps Lock tap (<300ms):  Toggle mode")
    print("  Caps Lock hold (>300ms): Push-to-talk")
    print("  Ctrl+Shift+Space: Toggle mode (legacy)")
end

return module
