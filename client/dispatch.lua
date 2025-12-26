-- Dispatch System with Advanced Tablet UI
local QBCore = exports['qb-core']:GetCoreObject()

local ActiveDispatch = nil
local DispatchBlip = nil

-- =====================================
-- STATE BAG DISPATCH CACHE
-- Listens to GlobalState instead of polling database
-- =====================================

local CachedDispatchFlights = {}

-- Listen for dispatch state changes from server
AddStateBagChangeHandler('airlineDispatch', 'global', function(bagName, key, value)
    if not value then return end

    CachedDispatchFlights = value.flights or {}

    if Config.Debug then
        print('[dps-airlines] Dispatch State Bag updated: ' .. #CachedDispatchFlights .. ' flights available')
    end
end)

-- Get cached flights (no network call)
local function GetCachedFlights()
    -- Try GlobalState first
    local state = GlobalState.airlineDispatch
    if state and state.flights then
        return state.flights
    end
    return CachedDispatchFlights
end

-- =====================================
-- DISPATCH TABLET UI
-- Enhanced flight board with detailed information
-- =====================================

function OpenDispatchTablet()
    if not OnDuty then
        lib.notify({ title = 'Dispatch', description = 'You must be on duty', type = 'error' })
        return
    end

    -- Use cached flights from State Bag (no database poll!)
    local flights = GetCachedFlights()
    local stats = lib.callback.await('dps-airlines:server:getPilotStats', false)
    local weather = GetCachedWeather and GetCachedWeather() or { weather = 'CLEAR', canFly = true }

    -- Build tablet header with weather/status
    local headerDescription = string.format(
        '**Weather:** %s | **ATC:** %s | **Your Rep:** %d',
        weather.weather or 'CLEAR',
        weather.canFly and 'Operational' or 'Grounded',
        stats and stats.reputation or 0
    )

    local options = {
        {
            title = 'Flight Board Status',
            description = headerDescription,
            icon = weather.canFly and 'fas fa-tower-control' or 'fas fa-exclamation-triangle',
            disabled = true
        }
    }

    if not weather.canFly then
        table.insert(options, {
            title = 'FLIGHTS GROUNDED',
            description = weather.reason or 'Severe weather conditions',
            icon = 'fas fa-ban',
            disabled = true
        })
    elseif #flights == 0 then
        table.insert(options, {
            title = 'No Flights Available',
            description = 'Check back in a few minutes for new assignments',
            icon = 'fas fa-clock',
            disabled = true
        })
    else
        -- Sort flights by priority
        table.sort(flights, function(a, b)
            local priorityOrder = { urgent = 1, high = 2, normal = 3, low = 4 }
            return (priorityOrder[a.priority] or 4) < (priorityOrder[b.priority] or 4)
        end)

        for _, flight in ipairs(flights) do
            local fromAirport = Locations.Airports[flight.from_airport]
            local toAirport = Locations.Airports[flight.to_airport]

            if fromAirport and toAirport then
                local priorityIcon = 'fas fa-plane'
                local priorityColor = nil

                if flight.priority == 'urgent' then
                    priorityIcon = 'fas fa-exclamation-circle'
                elseif flight.priority == 'high' then
                    priorityIcon = 'fas fa-arrow-up'
                end

                local flightTypeLabel = flight.flight_type == 'cargo' and 'Cargo' or 'Passenger'
                local payloadInfo = flight.flight_type == 'cargo'
                    and string.format('%dkg %s', flight.cargo_weight or 0, flight.cargo_type or 'freight')
                    or string.format('%d passengers', flight.passengers or 0)

                -- Check if player can fly this plane
                local canFly = true
                local planeRequired = flight.plane_required
                if planeRequired and stats then
                    local planeData = Config.Planes[planeRequired]
                    if planeData and stats.reputation < planeData.repRequired then
                        canFly = false
                    end
                end

                table.insert(options, {
                    title = string.format('%s → %s', fromAirport.label, toAirport.label),
                    description = string.format('[%s] %s | %s | $%d',
                        flight.priority:upper(),
                        flightTypeLabel,
                        payloadInfo,
                        flight.payment
                    ),
                    icon = priorityIcon,
                    disabled = not canFly or ActiveDispatch ~= nil,
                    metadata = {
                        { label = 'Distance', value = string.format('%.1f km', toAirport.distance or 0) },
                        { label = 'Aircraft', value = planeRequired and Config.Planes[planeRequired].label or 'Any' },
                        { label = 'Priority', value = flight.priority:upper() },
                        { label = 'Payment', value = '$' .. flight.payment }
                    },
                    onSelect = function()
                        AcceptDispatchFromTablet(flight, fromAirport, toAirport)
                    end
                })
            end
        end
    end

    -- Add current assignment if active
    if ActiveDispatch then
        table.insert(options, 2, {
            title = '▶ ACTIVE: ' .. (ActiveDispatch.to_label or ActiveDispatch.to_airport),
            description = 'Click to view or cancel',
            icon = 'fas fa-plane-departure',
            onSelect = function()
                OpenActiveFlightMenu()
            end
        })
    end

    -- Footer options
    table.insert(options, {
        title = 'Refresh Board',
        description = 'Update flight listings',
        icon = 'fas fa-sync-alt',
        onSelect = function()
            -- Trigger server to refresh State Bag, then reopen
            TriggerServerEvent('dps-airlines:server:refreshDispatch')
            Wait(500) -- Allow state bag to sync
            OpenDispatchTablet()
        end
    })

    lib.registerContext({
        id = 'airlines_dispatch_tablet',
        title = '✈ DPS Airlines - Flight Dispatch',
        options = options
    })

    lib.showContext('airlines_dispatch_tablet')
end

function OpenActiveFlightMenu()
    if not ActiveDispatch then return end

    local fromAirport = Locations.Airports[ActiveDispatch.from_airport]
    local toAirport = Locations.Airports[ActiveDispatch.to_airport]

    local options = {
        {
            title = 'Current Assignment',
            description = string.format('%s → %s',
                fromAirport and fromAirport.label or ActiveDispatch.from_airport,
                toAirport and toAirport.label or ActiveDispatch.to_airport
            ),
            icon = 'fas fa-info-circle',
            disabled = true,
            metadata = {
                { label = 'Type', value = ActiveDispatch.flight_type or 'Unknown' },
                { label = 'Passengers', value = tostring(ActiveDispatch.passengers or 0) },
                { label = 'Cargo', value = string.format('%dkg', ActiveDispatch.cargo_weight or 0) },
                { label = 'Payment', value = '$' .. (ActiveDispatch.payment or 0) }
            }
        },
        {
            title = 'Set Waypoint to Destination',
            icon = 'fas fa-map-marker-alt',
            onSelect = function()
                if toAirport then
                    SetNewWaypoint(toAirport.coords.x, toAirport.coords.y)
                    lib.notify({ title = 'Navigation', description = 'Waypoint set', type = 'success' })
                end
            end
        },
        {
            title = 'Cancel Flight',
            description = 'Abort current assignment (may affect reputation)',
            icon = 'fas fa-times-circle',
            onSelect = function()
                CancelDispatch()
            end
        }
    }

    lib.registerContext({
        id = 'airlines_active_flight',
        title = 'Active Flight',
        menu = 'airlines_dispatch_tablet',
        options = options
    })

    lib.showContext('airlines_active_flight')
end

function AcceptDispatchFromTablet(flight, fromAirport, toAirport)
    if ActiveDispatch then
        lib.notify({ title = 'Dispatch', description = 'Complete current flight first', type = 'error' })
        return
    end

    if not CurrentPlane then
        lib.notify({ title = 'Dispatch', description = 'Spawn an aircraft first', type = 'error' })
        return
    end

    -- Confirm acceptance
    local confirm = lib.alertDialog({
        header = 'Accept Flight Assignment',
        content = string.format([[
**Route:** %s → %s
**Type:** %s
**Payload:** %s
**Payment:** $%d

Accept this assignment?
        ]],
            fromAirport.label,
            toAirport.label,
            flight.flight_type:gsub("^%l", string.upper),
            flight.flight_type == 'cargo'
                and string.format('%dkg %s', flight.cargo_weight or 0, flight.cargo_type or '')
                or string.format('%d passengers', flight.passengers or 0),
            flight.payment
        ),
        centered = true,
        cancel = true
    })

    if confirm == 'confirm' then
        AcceptDispatch(flight)
    end
end

-- =====================================
-- DISPATCH NOTIFICATION
-- =====================================

RegisterNetEvent('dps-airlines:client:newDispatch', function(dispatch)
    if not OnDuty then return end

    lib.notify({
        title = 'New Flight Available',
        description = string.format('%s → %s | $%d',
            dispatch.from_label,
            dispatch.to_label,
            dispatch.payment
        ),
        type = 'inform',
        duration = 10000
    })

    -- Play sound
    PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', false)
end)

-- =====================================
-- ACCEPT DISPATCH
-- =====================================

function AcceptDispatch(dispatch)
    if ActiveDispatch then
        lib.notify({ title = 'Dispatch', description = 'You already have an active assignment', type = 'error' })
        return
    end

    if not CurrentPlane then
        lib.notify({ title = 'Dispatch', description = 'You need an aircraft first', type = 'error' })
        return
    end

    local success = lib.callback.await('dps-airlines:server:acceptDispatch', false, dispatch.id)

    if success then
        ActiveDispatch = dispatch

        -- Set waypoint to origin if not already there
        local fromAirport = Locations.Airports[dispatch.from_airport]
        if fromAirport then
            local playerPos = GetEntityCoords(PlayerPedId())
            local dist = #(playerPos - vector3(fromAirport.coords.x, fromAirport.coords.y, fromAirport.coords.z))

            if dist > 500 then
                -- Need to go to origin first
                SetNewWaypoint(fromAirport.coords.x, fromAirport.coords.y)
                lib.notify({
                    title = 'Dispatch',
                    description = 'Head to ' .. fromAirport.label .. ' first',
                    type = 'inform'
                })
            else
                -- Already at origin, set destination
                local toAirport = Locations.Airports[dispatch.to_airport]
                SetNewWaypoint(toAirport.coords.x, toAirport.coords.y)
                lib.notify({
                    title = 'Dispatch',
                    description = 'Head to ' .. toAirport.label,
                    type = 'success'
                })
            end
        end

        -- Start flight
        TriggerServerEvent('dps-airlines:server:startFlight', {
            from = dispatch.from_airport,
            to = dispatch.to_airport,
            flightType = dispatch.flight_type,
            plane = GetCurrentPlaneName(),
            passengers = dispatch.passengers or 0,
            cargo = dispatch.cargo_weight or 0
        })
    else
        lib.notify({ title = 'Dispatch', description = 'Failed to accept dispatch', type = 'error' })
    end
end

function GetCurrentPlaneName()
    if not CurrentPlane then return nil end

    local model = GetEntityModel(CurrentPlane)
    for name, data in pairs(Config.Planes) do
        if GetHashKey(name) == model then
            return name
        end
    end
    return nil
end

-- =====================================
-- DISPATCH COMPLETION CHECK
-- Altitude-aware throttling for performance
-- =====================================

CreateThread(function()
    while true do
        -- Use dynamic throttle rate based on flight altitude
        local throttleRate = 2000 -- Default

        if ActiveDispatch and CurrentPlane and DoesEntityExist(CurrentPlane) then
            local planeCoords = GetEntityCoords(CurrentPlane)
            local heightAboveGround = GetEntityHeightAboveGround(CurrentPlane)

            -- Throttle check frequency based on altitude
            if heightAboveGround > 500 then
                throttleRate = 10000 -- Cruising: check every 10 seconds
            elseif heightAboveGround > 200 then
                throttleRate = 5000  -- Mid-altitude: every 5 seconds
            elseif heightAboveGround > 50 then
                throttleRate = 3000  -- Low altitude: every 3 seconds
            else
                throttleRate = 1000  -- Ground/approach: every 1 second
            end

            local toAirport = Locations.Airports[ActiveDispatch.to_airport]
            if toAirport then
                -- Use vector math (faster than GetDistanceBetweenCoords native)
                local destCoords = vector3(toAirport.coords.x, toAirport.coords.y, toAirport.coords.z)
                local dist = #(planeCoords - destCoords)
                local speed = GetEntitySpeed(CurrentPlane)

                -- Check if landed at destination
                if dist < 200 and heightAboveGround < 5 and speed < 10 then
                    CompleteDispatch()
                end
            end
        else
            throttleRate = 5000 -- No active flight, slow check
        end

        Wait(throttleRate)
    end
end)

function CompleteDispatch()
    if not ActiveDispatch then return end

    lib.notify({
        title = 'Flight Complete',
        description = 'Arrived at destination',
        type = 'success'
    })

    TriggerServerEvent('dps-airlines:server:completeFlight')

    -- Cleanup
    ActiveDispatch = nil
    if DispatchBlip then
        RemoveBlip(DispatchBlip)
        DispatchBlip = nil
    end
end

-- =====================================
-- CANCEL DISPATCH
-- =====================================

function CancelDispatch()
    if not ActiveDispatch then return end

    local confirm = lib.alertDialog({
        header = 'Cancel Assignment',
        content = 'Are you sure you want to cancel this flight? This may affect your reputation.',
        centered = true,
        cancel = true
    })

    if confirm == 'confirm' then
        TriggerServerEvent('dps-airlines:server:cancelFlight')

        ActiveDispatch = nil
        if DispatchBlip then
            RemoveBlip(DispatchBlip)
            DispatchBlip = nil
        end

        lib.notify({ title = 'Dispatch', description = 'Flight cancelled', type = 'warning' })
    end
end

-- =====================================
-- AUTO DISPATCH GENERATION (Server triggers this periodically)
-- =====================================

RegisterNetEvent('dps-airlines:client:dispatchGenerated', function(dispatch)
    if OnDuty then
        lib.notify({
            title = 'New Dispatch',
            description = string.format('%s flight to %s available',
                dispatch.flight_type:gsub("^%l", string.upper),
                dispatch.to_label
            ),
            type = 'inform',
            duration = 8000
        })
    end
end)

-- =====================================
-- EXPORTS
-- =====================================

exports('GetActiveDispatch', function() return ActiveDispatch end)
exports('AcceptDispatch', AcceptDispatch)
exports('CancelDispatch', CancelDispatch)
exports('OpenDispatchTablet', OpenDispatchTablet)
exports('OpenActiveFlightMenu', OpenActiveFlightMenu)
