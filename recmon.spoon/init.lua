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

-- macOS's name, version and build, e.g. "macOS Golden Gate, 27.0.1, build
-- 26A434". The system doesn't store the marketing name anywhere readable on
-- macOS 27 (not in the licence, the About pane's strings or the install
-- history), so it comes from this table; add new releases here.
local macOSNames = {
    [11] = "Big Sur", [12] = "Monterey", [13] = "Ventura", [14] = "Sonoma",
    [15] = "Sequoia", [26] = "Tahoe", [27] = "Golden Gate",
}

local function macOSVersion()
    local info = hs.plist.read("/System/Library/CoreServices/SystemVersion.plist") or {}
    local version = info.ProductVersion or ""
    local major = tonumber(version:match("^(%d+)"))
    local name = major and macOSNames[major]
    local extra = info.ProductVersionExtra and (" " .. info.ProductVersionExtra) or ""
    local res = "macOS" .. (name and (" " .. name) or "") .. ", " .. version .. extra
    if info.ProductBuildVersion then res = res .. ", build " .. info.ProductBuildVersion end
    speak(res .. ".")
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

local function deviceReport(label, device)
    if not device then return "No " .. label:lower() .. " device." end
    local res = label .. ": " .. device:name()
    local volume = device:volume()
    if volume then res = res .. ", volume " .. math.floor(volume + 0.5) .. "%" end
    if device:muted() then res = res .. ", muted" end
    return res .. "."
end

local function outputDevice()
    speak(deviceReport("Output", hs.audiodevice.defaultOutputDevice()))
end

local function inputDevice()
    speak(deviceReport("Input", hs.audiodevice.defaultInputDevice()))
end

-- The five processes using the most CPU right now. `top` takes a fresh
-- one-second sample, like Activity Monitor (`ps` alone reports a smoothed
-- average over the last minute or so), run in the background so Hammerspoon
-- doesn't wait. Names come from the app a process belongs to where there is
-- one, otherwise the full process name.
local friendlyProcessNames = {
    ["com.apple.WebKit.WebContent"] = "Web page content",
    ["com.apple.WebKit.GPU"] = "Web graphics",
    ["com.apple.WebKit.Networking"] = "Web networking",
}

local function processName(pid)
    local app = hs.application.applicationForPID(pid)
    if app and app:name() then return app:name() end
    local comm = hs.execute("/bin/ps -o comm= -p " .. pid) or ""
    comm = comm:gsub("%s+$", ""):match("([^/]+)$") or ""
    return friendlyProcessNames[comm] or comm, comm
end

local topTask
local function topProcesses()
    if topTask and topTask:isRunning() then return end
    topTask = hs.task.new("/usr/bin/top", function(exitCode, stdout)
        if exitCode ~= 0 or not stdout then
            speak("Couldn't read processes.")
            return
        end
        -- Two samples; the first has no CPU figures yet, so use the second.
        local samples, rows = 0, {}
        for line in stdout:gmatch("[^\n]+") do
            if line:match("^PID") then
                samples = samples + 1
            elseif samples == 2 then
                local pid, cpu = line:match("^%s*(%d+)%s+([%d%.]+)")
                if pid then table.insert(rows, {pid = tonumber(pid), cpu = tonumber(cpu)}) end
            end
        end
        local parts = {}
        for _, row in ipairs(rows) do
            local name, comm = processName(row.pid)
            if comm ~= "top" and name ~= "" then
                table.insert(parts, name .. " " .. math.floor(row.cpu + 0.5) .. "%")
            end
            if #parts == 5 then break end
        end
        speak(#parts > 0 and ("Top processes: " .. table.concat(parts, ", ") .. ".") or "No processes found.")
    end, {"-l", "2", "-s", "1", "-o", "cpu", "-n", "7", "-stats", "pid,cpu"})
    topTask:start()
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

local hotkeys = {
    hs.hotkey.new("ctrl-shift", "1", cpuUsage),
    hs.hotkey.new("ctrl-shift", "2", ramUsage),
    hs.hotkey.new("ctrl-shift", "3", diskUsage),
    hs.hotkey.new("ctrl-shift", "4", macOSVersion),
    hs.hotkey.new("ctrl-shift", "5", uptime),
    hs.hotkey.new("ctrl-shift", "6", batteryPercentage),
    hs.hotkey.new("ctrl-shift", "7", outputDevice),
    hs.hotkey.new("ctrl-shift", "8", inputDevice),
    hs.hotkey.new("ctrl-shift", "9", pasteboard),
    hs.hotkey.new("ctrl-shift", "0", topProcesses),
}

function recmon.init() end

function recmon.start()
    for _, hotkey in ipairs(hotkeys) do hotkey:enable() end
end

function recmon.stop()
    for _, hotkey in ipairs(hotkeys) do hotkey:disable() end
end

return recmon
