-- Flight & ATC System
local QBCore = exports['qb-core']:GetCoreObject()

local CurrentCallsign = nil
local HasClearance = false
local FlightPhase = 'ground' -- ground, taxiing, takeoff, cruise, approach, landed
local WeatherDelay = nil

-- =====================================
-- STATE BAG WEATHER LISTENER
-- No polling - reacts to GlobalState changes
-- =====================================

local CachedWeather = {
    weather = 'CLEAR',
    canFly = true,
    delayMinutes = 0,
    payBonus = 1.0
}

-- Listen for weather state changes from server
AddStateBagChangeHandler('airlineWeather', 'global', function(bagName, key, value)
    if not value then return end

    local oldWeather = CachedWeather
    CachedWeather = value

    -- Only notify if on duty and weather changed significantly
    if OnDuty then
        if oldWeather.canFly and not value.canFly then
            lib.notify({
                title = 'Weather Alert',
                description = value.reason or 'Flights grounded due to weather',
                type = 'error',
                duration = 10000
            })
        elseif not oldWeather.canFly and value.canFly then
            lib.notify({
                title = 'Weather Update',
                description = 'Weather has cleared - flights resumed',
                type = 'success',
                duration = 5000
            })
        elseif value.delayMinutes > 0 and oldWeather.delayMinutes == 0 then
            lib.notify({
                title = 'Weather Delay',
                description = string.format('%s conditions - %d min delays possible',
                    value.weather, value.delayMinutes),
                type = 'warning',
                duration = 7000
            })
        end
    end

    if Config.Debug then
        print('[dps-airlines] Weather state updated: ' .. json.encode(value))
    end
end)

-- Listen for ATC status changes
AddStateBagChangeHandler('atcStatus', 'global', function(bagName, key, value)
    if not value then return end

    if OnDuty then
        if value == 'closed' then
            lib.notify({
                title = 'ATC',
                description = 'ATC services temporarily unavailable',
                type = 'warning'
            })
        elseif value == 'busy' then
            lib.notify({
                title = 'ATC',
                description = 'Heavy traffic - expect delays',
                type = 'inform'
            })
        end
    end
end)

-- Get current weather from cache (no callback needed)
function GetCachedWeather()
    return CachedWeather
end

exports('GetCachedWeather', GetCachedWeather)

-- =====================================
-- ALTITUDE-BASED THROTTLING SYSTEM
-- Optimizes CPU by reducing checks at cruising altitude
-- =====================================

local ThrottleTiers = {
    ground = 100,       -- On ground or <50m - high precision for markers/interactions
    lowAltitude = 500,  -- 50-200m - approaching/departing
    midAltitude = 1000, -- 200-500m - climbing/descending
    cruising = 5000     -- >500m - deep sleep, just check for crash/destination
}

local currentThrottleRate = ThrottleTiers.ground
local lastAltitude = 0
local lastSpeed = 0

-- Get optimal tick rate based on flight state
local function GetFlightThrottleRate()
    if not CurrentPlane or not DoesEntityExist(CurrentPlane) then
        return ThrottleTiers.ground
    end

    local ped = PlayerPedId()
    if not IsPedInVehicle(ped, CurrentPlane, false) then
        return ThrottleTiers.ground
    end

    local altitude = GetEntityCoords(CurrentPlane).z
    local heightAboveGround = GetEntityHeightAboveGround(CurrentPlane)
    lastAltitude = heightAboveGround
    lastSpeed = GetEntitySpeed(CurrentPlane) * 3.6 -- km/h

    -- Use height above ground for more accurate detection
    if heightAboveGround < 50.0 then
        return ThrottleTiers.ground
    elseif heightAboveGround < 200.0 then
        return ThrottleTiers.lowAltitude
    elseif heightAboveGround < 500.0 then
        return ThrottleTiers.midAltitude
    else
        return ThrottleTiers.cruising
    end
end

-- Export for other scripts to check current throttle state
exports('GetFlightThrottleRate', function()
    return currentThrottleRate, lastAltitude, lastSpeed
end)

-- =====================================
-- ATC / CLEARANCE SYSTEM
-- =====================================

function RequestClearance(runway)
    if not Config.ATC.enabled or not Config.ATC.requireClearance then
        HasClearance = true
        return true
    end

    if HasClearance then
        lib.notify({ title = 'ATC', description = 'You already have clearance', type = 'warning' })
        return true
    end

    -- Generate callsign
    CurrentCallsign = string.format('%s%d', Config.ATC.callsigns.prefix, math.random(100, 999))

    lib.notify({
        title = 'ATC Request',
        description = string.format('%s requesting clearance for %s', CurrentCallsign, runway.label),
        type = 'inform'
    })

    -- Simulate ATC delay
    local delay = math.random(Config.ATC.clearanceDelay.min, Config.ATC.clearanceDelay.max) * 1000

    local success = lib.progressBar({
        duration = delay,
        label = 'Awaiting ATC clearance...',
        useWhileDead = false,
        canCancel = true,
        disable = { move = false, car = false, combat = true }
    })

    if success then
        HasClearance = true
        lib.notify({
            title = 'ATC',
            description = string.format('%s, cleared for takeoff %s. Winds calm.', CurrentCallsign, runway.label),
            type = 'success',
            duration = 5000
        })
        return true
    else
        lib.notify({ title = 'ATC', description = 'Clearance cancelled', type = 'error' })
        return false
    end
end

function LandingClearance(airport)
    if not Config.ATC.enabled then return true end

    lib.notify({
        title = 'ATC',
        description = string.format('%s, cleared to land at %s', CurrentCallsign or 'Aircraft', airport.label),
        type = 'success',
        duration = 5000
    })

    return true
end

function ResetClearance()
    HasClearance = false
    CurrentCallsign = nil
    FlightPhase = 'ground'
end

-- =====================================
-- WEATHER SYSTEM (STATE BAG DRIVEN)
-- Uses cached state from GlobalState - no polling
-- =====================================

function CheckWeatherConditions()
    if not Config.Weather.enabled then
        return { canFly = true, delay = 0, bonus = 1.0 }
    end

    -- Use cached state from GlobalState (updated via state bag listener)
    local weather = CachedWeather

    return {
        canFly = weather.canFly,
        delay = weather.delayMinutes or 0,
        bonus = weather.payBonus or 1.0,
        weather = weather.weather,
        reason = weather.reason
    }
end

function ApplyWeatherDelay()
    local conditions = CheckWeatherConditions()

    if not conditions.canFly then
        lib.notify({
            title = 'Weather Alert',
            description = conditions.reason,
            type = 'error',
            duration = 7000
        })
        return false
    end

    if conditions.delay > 0 then
        WeatherDelay = {
            minutes = conditions.delay,
            bonus = conditions.bonus,
            weather = conditions.weather
        }

        local alert = lib.alertDialog({
            header = 'Weather Delay',
            content = string.format(
                'Due to %s conditions, there is a %d minute delay.\n\nFly anyway for a %d%% bonus, or wait for better conditions?',
                conditions.weather,
                conditions.delay,
                math.floor((conditions.bonus - 1) * 100)
            ),
            centered = true,
            cancel = true,
            labels = {
                confirm = 'Fly Now (Bonus)',
                cancel = 'Wait'
            }
        })

        if alert == 'confirm' then
            lib.notify({
                title = 'Weather Bonus',
                description = string.format('%d%% bonus applied for flying in %s', math.floor((conditions.bonus - 1) * 100), conditions.weather),
                type = 'success'
            })
            return true, conditions.bonus
        else
            return false
        end
    end

    return true, 1.0
end

-- =====================================
-- FLIGHT TRACKING
-- =====================================

function SetFlightPhase(phase)
    FlightPhase = phase

    if phase == 'takeoff' then
        lib.notify({ title = 'Flight', description = 'Takeoff', type = 'inform' })
    elseif phase == 'cruise' then
        lib.notify({ title = 'Flight', description = 'Cruising altitude reached', type = 'inform' })
    elseif phase == 'approach' then
        lib.notify({ title = 'Flight', description = 'Beginning approach', type = 'inform' })
    elseif phase == 'landed' then
        lib.notify({ title = 'Flight', description = 'Landed safely', type = 'success' })
    end
end

function GetFlightPhase()
    return FlightPhase
end

-- Monitor altitude and speed for flight phases (with dynamic throttling)
CreateThread(function()
    while true do
        -- Use dynamic throttle rate based on altitude
        currentThrottleRate = GetFlightThrottleRate()
        Wait(currentThrottleRate)

        if CurrentFlight and CurrentPlane and DoesEntityExist(CurrentPlane) then
            local ped = PlayerPedId()
            if IsPedInVehicle(ped, CurrentPlane, false) then
                local coords = GetEntityCoords(CurrentPlane)
                local altitude = coords.z
                local heightAboveGround = GetEntityHeightAboveGround(CurrentPlane)
                local speed = GetEntitySpeed(CurrentPlane) * 3.6 -- km/h

                -- Update state bag for other clients (if enabled)
                if LocalPlayer.state.flightStatus then
                    LocalPlayer.state:set('flightAltitude', heightAboveGround, true)
                    LocalPlayer.state:set('flightSpeed', speed, true)
                    LocalPlayer.state:set('flightPhase', FlightPhase, true)
                end

                if FlightPhase == 'ground' and speed > 50 then
                    SetFlightPhase('takeoff')
                elseif FlightPhase == 'takeoff' and heightAboveGround > 150 then
                    SetFlightPhase('cruise')
                elseif FlightPhase == 'cruise' then
                    -- Check proximity to destination (only at cruising intervals)
                    local dest = Locations.Airports[CurrentFlight.to]
                    if dest then
                        local dist = #(coords - vector3(dest.coords.x, dest.coords.y, dest.coords.z))
                        if dist < 2000 and heightAboveGround < 300 then
                            SetFlightPhase('approach')
                        end
                    end
                elseif FlightPhase == 'approach' and heightAboveGround < 5 and speed < 30 then
                    SetFlightPhase('landed')
                end

                -- Crash detection (check at all altitudes)
                local health = GetEntityHealth(CurrentPlane)
                if health < 100 or IsEntityDead(CurrentPlane) then
                    TriggerEvent('dps-airlines:client:planeCrashed', {
                        coords = coords,
                        flightNumber = CurrentFlight.flightNumber or CurrentCallsign,
                        phase = FlightPhase
                    })
                end
            end
        else
            FlightPhase = 'ground'
            currentThrottleRate = ThrottleTiers.ground
        end
    end
end)

-- =====================================
-- RUNWAY SELECTION MENU
-- =====================================

function OpenRunwayMenu()
    local options = {}

    for _, runway in ipairs(Locations.Hub.runways) do
        table.insert(options, {
            title = runway.label,
            description = 'Request clearance for this runway',
            icon = 'fas fa-road',
            onSelect = function()
                local success = RequestClearance(runway)
                if success then
                    SetNewWaypoint(runway.location.x, runway.location.y)
                    lib.notify({
                        title = 'Waypoint Set',
                        description = 'Navigate to ' .. runway.label,
                        type = 'inform'
                    })
                end
            end
        })
    end

    lib.registerContext({
        id = 'airlines_runway_menu',
        title = 'Select Runway',
        options = options
    })

    lib.showContext('airlines_runway_menu')
end

-- =====================================
-- EXPORTS
-- =====================================

exports('RequestClearance', RequestClearance)
exports('LandingClearance', LandingClearance)
exports('ResetClearance', ResetClearance)
exports('CheckWeatherConditions', CheckWeatherConditions)
exports('ApplyWeatherDelay', ApplyWeatherDelay)
exports('GetFlightPhase', GetFlightPhase)
exports('HasClearance', function() return HasClearance end)
exports('GetCallsign', function() return CurrentCallsign end)
