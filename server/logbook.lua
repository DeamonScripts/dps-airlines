-- Pilot Logbook & Flight Logging System
-- Realistic flight time tracking like real aviation
local QBCore = exports['qb-core']:GetCoreObject()

-- =====================================
-- FLIGHT TIME CALCULATION
-- =====================================

local function IsNightTime()
    local hour = GetClockHours()
    return hour >= 21 or hour < 6
end

local function GetWeatherCondition()
    local success, weather = pcall(function()
        return exports['qb-weathersync']:getWeatherState()
    end)
    return success and weather or 'CLEAR'
end

local function IsIFRWeather(weather)
    local ifrConditions = { 'FOGGY', 'RAIN', 'THUNDER', 'SNOW', 'BLIZZARD' }
    for _, condition in ipairs(ifrConditions) do
        if weather == condition then return true end
    end
    return false
end

local function GetLandingQuality(speed, verticalSpeed)
    -- Based on touchdown speed
    if speed < 5 then
        return 'smooth'
    elseif speed < 15 then
        return 'normal'
    else
        return 'hard'
    end
end

-- =====================================
-- LOGBOOK ENTRY CREATION
-- =====================================

function CreateLogbookEntry(citizenid, flightData)
    -- Calculate flight time in hours
    local flightTimeHours = (flightData.arrivalTime - flightData.departureTime) / 3600

    -- Determine day/night
    local departHour = tonumber(os.date('%H', flightData.departureTime))
    local arriveHour = tonumber(os.date('%H', flightData.arrivalTime))
    local dayNight = 'day'
    if (departHour >= 21 or departHour < 6) and (arriveHour >= 21 or arriveHour < 6) then
        dayNight = 'night'
    elseif (departHour >= 21 or departHour < 6) or (arriveHour >= 21 or arriveHour < 6) then
        dayNight = 'mixed'
    end

    -- Determine IFR/VFR based on weather
    local weather = flightData.weather or 'CLEAR'
    local ifrVfr = IsIFRWeather(weather) and 'ifr' or 'vfr'

    -- Get aircraft category
    local planeData = Config.Planes[flightData.aircraft]
    local category = planeData and planeData.category or 'small'

    -- Calculate distance
    local fromAirport = Locations.Airports[flightData.from]
    local toAirport = Locations.Airports[flightData.to]
    local distance = toAirport and toAirport.distance or 0

    -- Net earnings
    local netEarnings = (flightData.payment or 0) - (flightData.fuelCost or 0)

    -- Insert logbook entry
    local logId = MySQL.insert.await([[
        INSERT INTO airline_pilot_logbook (
            citizenid, flight_id, flight_number,
            departure_airport, arrival_airport, route_distance,
            aircraft_model, aircraft_category,
            departure_time, arrival_time, flight_time, block_time,
            day_night, weather_conditions, ifr_vfr,
            flight_type, passengers, cargo_kg,
            landings, landing_quality, fuel_used,
            payment, fuel_cost, net_earnings,
            remarks, status
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?), FROM_UNIXTIME(?), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        citizenid,
        flightData.flightId,
        flightData.flightNumber,
        flightData.from,
        flightData.to,
        distance,
        flightData.aircraft,
        category,
        flightData.departureTime,
        flightData.arrivalTime,
        flightTimeHours,
        flightTimeHours + 0.1, -- Block time slightly higher
        dayNight,
        weather,
        ifrVfr,
        flightData.flightType,
        flightData.passengers or 0,
        flightData.cargo or 0,
        flightData.landings or 1,
        flightData.landingQuality or 'normal',
        flightData.fuelUsed or 0,
        flightData.payment or 0,
        flightData.fuelCost or 0,
        netEarnings,
        flightData.remarks,
        flightData.status or 'completed'
    })

    -- Update pilot stats
    UpdatePilotLogbookStats(citizenid, {
        flightTime = flightTimeHours,
        dayNight = dayNight,
        ifrVfr = ifrVfr,
        flightType = flightData.flightType,
        aircraft = flightData.aircraft,
        distance = distance,
        landings = flightData.landings or 1,
        landingQuality = flightData.landingQuality or 'normal',
        passengers = flightData.passengers or 0,
        cargo = flightData.cargo or 0,
        payment = flightData.payment or 0
    })

    return logId
end

-- =====================================
-- PILOT STATS UPDATE
-- =====================================

function UpdatePilotLogbookStats(citizenid, data)
    local nightHours = 0
    local dayLandings = 0
    local nightLandings = 0

    if data.dayNight == 'night' then
        nightHours = data.flightTime
        nightLandings = data.landings
    elseif data.dayNight == 'mixed' then
        nightHours = data.flightTime * 0.3 -- Estimate 30% night
        nightLandings = math.floor(data.landings * 0.3)
        dayLandings = data.landings - nightLandings
    else
        dayLandings = data.landings
    end

    local ifrHours = data.ifrVfr == 'ifr' and data.flightTime or 0
    local crossCountryHours = data.distance > 8 and data.flightTime or 0 -- > 8km = cross country

    -- Determine job type hours column
    local typeHoursColumn = 'passenger_hours'
    if data.flightType == 'cargo' then
        typeHoursColumn = 'cargo_hours'
    elseif data.flightType == 'charter' then
        typeHoursColumn = 'charter_hours'
    elseif data.flightType == 'ferry' then
        typeHoursColumn = 'ferry_hours'
    end

    -- Hard landing tracking
    local hardLandings = data.landingQuality == 'hard' and 1 or 0

    -- Update main stats
    MySQL.update.await(string.format([[
        UPDATE airline_pilot_stats SET
            total_flights = total_flights + 1,
            total_passengers = total_passengers + ?,
            total_cargo = total_cargo + ?,
            total_earnings = total_earnings + ?,
            total_hours = total_hours + ?,
            pic_hours = pic_hours + ?,
            night_hours = night_hours + ?,
            ifr_hours = ifr_hours + ?,
            cross_country_hours = cross_country_hours + ?,
            day_landings = day_landings + ?,
            night_landings = night_landings + ?,
            %s = %s + ?,
            hard_landings = hard_landings + ?,
            reputation = reputation + 1,
            last_flight = NOW()
        WHERE citizenid = ?
    ]], typeHoursColumn, typeHoursColumn), {
        data.passengers,
        data.cargo,
        data.payment,
        data.flightTime,
        data.flightTime, -- All hours are PIC for solo flights
        nightHours,
        ifrHours,
        crossCountryHours,
        dayLandings,
        nightLandings,
        data.flightTime,
        hardLandings,
        citizenid
    })

    -- Update type ratings
    UpdateTypeRating(citizenid, data.aircraft)
end

function UpdateTypeRating(citizenid, aircraft)
    local stats = MySQL.single.await('SELECT type_ratings FROM airline_pilot_stats WHERE citizenid = ?', { citizenid })
    if not stats then return end

    local ratings = json.decode(stats.type_ratings or '[]')

    -- Check if already has rating
    for _, rating in ipairs(ratings) do
        if rating == aircraft then return end
    end

    -- Add new rating
    table.insert(ratings, aircraft)

    MySQL.update.await('UPDATE airline_pilot_stats SET type_ratings = ? WHERE citizenid = ?', {
        json.encode(ratings),
        citizenid
    })
end

-- =====================================
-- LOGBOOK QUERIES
-- =====================================

lib.callback.register('dps-airlines:server:getPilotLogbook', function(source, targetCitizenid, limit, offset)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return {} end

    local citizenid = targetCitizenid or Player.PlayerData.citizenid

    -- Only allow viewing own logbook or if boss
    if citizenid ~= Player.PlayerData.citizenid then
        if Player.PlayerData.job.name ~= Config.Job or Player.PlayerData.job.grade.level < Config.BossGrade then
            return {}
        end
    end

    local entries = MySQL.query.await([[
        SELECT * FROM airline_pilot_logbook
        WHERE citizenid = ?
        ORDER BY departure_time DESC
        LIMIT ? OFFSET ?
    ]], { citizenid, limit or 50, offset or 0 })

    return entries or {}
end)

lib.callback.register('dps-airlines:server:getPilotDetailedStats', function(source, targetCitizenid)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return nil end

    local citizenid = targetCitizenid or Player.PlayerData.citizenid

    -- Only allow viewing own stats or if boss
    if citizenid ~= Player.PlayerData.citizenid then
        if Player.PlayerData.job.name ~= Config.Job or Player.PlayerData.job.grade.level < Config.BossGrade then
            return nil
        end
    end

    local stats = MySQL.single.await('SELECT * FROM airline_pilot_stats WHERE citizenid = ?', { citizenid })

    if not stats then return nil end

    -- Get recent flight summary
    local recentStats = MySQL.single.await([[
        SELECT
            COUNT(*) as flights_30days,
            SUM(flight_time) as hours_30days,
            SUM(payment) as earnings_30days
        FROM airline_pilot_logbook
        WHERE citizenid = ?
        AND departure_time > DATE_SUB(NOW(), INTERVAL 30 DAY)
    ]], { citizenid })

    -- Get last 5 flights
    local recentFlights = MySQL.query.await([[
        SELECT departure_airport, arrival_airport, flight_type, flight_time, payment, departure_time
        FROM airline_pilot_logbook
        WHERE citizenid = ?
        ORDER BY departure_time DESC
        LIMIT 5
    ]], { citizenid })

    stats.recent = recentStats
    stats.recentFlights = recentFlights
    stats.type_ratings = json.decode(stats.type_ratings or '[]')

    return stats
end)

lib.callback.register('dps-airlines:server:getLogbookSummary', function(source, period)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return nil end

    local citizenid = Player.PlayerData.citizenid
    local interval = period == 'week' and 7 or (period == 'month' and 30 or 365)

    local summary = MySQL.single.await([[
        SELECT
            COUNT(*) as total_flights,
            COALESCE(SUM(flight_time), 0) as total_hours,
            COALESCE(SUM(passengers), 0) as total_passengers,
            COALESCE(SUM(cargo_kg), 0) as total_cargo,
            COALESCE(SUM(payment), 0) as total_earnings,
            COALESCE(SUM(CASE WHEN flight_type = 'passenger' THEN flight_time ELSE 0 END), 0) as passenger_hours,
            COALESCE(SUM(CASE WHEN flight_type = 'cargo' THEN flight_time ELSE 0 END), 0) as cargo_hours,
            COALESCE(SUM(CASE WHEN flight_type = 'charter' THEN flight_time ELSE 0 END), 0) as charter_hours,
            COALESCE(SUM(CASE WHEN flight_type = 'ferry' THEN flight_time ELSE 0 END), 0) as ferry_hours,
            COALESCE(SUM(day_landings), 0) as day_landings,
            COALESCE(SUM(night_landings), 0) as night_landings
        FROM airline_pilot_logbook
        WHERE citizenid = ?
        AND departure_time > DATE_SUB(NOW(), INTERVAL ? DAY)
    ]], { citizenid, interval })

    return summary
end)

-- =====================================
-- EXPORTS
-- =====================================

exports('CreateLogbookEntry', CreateLogbookEntry)
exports('UpdatePilotLogbookStats', UpdatePilotLogbookStats)

print('^2[dps-airlines]^7 Logbook module loaded')
