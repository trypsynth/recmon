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

local function ramUsage()
    local stats = hs.host.vmStat()
    local totalMemory = stats.memSize
    local reclaimable = (stats.pagesFree + stats.pagesInactive + stats.pagesSpeculative + stats.pagesPurgeable) * stats.pageSize
    local usedMemory = totalMemory - reclaimable
    local res = "Physical: "
        .. bytesToHuman(usedMemory)
        .. " of "
        .. bytesToHuman(totalMemory)
        .. " used ("
        .. percent(usedMemory, totalMemory)
        .. "%). "
    local swapOutput = hs.execute("sysctl -n vm.swapusage")
    local swapUsed = swapOutput:match("used = ([%d%.]+)M")
    local swapUsedMB = tonumber(swapUsed) or 0
    if swapUsedMB > 0 then
        local swapTotal = swapOutput:match("total = ([%d%.]+)M")
        local swapTotalMB = tonumber(swapTotal) or 0
        res = res
            .. "Swap: "
            .. bytesToHuman(swapUsedMB * 1024 * 1024)
            .. " of "
            .. bytesToHuman(swapTotalMB * 1024 * 1024)
            .. " used."
    else
        res = res .. "Swap: 0 bytes used."
    end
    speak(res)
end

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

local function batteryPercentage()
    local res = math.floor(hs.battery.percentage()) .. "%, "
    local source = hs.battery.powerSource()
    if source == "AC Power" then
        res = res .. "Charging. "
        local timeRemaining = hs.battery.timeToFullCharge()
        if timeRemaining == -1 then
            res = res .. "Calculating time remaining until full."
        else
            res = res .. minutesToHours(timeRemaining) .. " until full."
        end
    elseif source == "Battery Power" then
        res = res .. "Not charging. "
        local timeRemaining = hs.battery.timeRemaining()
        if timeRemaining == -1 then
            res = res .. "Calculating time until empty."
        else
            res = res .. minutesToHours(timeRemaining) .. " until empty."
        end
    else
        res = "Unable to obtain battery percentage."
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
