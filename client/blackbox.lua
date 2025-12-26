-- Black Box Flight Data Recorder
-- Records flight telemetry for crash analysis and recovery
local QBCore = exports['qb-core']:GetCoreObject()

-- =====================================
-- BLACK BOX DATA STRUCTURE
-- =====================================

local BlackBoxData = {
    active = false,
    flightNumber = nil,
    startTime = nil,
    telemetry = {},
    events = {},
    maxEntries = 500,  -- Limit memory usage
    recordInterval = 2000  -- Record every 2 seconds during flight
}

local RecordingThread = nil

-- =====================================
-- TELEMETRY RECORDING
-- =====================================

local function RecordTelemetryPoint()
    if not CurrentPlane or not DoesEntityExist(CurrentPlane) then return end

    local coords = GetEntityCoords(CurrentPlane)
    local heading = GetEntityHeading(CurrentPlane)
    local speed = GetEntitySpeed(CurrentPlane) * 3.6  -- km/h
    local altitude = coords.z
    local heightAboveGround = GetEntityHeightAboveGround(CurrentPlane)
    local health = GetEntityHealth(CurrentPlane)
    local engineHealth = GetVehicleEngineHealth(CurrentPlane)

    local point = {
        timestamp = GetGameTimer(),
        coords = { x = coords.x, y = coords.y, z = coords.z },
        heading = heading,
        speed = math.floor(speed),
        altitude = math.floor(altitude),
        agl = math.floor(heightAboveGround),  -- Above Ground Level
        health = health,
        engineHealth = math.floor(engineHealth),
        phase = FlightPhase or 'unknown'
    }

    table.insert(BlackBoxData.telemetry, point)

    -- Trim old entries if exceeding max
    if #BlackBoxData.telemetry > BlackBoxData.maxEntries then
        table.remove(BlackBoxData.telemetry, 1)
    end
end

local function RecordEvent(eventType, data)
    local event = {
        timestamp = GetGameTimer(),
        type = eventType,
        data = data or {}
    }
    table.insert(BlackBoxData.events, event)

    if Config.Debug then
        print('[dps-airlines] BlackBox Event: ' .. eventType)
    end
end

-- =====================================
-- BLACK BOX CONTROL
-- =====================================

function StartBlackBox(flightNumber)
    if BlackBoxData.active then return end

    BlackBoxData = {
        active = true,
        flightNumber = flightNumber,
        startTime = GetGameTimer(),
        telemetry = {},
        events = {},
        maxEntries = 500,
        recordInterval = 2000
    }

    RecordEvent('FLIGHT_START', {
        flightNumber = flightNumber,
        plane = GetCurrentPlaneName and GetCurrentPlaneName() or 'unknown'
    })

    -- Start recording thread
    RecordingThread = CreateThread(function()
        while BlackBoxData.active do
            RecordTelemetryPoint()
            Wait(BlackBoxData.recordInterval)
        end
    end)

    if Config.Debug then
        print('[dps-airlines] BlackBox recording started for flight ' .. flightNumber)
    end
end

function StopBlackBox(reason)
    if not BlackBoxData.active then return end

    RecordEvent('FLIGHT_END', {
        reason = reason or 'normal',
        duration = GetGameTimer() - BlackBoxData.startTime
    })

    -- Save to server
    TriggerServerEvent('dps-airlines:server:saveBlackBox', {
        flightNumber = BlackBoxData.flightNumber,
        startTime = BlackBoxData.startTime,
        endTime = GetGameTimer(),
        telemetry = BlackBoxData.telemetry,
        events = BlackBoxData.events
    })

    BlackBoxData.active = false

    if Config.Debug then
        print('[dps-airlines] BlackBox recording stopped: ' .. (reason or 'normal'))
    end
end

function RecordBlackBoxEvent(eventType, data)
    if BlackBoxData.active then
        RecordEvent(eventType, data)
    end
end

-- =====================================
-- CRASH DETECTION & RECOVERY
-- =====================================

local CrashRecoveryData = nil

RegisterNetEvent('dps-airlines:client:planeCrashed', function(data)
    if not BlackBoxData.active then return end

    RecordEvent('CRASH', {
        coords = data.coords,
        phase = data.phase,
        health = GetEntityHealth(CurrentPlane) if CurrentPlane else 0
    })

    -- Stop recording
    StopBlackBox('crash')

    -- Store crash data for recovery prompt
    CrashRecoveryData = {
        flightNumber = BlackBoxData.flightNumber,
        lastPosition = BlackBoxData.telemetry[#BlackBoxData.telemetry],
        destination = CurrentFlight and CurrentFlight.to or nil,
        passengers = CurrentFlight and CurrentFlight.passengers or 0,
        cargo = CurrentFlight and CurrentFlight.cargo or 0
    }

    -- Notify server of crash
    TriggerServerEvent('dps-airlines:server:flightCrashed', {
        flightNumber = data.flightNumber,
        coords = data.coords,
        phase = data.phase
    })

    Wait(5000)

    -- Offer recovery option
    if CrashRecoveryData then
        local alert = lib.alertDialog({
            header = 'Flight Incident Recorded',
            content = string.format([[
**Flight %s crashed**

The black box has recorded all flight data.
Your insurance may cover a replacement aircraft.

Would you like to continue your assignment with a new aircraft?

*Note: Crash data has been logged for review.*
            ]], CrashRecoveryData.flightNumber),
            centered = true,
            cancel = true,
            labels = {
                confirm = 'Request New Aircraft',
                cancel = 'End Shift'
            }
        })

        if alert == 'confirm' then
            TriggerServerEvent('dps-airlines:server:requestRecoveryAircraft', CrashRecoveryData)
        end

        CrashRecoveryData = nil
    end
end)

-- =====================================
-- FLIGHT PHASE EVENTS
-- =====================================

-- Hook into flight phase changes
local originalSetFlightPhase = SetFlightPhase
function SetFlightPhase(phase)
    if BlackBoxData.active then
        RecordEvent('PHASE_CHANGE', {
            from = FlightPhase,
            to = phase
        })
    end
    originalSetFlightPhase(phase)
end

-- =====================================
-- EMERGENCY EVENTS
-- =====================================

function RecordEmergency(emergencyType, details)
    RecordEvent('EMERGENCY', {
        type = emergencyType,
        details = details
    })

    lib.notify({
        title = 'Black Box',
        description = 'Emergency event recorded',
        type = 'warning'
    })
end

-- =====================================
-- EVENT HANDLERS
-- =====================================

RegisterNetEvent('dps-airlines:client:flightStarted', function(data)
    StartBlackBox(data.flightNumber)
end)

RegisterNetEvent('dps-airlines:client:flightCompleted', function(data)
    StopBlackBox('completed')
end)

-- Handle unexpected disconnects
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        if BlackBoxData.active then
            StopBlackBox('resource_stop')
        end
    end
end)

-- =====================================
-- REPLAY SYSTEM (For Crash Analysis)
-- =====================================

function GetFlightReplay(flightNumber, callback)
    lib.callback('dps-airlines:server:getBlackBoxData', false, function(data)
        if data then
            callback(data)
        else
            lib.notify({
                title = 'Black Box',
                description = 'No flight data found',
                type = 'error'
            })
        end
    end, flightNumber)
end

function ShowCrashReport()
    local history = lib.callback.await('dps-airlines:server:getCrashHistory', false)

    if not history or #history == 0 then
        lib.notify({ title = 'Black Box', description = 'No crash reports found', type = 'inform' })
        return
    end

    local options = {}
    for _, crash in ipairs(history) do
        table.insert(options, {
            title = crash.flight_number,
            description = string.format('Crashed at %s | %s',
                crash.crash_time,
                crash.phase or 'Unknown phase'
            ),
            icon = 'fas fa-exclamation-triangle',
            metadata = {
                { label = 'Location', value = crash.location or 'Unknown' },
                { label = 'Cause', value = crash.cause or 'Under investigation' }
            }
        })
    end

    lib.registerContext({
        id = 'airlines_crash_reports',
        title = 'Flight Incident Reports',
        options = options
    })

    lib.showContext('airlines_crash_reports')
end

-- =====================================
-- EXPORTS
-- =====================================

exports('StartBlackBox', StartBlackBox)
exports('StopBlackBox', StopBlackBox)
exports('RecordBlackBoxEvent', RecordBlackBoxEvent)
exports('RecordEmergency', RecordEmergency)
exports('GetFlightReplay', GetFlightReplay)
exports('ShowCrashReport', ShowCrashReport)
exports('IsRecording', function() return BlackBoxData.active end)
