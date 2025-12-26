-- Boss Management Server
-- Comprehensive pilot roster and flight log management
local QBCore = exports['qb-core']:GetCoreObject()

-- =====================================
-- BOSS MENU - MAIN DATA
-- =====================================

lib.callback.register('dps-airlines:server:getBossData', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return nil end

    if Player.PlayerData.job.name ~= Config.Job or Player.PlayerData.job.grade.level < Config.BossGrade then
        return nil
    end

    -- Get society balance (if using qb-management)
    local societyBalance = 0
    local success, balance = pcall(function()
        return exports['qb-management']:GetAccount('pilot')
    end)
    if success then
        societyBalance = balance or 0
    end

    -- Get employee list with detailed stats
    local employees = MySQL.query.await([[
        SELECT
            p.citizenid,
            p.charinfo,
            p.job,
            COALESCE(s.total_flights, 0) as flights,
            COALESCE(s.total_hours, 0) as total_hours,
            COALESCE(s.pic_hours, 0) as pic_hours,
            COALESCE(s.night_hours, 0) as night_hours,
            COALESCE(s.passenger_hours, 0) as passenger_hours,
            COALESCE(s.cargo_hours, 0) as cargo_hours,
            COALESCE(s.charter_hours, 0) as charter_hours,
            COALESCE(s.ferry_hours, 0) as ferry_hours,
            COALESCE(s.day_landings, 0) + COALESCE(s.night_landings, 0) as total_landings,
            COALESCE(s.crashes, 0) as crashes,
            COALESCE(s.hard_landings, 0) as hard_landings,
            COALESCE(s.reputation, 0) as reputation,
            COALESCE(s.total_earnings, 0) as total_earnings,
            s.license_type,
            s.last_flight,
            s.type_ratings
        FROM players p
        LEFT JOIN airline_pilot_stats s ON p.citizenid = s.citizenid
        WHERE JSON_EXTRACT(p.job, '$.name') = 'pilot'
        ORDER BY COALESCE(s.total_hours, 0) DESC
    ]])

    -- Parse employee data
    local parsedEmployees = {}
    for _, emp in ipairs(employees or {}) do
        local charinfo = json.decode(emp.charinfo)
        local job = json.decode(emp.job)

        -- Calculate days since last flight
        local daysSinceLastFlight = nil
        if emp.last_flight then
            local lastFlightResult = MySQL.single.await([[
                SELECT DATEDIFF(NOW(), ?) as days
            ]], { emp.last_flight })
            daysSinceLastFlight = lastFlightResult and lastFlightResult.days or nil
        end

        table.insert(parsedEmployees, {
            citizenid = emp.citizenid,
            name = string.format('%s %s', charinfo.firstname, charinfo.lastname),
            grade = job.grade.level,
            gradeName = job.grade.name,
            flights = emp.flights,
            totalHours = emp.total_hours,
            picHours = emp.pic_hours,
            nightHours = emp.night_hours,
            passengerHours = emp.passenger_hours,
            cargoHours = emp.cargo_hours,
            charterHours = emp.charter_hours,
            ferryHours = emp.ferry_hours,
            landings = emp.total_landings,
            crashes = emp.crashes,
            hardLandings = emp.hard_landings,
            reputation = emp.reputation,
            earnings = emp.total_earnings,
            licenseType = emp.license_type or 'student',
            lastFlight = emp.last_flight,
            daysSinceLastFlight = daysSinceLastFlight,
            typeRatings = json.decode(emp.type_ratings or '[]')
        })
    end

    -- Get company stats (weekly)
    local weeklyStats = MySQL.single.await([[
        SELECT
            COUNT(*) as total_flights,
            COALESCE(SUM(passengers), 0) as total_passengers,
            COALESCE(SUM(cargo_weight), 0) as total_cargo,
            COALESCE(SUM(payment), 0) as total_revenue
        FROM airline_flights
        WHERE status = 'arrived'
        AND completed_at > DATE_SUB(NOW(), INTERVAL 7 DAY)
    ]])

    -- Get company stats (monthly)
    local monthlyStats = MySQL.single.await([[
        SELECT
            COUNT(*) as total_flights,
            COALESCE(SUM(passengers), 0) as total_passengers,
            COALESCE(SUM(cargo_weight), 0) as total_cargo,
            COALESCE(SUM(payment), 0) as total_revenue
        FROM airline_flights
        WHERE status = 'arrived'
        AND completed_at > DATE_SUB(NOW(), INTERVAL 30 DAY)
    ]])

    -- Get pending charters
    local pendingCharters = MySQL.scalar.await([[
        SELECT COUNT(*) FROM airline_charter_requests WHERE status IN ('pending', 'quoted', 'confirmed')
    ]])

    -- Get available ferry jobs
    local availableFerry = MySQL.scalar.await([[
        SELECT COUNT(*) FROM airline_ferry_jobs WHERE status = 'available'
    ]])

    return {
        balance = societyBalance,
        employees = parsedEmployees,
        weeklyStats = weeklyStats or {},
        monthlyStats = monthlyStats or {},
        pendingCharters = pendingCharters or 0,
        availableFerry = availableFerry or 0
    }
end)

-- =====================================
-- PILOT ROSTER - DETAILED VIEW
-- =====================================

lib.callback.register('dps-airlines:server:getPilotDetails', function(source, citizenid)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return nil end

    if Player.PlayerData.job.name ~= Config.Job or Player.PlayerData.job.grade.level < Config.BossGrade then
        return nil
    end

    -- Get full pilot stats
    local stats = MySQL.single.await('SELECT * FROM airline_pilot_stats WHERE citizenid = ?', { citizenid })

    if not stats then return nil end

    -- Get pilot character info
    local playerData = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ?', { citizenid })
    local charinfo = playerData and json.decode(playerData.charinfo) or {}

    -- Get last 10 flights
    local recentFlights = MySQL.query.await([[
        SELECT * FROM airline_pilot_logbook
        WHERE citizenid = ?
        ORDER BY departure_time DESC
        LIMIT 10
    ]], { citizenid })

    -- Get flight stats by type (last 30 days)
    local flightsByType = MySQL.query.await([[
        SELECT
            flight_type,
            COUNT(*) as count,
            SUM(flight_time) as hours,
            SUM(payment) as earnings
        FROM airline_pilot_logbook
        WHERE citizenid = ?
        AND departure_time > DATE_SUB(NOW(), INTERVAL 30 DAY)
        GROUP BY flight_type
    ]], { citizenid })

    -- Get crash history
    local crashes = MySQL.query.await([[
        SELECT * FROM airline_crashes
        WHERE pilot_citizenid = ?
        ORDER BY crash_time DESC
        LIMIT 5
    ]], { citizenid })

    -- Get checkride history
    local checkrides = MySQL.query.await([[
        SELECT * FROM airline_checkrides
        WHERE pilot_citizenid = ?
        ORDER BY completed_at DESC
        LIMIT 5
    ]], { citizenid })

    return {
        name = string.format('%s %s', charinfo.firstname or '', charinfo.lastname or ''),
        citizenid = citizenid,
        stats = stats,
        typeRatings = json.decode(stats.type_ratings or '[]'),
        recentFlights = recentFlights or {},
        flightsByType = flightsByType or {},
        crashes = crashes or {},
        checkrides = checkrides or {}
    }
end)

-- =====================================
-- COMPANY FLIGHT LOG
-- =====================================

lib.callback.register('dps-airlines:server:getCompanyFlightLog', function(source, filters)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return {} end

    if Player.PlayerData.job.name ~= Config.Job or Player.PlayerData.job.grade.level < Config.BossGrade then
        return {}
    end

    local query = [[
        SELECT
            l.*,
            p.charinfo
        FROM airline_pilot_logbook l
        LEFT JOIN players p ON l.citizenid = p.citizenid
        WHERE 1=1
    ]]

    local params = {}

    if filters then
        if filters.flightType then
            query = query .. ' AND l.flight_type = ?'
            table.insert(params, filters.flightType)
        end
        if filters.pilotCitizenid then
            query = query .. ' AND l.citizenid = ?'
            table.insert(params, filters.pilotCitizenid)
        end
        if filters.days then
            query = query .. ' AND l.departure_time > DATE_SUB(NOW(), INTERVAL ? DAY)'
            table.insert(params, filters.days)
        end
    end

    query = query .. ' ORDER BY l.departure_time DESC LIMIT 100'

    local flights = MySQL.query.await(query, params)

    -- Parse charinfo for each flight
    for _, flight in ipairs(flights or {}) do
        if flight.charinfo then
            local charinfo = json.decode(flight.charinfo)
            flight.pilotName = string.format('%s %s', charinfo.firstname, charinfo.lastname)
            flight.charinfo = nil -- Remove raw data
        end
    end

    return flights or {}
end)

-- =====================================
-- COMPANY STATISTICS
-- =====================================

lib.callback.register('dps-airlines:server:getCompanyStats', function(source, period)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return nil end

    if Player.PlayerData.job.name ~= Config.Job or Player.PlayerData.job.grade.level < Config.BossGrade then
        return nil
    end

    local interval = period == 'week' and 7 or (period == 'month' and 30 or 365)

    -- Overall stats
    local overall = MySQL.single.await([[
        SELECT
            COUNT(*) as total_flights,
            COALESCE(SUM(flight_time), 0) as total_hours,
            COALESCE(SUM(passengers), 0) as total_passengers,
            COALESCE(SUM(cargo_kg), 0) as total_cargo,
            COALESCE(SUM(payment), 0) as total_revenue,
            COALESCE(AVG(payment), 0) as avg_payment
        FROM airline_pilot_logbook
        WHERE departure_time > DATE_SUB(NOW(), INTERVAL ? DAY)
        AND status = 'completed'
    ]], { interval })

    -- By flight type
    local byType = MySQL.query.await([[
        SELECT
            flight_type,
            COUNT(*) as flights,
            COALESCE(SUM(flight_time), 0) as hours,
            COALESCE(SUM(payment), 0) as revenue
        FROM airline_pilot_logbook
        WHERE departure_time > DATE_SUB(NOW(), INTERVAL ? DAY)
        GROUP BY flight_type
    ]], { interval })

    -- By aircraft
    local byAircraft = MySQL.query.await([[
        SELECT
            aircraft_model,
            COUNT(*) as flights,
            COALESCE(SUM(flight_time), 0) as hours
        FROM airline_pilot_logbook
        WHERE departure_time > DATE_SUB(NOW(), INTERVAL ? DAY)
        GROUP BY aircraft_model
        ORDER BY flights DESC
    ]], { interval })

    -- By route
    local byRoute = MySQL.query.await([[
        SELECT
            CONCAT(departure_airport, ' → ', arrival_airport) as route,
            COUNT(*) as flights,
            COALESCE(SUM(payment), 0) as revenue
        FROM airline_pilot_logbook
        WHERE departure_time > DATE_SUB(NOW(), INTERVAL ? DAY)
        GROUP BY departure_airport, arrival_airport
        ORDER BY flights DESC
        LIMIT 10
    ]], { interval })

    -- Top pilots
    local topPilots = MySQL.query.await([[
        SELECT
            l.citizenid,
            p.charinfo,
            COUNT(*) as flights,
            COALESCE(SUM(l.flight_time), 0) as hours,
            COALESCE(SUM(l.payment), 0) as earnings
        FROM airline_pilot_logbook l
        LEFT JOIN players p ON l.citizenid = p.citizenid
        WHERE l.departure_time > DATE_SUB(NOW(), INTERVAL ? DAY)
        GROUP BY l.citizenid
        ORDER BY hours DESC
        LIMIT 5
    ]], { interval })

    -- Parse pilot names
    for _, pilot in ipairs(topPilots or {}) do
        if pilot.charinfo then
            local charinfo = json.decode(pilot.charinfo)
            pilot.name = string.format('%s %s', charinfo.firstname, charinfo.lastname)
            pilot.charinfo = nil
        end
    end

    -- Safety stats
    local safety = MySQL.single.await([[
        SELECT
            (SELECT COUNT(*) FROM airline_crashes WHERE crash_time > DATE_SUB(NOW(), INTERVAL ? DAY)) as crashes,
            (SELECT COALESCE(SUM(hard_landings), 0) FROM airline_pilot_stats) as hard_landings,
            (SELECT COALESCE(SUM(incidents), 0) FROM airline_pilot_stats) as incidents
    ]], { interval })

    return {
        overall = overall,
        byType = byType or {},
        byAircraft = byAircraft or {},
        byRoute = byRoute or {},
        topPilots = topPilots or {},
        safety = safety or {}
    }
end)

-- =====================================
-- CHARTER MANAGEMENT (Boss)
-- =====================================

lib.callback.register('dps-airlines:server:getAllCharters', function(source, statusFilter)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return {} end

    if Player.PlayerData.job.name ~= Config.Job or Player.PlayerData.job.grade.level < Config.BossGrade then
        return {}
    end

    local query = [[
        SELECT c.*, p.charinfo as pilot_info
        FROM airline_charter_requests c
        LEFT JOIN players p ON c.assigned_pilot = p.citizenid
    ]]

    local params = {}

    if statusFilter then
        query = query .. ' WHERE c.status = ?'
        table.insert(params, statusFilter)
    end

    query = query .. ' ORDER BY c.created_at DESC LIMIT 50'

    local charters = MySQL.query.await(query, params)

    for _, charter in ipairs(charters or {}) do
        if charter.pilot_info then
            local info = json.decode(charter.pilot_info)
            charter.pilotName = string.format('%s %s', info.firstname, info.lastname)
            charter.pilot_info = nil
        end
    end

    return charters or {}
end)

-- =====================================
-- EMPLOYEE MANAGEMENT
-- =====================================

RegisterNetEvent('dps-airlines:server:hireEmployee', function(targetId)
    local source = source
    local Player = QBCore.Functions.GetPlayer(source)
    local Target = QBCore.Functions.GetPlayer(targetId)

    if not Player or not Target then return end

    if Player.PlayerData.job.name ~= Config.Job or Player.PlayerData.job.grade.level < Config.BossGrade then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Airlines',
            description = 'You do not have permission',
            type = 'error'
        })
        return
    end

    Target.Functions.SetJob('pilot', 0)

    TriggerClientEvent('ox_lib:notify', source, {
        title = 'Airlines',
        description = 'Employee hired',
        type = 'success'
    })

    TriggerClientEvent('ox_lib:notify', targetId, {
        title = 'Airlines',
        description = 'You have been hired as a pilot!',
        type = 'success'
    })
end)

RegisterNetEvent('dps-airlines:server:fireEmployee', function(citizenid)
    local source = source
    local Player = QBCore.Functions.GetPlayer(source)

    if not Player then return end

    if Player.PlayerData.job.name ~= Config.Job or Player.PlayerData.job.grade.level < Config.BossGrade then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Airlines',
            description = 'You do not have permission',
            type = 'error'
        })
        return
    end

    -- Get target player
    local Target = QBCore.Functions.GetPlayerByCitizenId(citizenid)

    if Target then
        Target.Functions.SetJob('unemployed', 0)
        TriggerClientEvent('ox_lib:notify', Target.PlayerData.source, {
            title = 'Airlines',
            description = 'You have been fired',
            type = 'error'
        })
    else
        -- Update offline player
        MySQL.update.await([[
            UPDATE players SET job = ? WHERE citizenid = ?
        ]], {
            json.encode({
                name = 'unemployed',
                label = 'Civilian',
                payment = 10,
                onduty = false,
                isboss = false,
                grade = { name = 'Freelancer', level = 0 }
            }),
            citizenid
        })
    end

    TriggerClientEvent('ox_lib:notify', source, {
        title = 'Airlines',
        description = 'Employee terminated',
        type = 'success'
    })
end)

RegisterNetEvent('dps-airlines:server:promoteEmployee', function(citizenid, newGrade)
    local source = source
    local Player = QBCore.Functions.GetPlayer(source)

    if not Player then return end

    if Player.PlayerData.job.name ~= Config.Job or Player.PlayerData.job.grade.level < Config.BossGrade then
        return
    end

    local Target = QBCore.Functions.GetPlayerByCitizenId(citizenid)

    if Target then
        Target.Functions.SetJob('pilot', newGrade)
        TriggerClientEvent('ox_lib:notify', Target.PlayerData.source, {
            title = 'Airlines',
            description = 'You have been promoted!',
            type = 'success'
        })
    end

    TriggerClientEvent('ox_lib:notify', source, {
        title = 'Airlines',
        description = 'Employee promoted',
        type = 'success'
    })
end)

-- =====================================
-- SOCIETY MANAGEMENT
-- =====================================

RegisterNetEvent('dps-airlines:server:withdrawSociety', function(amount)
    local source = source
    local Player = QBCore.Functions.GetPlayer(source)

    if not Player then return end

    if Player.PlayerData.job.name ~= Config.Job or Player.PlayerData.job.grade.level < Config.BossGrade then
        return
    end

    local success = exports['qb-management']:RemoveMoney('pilot', amount)

    if success then
        Player.Functions.AddMoney('cash', amount, 'society-withdrawal')
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Airlines',
            description = string.format('Withdrew $%d from company', amount),
            type = 'success'
        })
    else
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Airlines',
            description = 'Insufficient company funds',
            type = 'error'
        })
    end
end)

RegisterNetEvent('dps-airlines:server:depositSociety', function(amount)
    local source = source
    local Player = QBCore.Functions.GetPlayer(source)

    if not Player then return end

    if Player.PlayerData.job.name ~= Config.Job or Player.PlayerData.job.grade.level < Config.BossGrade then
        return
    end

    if Player.Functions.RemoveMoney('cash', amount, 'society-deposit') then
        exports['qb-management']:AddMoney('pilot', amount)
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Airlines',
            description = string.format('Deposited $%d to company', amount),
            type = 'success'
        })
    else
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Airlines',
            description = 'Insufficient funds',
            type = 'error'
        })
    end
end)

-- =====================================
-- MAINTENANCE HISTORY
-- =====================================

lib.callback.register('dps-airlines:server:getMaintenanceHistory', function(source)
    local history = MySQL.query.await([[
        SELECT * FROM airline_maintenance
        WHERE owned_by = 'company'
        ORDER BY last_service DESC
    ]])

    return history or {}
end)

print('^2[dps-airlines]^7 Boss module loaded')
