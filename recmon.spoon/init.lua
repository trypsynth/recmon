local inspect = hs.inspect

local recmon = {}

recmon.name = "Resource Monitor"
recmon.version = "1.3"
recmon.author = "Quin Marilyn <quin.marilyn05@gmail.com>"
recmon.license = "MIT"

local synth = hs.speech.new()

local function speak(text)
    if hs.application.get("VoiceOver") ~= nil then
        hs.osascript.applescript(
            "tell application \"VoiceOver\" to output \"" .. text:gsub("\"", "\\\"") .. "\""
        )
    else
        synth:speak(text)
    end
end

local function round(num, numDecimalPlaces)
    local mult = 10 ^ (numDecimalPlaces or 2)
    return math.floor(num * mult + 0.5) / mult
end

local function bytesToHuman(size)
    local units = { "B", "KB", "MB", "GB", "TB" }
    local finalUnit = ""
    for _, unit in ipairs(units) do
        if size < 1024.0 then
            finalUnit = unit
            break
        end
        size = size / 1024.0
    end
    return round(size) .. finalUnit
end

local function percent(n1, n2)
    return round((n1 / n2) * 100)
end

local function minutesToHours(minutes)
    local hours = minutes / 60
    local minutes = minutes % 60
    local res = ""
    if hours > 0 then
        res = math.floor(hours) .. " hours, "
    end
    res = res .. math.floor(minutes) .. " minutes"
    return res
end

local function cpuUsage()
    local usage = hs.host.cpuUsage()
    speak(
        "Average CPU load "
            .. round(usage.overall.active)
            .. "%. User: "
            .. round(usage.overall.user)
            .. "%. System: "
            .. round(usage.overall.system)
            .. "%"
    )
end

local function ramUsage() end

local function diskUsage()
    local disks = hs.host.volumeInformation()
    local res = {}
    for k, v in pairs(disks) do
        local str = v["NSURLVolumeLocalizedNameKey"]
            .. " ("
            .. v["NSURLVolumeLocalizedFormatDescriptionKey"]
            .. "): "
            .. bytesToHuman(
                v["NSURLVolumeTotalCapacityKey"]
                    - v["NSURLVolumeAvailableCapacityKey"]
            )
            .. " of "
            .. bytesToHuman(v["NSURLVolumeTotalCapacityKey"])
            .. " used ("
            .. percent(
                v["NSURLVolumeTotalCapacityKey"]
                    - v["NSURLVolumeAvailableCapacityKey"],
                v["NSURLVolumeTotalCapacityKey"]
            )
            .. "%. "
        table.insert(res, str)
    end
    res = table.concat(res)
    speak(res)
end

local function osVersion()
    speak(hs.host.operatingSystemVersionString())
end

local function uptime()
    speak(hs.execute(hs.spoons.scriptPath() .. "/uptime.sh"))
end

-- Battery time-remaining, working around a macOS 26/27 regression.
--
-- hs.battery.timeRemaining() / timeToFullCharge() (and `pmset`, Activity Monitor)
-- read the high-level IOPowerSources API, which on macOS 27 returns -1 /
-- "no estimate". But the battery firmware's own estimate is still published in
-- the raw AppleSmartBattery IORegistry node, so we read that directly. We also
-- read the raw charge/capacity so we can compute an independent estimate as a
-- fallback (and cross-check) if the firmware value is missing.
local function readSmartBattery()
    local out = hs.execute("/usr/sbin/ioreg -rn AppleSmartBattery -w0 2>/dev/null")
    if not out or out == "" then return nil end
    local function num(key)
        -- these fields are all small positive integers (mAh / minutes), so plain
        -- tonumber is safe; we deliberately do NOT parse Amperage from here, as it
        -- arrives as an unsigned 64-bit value that loses precision as a Lua float.
        local v = out:match('"' .. key .. '"%s*=%s*(%d+)')
        return v and tonumber(v)
    end
    return {
        remaining  = num("RemainingCapacity"),      -- mAh left
        full       = num("NominalChargeCapacity")   -- mAh at full (wear-adjusted)
                     or num("AppleRawMaxCapacity"),
        avgToEmpty = num("AvgTimeToEmpty"),          -- firmware estimate, minutes
        avgToFull  = num("AvgTimeToFull"),           -- firmware estimate, minutes
    }
end

-- Returns estimated minutes remaining (until empty when charging=false, until
-- full when charging=true), or nil if it genuinely can't be determined yet.
--
-- Three layers, best source first, so this is a no-op change on macOS <= 26:
--   1. The standard hs.battery API. On macOS <= 26 (and if Apple ever fixes 27)
--      this returns a valid estimate and we use it, unchanged from before.
--   2. macOS 27 breaks that API (returns -1). Fall back to the battery firmware's
--      own estimate, read from the raw AppleSmartBattery IORegistry node.
--   3. If even that is missing, compute it ourselves from raw charge / current.
local function batteryMinutesRemaining(charging)
    -- Layer 1: the OS estimate. -1 means "no estimate" (the macOS 27 regression);
    -- timeToFullCharge() also reports 0 when not actively charging.
    local apiValue = charging and hs.battery.timeToFullCharge()
                              or hs.battery.timeRemaining()
    if apiValue and apiValue > 0 then
        return apiValue
    end

    -- Layers 2 & 3: workaround for the broken API.
    local sb = readSmartBattery() or {}
    -- 65535 (0xFFFF) and 0 are the firmware's "not available" sentinels.
    local function firmwareValid(t) return t ~= nil and t > 0 and t < 65535 end
    local amperage = hs.battery.amperage() -- signed mA: <0 discharging, >0 charging
    if charging then
        if firmwareValid(sb.avgToFull) then return sb.avgToFull end
        if sb.full and sb.remaining and amperage and amperage > 0 then
            return (sb.full - sb.remaining) / amperage * 60
        end
    else
        if firmwareValid(sb.avgToEmpty) then return sb.avgToEmpty end
        if sb.remaining and amperage and amperage < 0 then
            return sb.remaining / math.abs(amperage) * 60
        end
    end
    return nil
end

local function batteryPercentage()
    local res = math.floor(hs.battery.percentage()) .. "%, "
    local source = hs.battery.powerSource()
    if source == "AC Power" then
        if hs.battery.isCharging() then
            res = res .. "Charging. "
            local mins = batteryMinutesRemaining(true)
            if mins then
                res = res .. minutesToHours(mins) .. " until full."
            else
                res = res .. "Calculating time until full."
            end
        else
            res = res .. "Plugged in, not charging."
        end
    elseif source == "Battery Power" then
        res = res .. "Not charging. "
        local mins = batteryMinutesRemaining(false)
        if mins then
            res = res .. minutesToHours(mins) .. " until empty."
        else
            res = res .. "Calculating time until empty."
        end
    else
        res = "Unable to obtain battery information."
    end
    speak(res)
end

local function audioDevices()
    local inputDevice = hs.audiodevice.defaultInputDevice()
    local res = "Input: "
        .. inputDevice:name()
        .. " (volume "
        .. math.floor(inputDevice:volume())
        .. "%)"
    if inputDevice:muted() then
        res = res .. " Muted"
    end
    local outputDevice = hs.audiodevice.defaultOutputDevice()
    res = res
        .. ". Output: "
        .. outputDevice:name()
        .. " ("
        .. math.floor(outputDevice:volume())
        .. "%)."
    speak(res)
end

local function pasteboard()
    local res = hs.pasteboard.getContents()
    if res == nil or #res == 0 then
        speak("The clipboard is empty.")
    elseif #res >= 2048 then
        speak(
            "The clipboard contains a large portion of text. It is "
                .. #res
                .. " characters long."
        )
    else
        speak("Clipboard contains: " .. res)
    end
end

local cpuHotkey = hs.hotkey.new("ctrl-shift", "1", cpuUsage)
local ramHotkey = hs.hotkey.new("ctrl-shift", "2", ramUsage)
local diskHotkey = hs.hotkey.new("ctrl-shift", "3", diskUsage)
local osHotkey = hs.hotkey.new("ctrl-shift", "4", osVersion)
local uptimeHotkey = hs.hotkey.new("ctrl-shift", "5", uptime)
local batteryHotkey = hs.hotkey.new("ctrl-shift", "6", batteryPercentage)
local audioDeviceHotkey = hs.hotkey.new("ctrl-shift", "7", audioDevices)
local pasteboardHotkey = hs.hotkey.new("ctrl-shift", "8", pasteboard)

function recmon.init() end

function recmon.start()
    cpuHotkey:enable()
    ramHotkey:enable()
    diskHotkey:enable()
    osHotkey:enable()
    uptimeHotkey:enable()
    batteryHotkey:enable()
    audioDeviceHotkey:enable()
    pasteboardHotkey:enable()
end

function recmon.stop()
    cpuHotkey:disable()
    ramHotkey:disable()
    diskHotkey:disable()
    osHotkey:disable()
    uptimeHotkey:disable()
    batteryHotkey:disable()
    audioDeviceHotkey:disable()
    pasteboardHotkey:disable()
end

return recmon
