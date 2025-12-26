local QBCore = exports['qb-core']:GetCoreObject()

-- Active flights tracking
local ActiveFlights = {}
local ActiveCharters = {}

-- =====================================
-- STATE BAG WEATHER SYSTEM
-- Eliminates client polling - weather synced via GlobalState
-- =====================================

local CurrentWeatherState = {
    weather = 'CLEAR',
    canFly = true,
    delayMinutes = 0,
    payBonus = 1.0,
    lastUpdate = os.time()
}

-- Initialize global weather state
CreateThread(function()
    Wait(1000)
    GlobalState.airlineWeather = CurrentWeatherState
    GlobalState.atcStatus = 'operational' -- operational, busy, closed
    print('^2[dps-airlines]^7 GlobalState weather/ATC initialized')
end)

-- Periodic weather check and state bag update (server-side only)
CreateThread(function()
    while true do
        Wait(Config.Weather.checkInterval or 60000)

        if Config.Weather.enabled then
            local weather = GetCurrentServerWeather()
            local conditions = EvaluateWeatherConditions(weather)

            CurrentWeatherState = {
                weather = weather,
                canFly = conditions.canFly,
                delayMinutes = conditions.delay,
                payBonus = conditions.bonus,
                reason = conditions.reason,
                lastUpdate = os.time()
            }

            -- Update GlobalState - clients auto-sync
            GlobalState.airlineWeather = CurrentWeatherState

            -- Notify pilots of weather changes
            if not conditions.canFly then
                local players = QBCore.Functions.GetQBPlayers()
                for _, player in pairs(players) do
                    if player.PlayerData.job.name == Config.Job and player.PlayerData.job.onduty then
                        Notify(player.PlayerData.source, 'Weather Alert: ' .. conditions.reason, 'error')
                    end
                end
            end
        end
    end
end)

local function GetCurrentServerWeather()
    -- Try to get from qb-weathersync
    local success, weather = pcall(function()
        return exports['qb-weathersync']:getWeatherState()
    end)

    if success and weather then
        return weather
    end

    return 'CLEAR'
end

local function EvaluateWeatherConditions(weather)
    -- Check if grounded
    for _, grounded in ipairs(Config.Weather.groundedWeather or {}) do
        if weather == grounded then
            return {
                canFly = false,
                delay = 0,
                bonus = 1.0,
                reason = 'All flights grounded due to severe weather'
            }
        end
    end

    -- Check for delays
    local delayInfo = Config.Weather.delays and Config.Weather.delays[weather]
    if delayInfo then
        local roll = math.random(1, 100)
        if roll <= delayInfo.chance then
            return {
                canFly = true,
                delay = delayInfo.delayMinutes,
                bonus = delayInfo.payBonus,
                reason = string.format('%s conditions - %d min delay', weather, delayInfo.delayMinutes)
            }
        end
    end

    return { canFly = true, delay = 0, bonus = 1.0 }
end

-- Export for other resources
exports('GetWeatherState', function()
    return CurrentWeatherState
end)

-- =====================================
-- UTILITY FUNCTIONS
-- =====================================

local function GetPlayer(source)
    return QBCore.Functions.GetPlayer(source)
end

local function Notify(source, msg, type)
    TriggerClientEvent('ox_lib:notify', source, {
        title = 'Airlines',
        description = msg,
        type = type or 'inform'
    })
end

local function GenerateFlightNumber()
    local prefix = Config.ATC.callsigns.prefix
    local num = math.random(100, 999)
    return string.format(Config.ATC.callsigns.format, prefix, num)
end

local function GetPilotStats(citizenid)
    local result = MySQL.single.await('SELECT * FROM airline_pilot_stats WHERE citizenid = ?', { citizenid })
    if not result then
        MySQL.insert.await('INSERT INTO airline_pilot_stats (citizenid) VALUES (?)', { citizenid })
        return {
            citizenid = citizenid,
            total_flights = 0,
            total_passengers = 0,
            total_cargo = 0,
            total_earnings = 0,
            flight_hours = 0,
            reputation = 0,
            license_obtained = nil,
            lessons_completed = '[]'
        }
    end
    return result
end

local function UpdatePilotStats(citizenid, data)
    MySQL.update.await([[
        UPDATE airline_pilot_stats SET
            total_flights = total_flights + ?,
            total_passengers = total_passengers + ?,
            total_cargo = total_cargo + ?,
            total_earnings = total_earnings + ?,
            flight_hours = flight_hours + ?,
            reputation = reputation + ?
        WHERE citizenid = ?
    ]], {
        data.flights or 0,
        data.passengers or 0,
        data.cargo or 0,
        data.earnings or 0,
        data.hours or 0,
        data.rep or 0,
        citizenid
    })
end

local function HasPilotLicense(citizenid)
    local stats = GetPilotStats(citizenid)
    return stats.license_obtained ~= nil
end

local function GetPlaneMaintenanceStatus(model)
    local result = MySQL.single.await('SELECT * FROM airline_maintenance WHERE plane_model = ? AND owned_by = ?', { model, 'company' })
    return result
end

local function UpdatePlaneFlights(model)
    MySQL.update.await('UPDATE airline_maintenance SET flights_since_service = flights_since_service + 1 WHERE plane_model = ? AND owned_by = ?', { model, 'company' })
end

local function ServicePlane(model)
    MySQL.update.await([[
        UPDATE airline_maintenance SET
            flights_since_service = 0,
            last_service = NOW(),
            service_history = JSON_ARRAY_APPEND(COALESCE(service_history, '[]'), '$', JSON_OBJECT('date', NOW(), 'type', 'full_service'))
        WHERE plane_model = ? AND owned_by = ?
    ]], { model, 'company' })
end

-- =====================================
-- CALLBACKS
-- =====================================

lib.callback.register('dps-airlines:server:getPlayerData', function(source)
    local Player = GetPlayer(source)
    if not Player then return nil end

    local citizenid = Player.PlayerData.citizenid
    local stats = GetPilotStats(citizenid)
    local job = Player.PlayerData.job

    -- Get available planes based on reputation
    local availablePlanes = {}
    for model, data in pairs(Config.Planes) do
        if stats.reputation >= data.repRequired then
            availablePlanes[model] = data
        end
    end

    return {
        citizenid = citizenid,
        job = job,
        stats = stats,
        availablePlanes = availablePlanes,
        hasLicense = stats.license_obtained ~= nil,
        onDuty = job.onduty
    }
end)

lib.callback.register('dps-airlines:server:getPilotStats', function(source)
    local Player = GetPlayer(source)
    if not Player then return nil end
    return GetPilotStats(Player.PlayerData.citizenid)
end)

lib.callback.register('dps-airlines:server:getMaintenanceStatus', function(source, model)
    return GetPlaneMaintenanceStatus(model)
end)

lib.callback.register('dps-airlines:server:canUsePlane', function(source, model)
    local Player = GetPlayer(source)
    if not Player then return false, 'Player not found' end

    local stats = GetPilotStats(Player.PlayerData.citizenid)
    local planeData = Config.Planes[model]

    if not planeData then
        return false, 'Invalid plane model'
    end

    if stats.reputation < planeData.repRequired then
        return false, string.format('Need %d reputation (you have %d)', planeData.repRequired, stats.reputation)
    end

    -- Check maintenance
    if Config.Maintenance.enabled then
        local maintenance = GetPlaneMaintenanceStatus(model)
        if maintenance and maintenance.flights_since_service >= Config.Maintenance.flightsBeforeService then
            return false, 'This aircraft requires maintenance'
        end
    end

    return true, nil
end)

lib.callback.register('dps-airlines:server:getAvailableFlights', function(source)
    local Player = GetPlayer(source)
    if not Player then return {} end

    local citizenid = Player.PlayerData.citizenid
    local stats = GetPilotStats(citizenid)

    local flights = MySQL.query.await([[
        SELECT * FROM airline_dispatch
        WHERE status = 'available'
        AND (expires_at IS NULL OR expires_at > NOW())
        ORDER BY
            CASE priority
                WHEN 'urgent' THEN 1
                WHEN 'high' THEN 2
                WHEN 'normal' THEN 3
                ELSE 4
            END,
            created_at ASC
        LIMIT 10
    ]])

    -- Filter flights based on plane access
    local available = {}
    for _, flight in ipairs(flights or {}) do
        if flight.plane_required then
            local planeData = Config.Planes[flight.plane_required]
            if planeData and stats.reputation >= planeData.repRequired then
                table.insert(available, flight)
            end
        else
            table.insert(available, flight)
        end
    end

    return available
end)

-- =====================================
-- EVENTS
-- =====================================

RegisterNetEvent('dps-airlines:server:toggleDuty', function()
    local source = source
    local Player = GetPlayer(source)
    if not Player then return end

    if Player.PlayerData.job.name ~= Config.Job then
        Notify(source, 'You are not a pilot', 'error')
        return
    end

    local onDuty = not Player.PlayerData.job.onduty
    Player.Functions.SetJobDuty(onDuty)

    Notify(source, onDuty and 'You are now on duty' or 'You are now off duty', 'success')
    TriggerClientEvent('dps-airlines:client:dutyChanged', source, onDuty)
end)

RegisterNetEvent('dps-airlines:server:startFlight', function(data)
    local source = source
    local Player = GetPlayer(source)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local flightNumber = GenerateFlightNumber()

    -- Create flight record
    local flightId = MySQL.insert.await([[
        INSERT INTO airline_flights
        (flight_number, pilot_citizenid, from_airport, to_airport, flight_type, plane_model, passengers, cargo_weight, status, started_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'departed', NOW())
    ]], {
        flightNumber,
        citizenid,
        data.from,
        data.to,
        data.flightType,
        data.plane,
        data.passengers or 0,
        data.cargo or 0
    })

    ActiveFlights[source] = {
        id = flightId,
        flightNumber = flightNumber,
        from = data.from,
        to = data.to,
        plane = data.plane,
        flightType = data.flightType,
        passengers = data.passengers or 0,
        cargo = data.cargo or 0,
        startTime = os.time()
    }

    -- Update plane maintenance counter
    if Config.Maintenance.enabled then
        UpdatePlaneFlights(data.plane)
    end

    TriggerClientEvent('dps-airlines:client:flightStarted', source, {
        flightNumber = flightNumber,
        destination = Locations.Airports[data.to]
    })

    Notify(source, string.format('Flight %s departed to %s', flightNumber, Locations.Airports[data.to].label), 'success')
end)

RegisterNetEvent('dps-airlines:server:completeFlight', function()
    local source = source
    local Player = GetPlayer(source)
    if not Player then return end

    local flight = ActiveFlights[source]
    if not flight then
        Notify(source, 'No active flight found', 'error')
        return
    end

    local citizenid = Player.PlayerData.citizenid
    local planeData = Config.Planes[flight.plane]
    local destAirport = Locations.Airports[flight.to]

    -- Calculate payment
    local basePay = planeData.basePayment
    local passengerPay = flight.passengers * Config.Passengers.payPerPassenger
    local cargoPay = flight.cargo * Config.Cargo.payPerKg
    local distanceBonus = destAirport.distance * 10

    local totalPay = math.floor(basePay + passengerPay + cargoPay + distanceBonus)

    -- Apply weather bonus if applicable
    -- (Weather bonus applied client-side and passed through)

    -- Calculate flight time
    local flightTime = (os.time() - flight.startTime) / 3600 -- Convert to hours

    -- Update database
    MySQL.update.await([[
        UPDATE airline_flights SET
            status = 'arrived',
            payment = ?,
            completed_at = NOW()
        WHERE id = ?
    ]], { totalPay, flight.id })

    -- Update pilot stats
    UpdatePilotStats(citizenid, {
        flights = 1,
        passengers = flight.passengers,
        cargo = flight.cargo,
        earnings = totalPay,
        hours = flightTime,
        rep = Config.RepGainPerFlight
    })

    -- Pay the player
    if Config.UseSocietyFunds then
        local success = exports['qb-management']:RemoveMoney('pilot', totalPay)
        if success then
            Player.Functions.AddMoney(Config.PaymentAccount, totalPay, 'airline-flight-payment')
        else
            -- Fallback to direct payment if society doesn't have funds
            Player.Functions.AddMoney(Config.PaymentAccount, totalPay, 'airline-flight-payment')
        end
    else
        Player.Functions.AddMoney(Config.PaymentAccount, totalPay, 'airline-flight-payment')
    end

    -- Clear active flight
    ActiveFlights[source] = nil

    TriggerClientEvent('dps-airlines:client:flightCompleted', source, {
        flightNumber = flight.flightNumber,
        payment = totalPay,
        passengers = flight.passengers,
        cargo = flight.cargo
    })

    Notify(source, string.format('Flight completed! Earned $%d', totalPay), 'success')
end)

RegisterNetEvent('dps-airlines:server:cancelFlight', function()
    local source = source
    local flight = ActiveFlights[source]

    if flight then
        MySQL.update.await('UPDATE airline_flights SET status = ? WHERE id = ?', { 'cancelled', flight.id })
        ActiveFlights[source] = nil
        Notify(source, 'Flight cancelled', 'warning')
    end
end)

RegisterNetEvent('dps-airlines:server:servicePlane', function(model)
    local source = source
    local Player = GetPlayer(source)
    if not Player then return end

    local planeData = Config.Planes[model]
    if not planeData then return end

    local cost = Config.Maintenance.serviceCost[planeData.category]

    -- Check if player has money (for boss) or use society
    local canPay = false
    if Player.PlayerData.job.grade.level >= Config.BossGrade then
        canPay = exports['qb-management']:RemoveMoney('pilot', cost)
    end

    if canPay then
        ServicePlane(model)
        Notify(source, string.format('%s has been serviced for $%d', planeData.label, cost), 'success')
        TriggerClientEvent('dps-airlines:client:planeServiced', source, model)
    else
        Notify(source, 'Insufficient society funds', 'error')
    end
end)

-- =====================================
-- FLIGHT SCHOOL
-- =====================================

RegisterNetEvent('dps-airlines:server:startLesson', function(lessonId)
    local source = source
    local Player = GetPlayer(source)
    if not Player then return end

    local lesson = nil
    for _, l in ipairs(Config.FlightSchool.lessons) do
        if l.name == lessonId then
            lesson = l
            break
        end
    end

    if not lesson then
        Notify(source, 'Invalid lesson', 'error')
        return
    end

    TriggerClientEvent('dps-airlines:client:startLesson', source, lesson)
end)

RegisterNetEvent('dps-airlines:server:completeLesson', function(lessonId)
    local source = source
    local Player = GetPlayer(source)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local stats = GetPilotStats(citizenid)

    local lessons = json.decode(stats.lessons_completed) or {}

    -- Check if already completed
    for _, completed in ipairs(lessons) do
        if completed == lessonId then
            Notify(source, 'Lesson already completed', 'error')
            return
        end
    end

    -- Find lesson reward
    local reward = 0
    for _, lesson in ipairs(Config.FlightSchool.lessons) do
        if lesson.name == lessonId then
            reward = lesson.reward
            break
        end
    end

    table.insert(lessons, lessonId)

    MySQL.update.await('UPDATE airline_pilot_stats SET lessons_completed = ? WHERE citizenid = ?', {
        json.encode(lessons),
        citizenid
    })

    Player.Functions.AddMoney('cash', reward, 'flight-lesson-reward')
    Notify(source, string.format('Lesson completed! Earned $%d', reward), 'success')

    -- Check if all lessons completed
    if #lessons >= Config.FlightSchool.requiredLessons then
        TriggerClientEvent('dps-airlines:client:canGetLicense', source)
    end
end)

RegisterNetEvent('dps-airlines:server:purchaseLicense', function()
    local source = source
    local Player = GetPlayer(source)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local stats = GetPilotStats(citizenid)

    if stats.license_obtained then
        Notify(source, 'You already have a pilot license', 'error')
        return
    end

    local lessons = json.decode(stats.lessons_completed) or {}
    if #lessons < Config.FlightSchool.requiredLessons then
        Notify(source, 'Complete all lessons first', 'error')
        return
    end

    local cost = Config.FlightSchool.licenseCost
    if Player.Functions.RemoveMoney('cash', cost, 'pilot-license-purchase') or
       Player.Functions.RemoveMoney('bank', cost, 'pilot-license-purchase') then

        MySQL.update.await('UPDATE airline_pilot_stats SET license_obtained = NOW() WHERE citizenid = ?', { citizenid })

        -- Give license item
        exports['ox_inventory']:AddItem(source, 'pilots_license', 1)

        Notify(source, 'Congratulations! You are now a licensed pilot!', 'success')
    else
        Notify(source, string.format('You need $%d for the license', cost), 'error')
    end
end)

-- =====================================
-- PLAYER DISCONNECT HANDLING
-- =====================================

AddEventHandler('playerDropped', function()
    local source = source
    if ActiveFlights[source] then
        MySQL.update.await('UPDATE airline_flights SET status = ? WHERE id = ?', { 'cancelled', ActiveFlights[source].id })
        ActiveFlights[source] = nil
    end
    if ActiveCharters[source] then
        ActiveCharters[source] = nil
    end
end)

-- =====================================
-- ADMIN COMMANDS
-- =====================================

QBCore.Commands.Add('setpilotgrade', 'Set pilot job grade (Admin)', {
    { name = 'id', help = 'Player ID' },
    { name = 'grade', help = 'Grade (0-2)' }
}, true, function(source, args)
    local targetId = tonumber(args[1])
    local grade = tonumber(args[2])

    if not targetId or not grade then return end

    local Player = QBCore.Functions.GetPlayer(targetId)
    if Player then
        Player.Functions.SetJob('pilot', grade)
        Notify(source, 'Pilot grade updated', 'success')
        Notify(targetId, 'Your pilot grade has been updated', 'success')
    end
end, 'admin')

QBCore.Commands.Add('resetpilotstats', 'Reset pilot stats (Admin)', {
    { name = 'id', help = 'Player ID' }
}, true, function(source, args)
    local targetId = tonumber(args[1])
    if not targetId then return end

    local Player = QBCore.Functions.GetPlayer(targetId)
    if Player then
        MySQL.update.await('DELETE FROM airline_pilot_stats WHERE citizenid = ?', { Player.PlayerData.citizenid })
        Notify(source, 'Pilot stats reset', 'success')
    end
end, 'admin')

-- =====================================
-- CHECKRIDE SYSTEM (Server)
-- Recurrent training for inactive pilots
-- =====================================

local CheckrideConfig = {
    inactivityDays = 14,
    warningDays = 10
}

lib.callback.register('dps-airlines:server:getCheckrideStatus', function(source)
    local Player = GetPlayer(source)
    if not Player then return nil end

    local citizenid = Player.PlayerData.citizenid
    local stats = GetPilotStats(citizenid)

    if not stats.last_flight then
        -- New pilot, no checkride needed
        return { required = false, warning = false }
    end

    -- Calculate days since last flight
    local lastFlight = MySQL.single.await([[
        SELECT DATEDIFF(NOW(), completed_at) as days_inactive
        FROM airline_flights
        WHERE pilot_citizenid = ? AND status = 'arrived'
        ORDER BY completed_at DESC
        LIMIT 1
    ]], { citizenid })

    if not lastFlight then
        return { required = false, warning = false }
    end

    local daysInactive = lastFlight.days_inactive or 0

    if daysInactive >= CheckrideConfig.inactivityDays then
        -- Check if they already have a pending/recent passed checkride
        local recentCheckride = MySQL.single.await([[
            SELECT * FROM airline_checkrides
            WHERE pilot_citizenid = ? AND status = 'passed'
            AND completed_at > DATE_SUB(NOW(), INTERVAL 1 DAY)
        ]], { citizenid })

        if recentCheckride then
            return { required = false, warning = false }
        end

        return {
            required = true,
            daysInactive = daysInactive
        }
    elseif daysInactive >= CheckrideConfig.warningDays then
        return {
            required = false,
            warning = true,
            daysRemaining = CheckrideConfig.inactivityDays - daysInactive
        }
    end

    return { required = false, warning = false }
end)

RegisterNetEvent('dps-airlines:server:completeCheckride', function(data)
    local source = source
    local Player = GetPlayer(source)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid

    -- Record checkride result
    MySQL.insert.await([[
        INSERT INTO airline_checkrides
        (pilot_citizenid, checkride_type, status, score, notes, completed_at)
        VALUES (?, 'recurrent', ?, ?, ?, NOW())
    ]], {
        citizenid,
        data.passed and 'passed' or 'failed',
        data.score,
        data.reason or json.encode(data.penalties or {})
    })

    if data.passed then
        -- Update last flight to reset the timer
        MySQL.update.await([[
            UPDATE airline_pilot_stats
            SET checkride_due = NULL, last_flight = NOW()
            WHERE citizenid = ?
        ]], { citizenid })

        Notify(source, 'Checkride passed! You may now accept flights.', 'success')
    else
        Notify(source, 'Checkride failed. Please try again.', 'error')
    end
end)

-- Update last_flight when a flight is completed
local originalCompleteFlight = nil
AddEventHandler('dps-airlines:server:completeFlight', function()
    local source = source
    local Player = GetPlayer(source)
    if Player then
        MySQL.update.await('UPDATE airline_pilot_stats SET last_flight = NOW() WHERE citizenid = ?', {
            Player.PlayerData.citizenid
        })
    end
end)

-- =====================================
-- BLACK BOX FLIGHT RECORDER (Server)
-- =====================================

local BlackBoxRecords = {}

RegisterNetEvent('dps-airlines:server:saveBlackBox', function(data)
    local source = source
    local Player = GetPlayer(source)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid

    -- Store in memory (recent flights only)
    BlackBoxRecords[data.flightNumber] = {
        pilot = citizenid,
        data = data,
        savedAt = os.time()
    }

    -- Save summary to database
    MySQL.insert.await([[
        INSERT INTO airline_blackbox
        (flight_number, pilot_citizenid, start_time, end_time, telemetry_count, events_count, data_summary)
        VALUES (?, ?, FROM_UNIXTIME(?), FROM_UNIXTIME(?), ?, ?, ?)
    ]], {
        data.flightNumber,
        citizenid,
        math.floor(data.startTime / 1000),
        math.floor(data.endTime / 1000),
        #data.telemetry,
        #data.events,
        json.encode({
            finalPosition = data.telemetry[#data.telemetry],
            eventTypes = GetEventTypes(data.events)
        })
    })

    if Config.Debug then
        print(string.format('[dps-airlines] BlackBox saved for flight %s (%d points, %d events)',
            data.flightNumber, #data.telemetry, #data.events))
    end
end)

local function GetEventTypes(events)
    local types = {}
    for _, event in ipairs(events) do
        types[event.type] = (types[event.type] or 0) + 1
    end
    return types
end

RegisterNetEvent('dps-airlines:server:flightCrashed', function(data)
    local source = source
    local Player = GetPlayer(source)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid
    local flight = ActiveFlights[source]

    -- Log crash
    MySQL.insert.await([[
        INSERT INTO airline_crashes
        (flight_number, pilot_citizenid, crash_coords, crash_phase, flight_id, crash_time)
        VALUES (?, ?, ?, ?, ?, NOW())
    ]], {
        data.flightNumber,
        citizenid,
        json.encode(data.coords),
        data.phase,
        flight and flight.id or nil
    })

    -- Update flight status
    if flight then
        MySQL.update.await('UPDATE airline_flights SET status = ?, completed_at = NOW() WHERE id = ?', {
            'crashed',
            flight.id
        })
    end

    -- Update pilot stats (no rep penalty, just track crashes)
    MySQL.update.await([[
        UPDATE airline_pilot_stats
        SET crashes = COALESCE(crashes, 0) + 1
        WHERE citizenid = ?
    ]], { citizenid })

    Notify(source, 'Flight incident has been recorded', 'warning')

    -- Clear active flight
    ActiveFlights[source] = nil
end)

RegisterNetEvent('dps-airlines:server:requestRecoveryAircraft', function(data)
    local source = source
    local Player = GetPlayer(source)
    if not Player then return end

    -- Check if eligible for recovery (insurance check could go here)
    local canRecover = true

    if canRecover then
        -- Notify client to spawn replacement
        TriggerClientEvent('dps-airlines:client:recoveryApproved', source, {
            destination = data.destination,
            passengers = data.passengers,
            cargo = data.cargo
        })

        Notify(source, 'Recovery aircraft approved. Head to the hangar.', 'success')
    else
        Notify(source, 'Recovery not available at this time', 'error')
    end
end)

lib.callback.register('dps-airlines:server:getBlackBoxData', function(source, flightNumber)
    if BlackBoxRecords[flightNumber] then
        return BlackBoxRecords[flightNumber].data
    end

    -- Try to get from database
    local record = MySQL.single.await([[
        SELECT * FROM airline_blackbox WHERE flight_number = ?
    ]], { flightNumber })

    return record
end)

lib.callback.register('dps-airlines:server:getCrashHistory', function(source)
    local Player = GetPlayer(source)
    if not Player then return {} end

    -- Bosses can see all, pilots see their own
    local citizenid = Player.PlayerData.citizenid
    local isBoss = Player.PlayerData.job.grade.level >= Config.BossGrade

    local crashes
    if isBoss then
        crashes = MySQL.query.await([[
            SELECT c.*, f.from_airport, f.to_airport, f.plane_model
            FROM airline_crashes c
            LEFT JOIN airline_flights f ON c.flight_id = f.id
            ORDER BY c.crash_time DESC
            LIMIT 20
        ]])
    else
        crashes = MySQL.query.await([[
            SELECT c.*, f.from_airport, f.to_airport, f.plane_model
            FROM airline_crashes c
            LEFT JOIN airline_flights f ON c.flight_id = f.id
            WHERE c.pilot_citizenid = ?
            ORDER BY c.crash_time DESC
            LIMIT 10
        ]], { citizenid })
    end

    return crashes or {}
end)

-- Cleanup old blackbox records from memory periodically
CreateThread(function()
    while true do
        Wait(300000) -- Every 5 minutes

        local now = os.time()
        local cleaned = 0

        for flightNumber, record in pairs(BlackBoxRecords) do
            -- Remove records older than 1 hour
            if now - record.savedAt > 3600 then
                BlackBoxRecords[flightNumber] = nil
                cleaned = cleaned + 1
            end
        end

        if cleaned > 0 and Config.Debug then
            print('[dps-airlines] Cleaned ' .. cleaned .. ' old blackbox records from memory')
        end
    end
end)

print('^2[dps-airlines]^7 Server loaded')
