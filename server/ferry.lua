-- Ferry Flight System
-- Repositioning aircraft between locations
local QBCore = exports['qb-core']:GetCoreObject()

-- =====================================
-- FERRY JOB GENERATION
-- =====================================

local FerryReasons = {
    { reason = 'new_delivery', label = 'New Aircraft Delivery', payMultiplier = 1.5 },
    { reason = 'reposition', label = 'Fleet Reposition', payMultiplier = 1.0 },
    { reason = 'maintenance', label = 'Maintenance Transfer', payMultiplier = 1.2 },
    { reason = 'lease_return', label = 'Lease Return', payMultiplier = 1.3 },
}

local function GenerateFerryJob()
    local airports = {}
    for name, airport in pairs(Locations.Airports) do
        if not airport.isHub then
            table.insert(airports, name)
        end
    end

    if #airports < 2 then return nil end

    -- Random from/to (not the same)
    local fromIdx = math.random(1, #airports)
    local toIdx = fromIdx
    while toIdx == fromIdx do
        toIdx = math.random(1, #airports)
    end

    local fromAirport = airports[fromIdx]
    local toAirport = airports[toIdx]

    -- Random aircraft
    local planes = {}
    for model, _ in pairs(Config.Planes) do
        table.insert(planes, model)
    end
    local aircraft = planes[math.random(1, #planes)]

    -- Random reason
    local reasonData = FerryReasons[math.random(1, #FerryReasons)]

    -- Calculate payment based on distance
    local destAirport = Locations.Airports[toAirport]
    local distance = destAirport and destAirport.distance or 10
    local basePay = 200 + (distance * 30)
    local payment = math.floor(basePay * reasonData.payMultiplier)

    -- Priority based on reason
    local priority = 'normal'
    if reasonData.reason == 'new_delivery' then
        priority = 'high'
    elseif reasonData.reason == 'maintenance' then
        priority = math.random() > 0.5 and 'urgent' or 'high'
    end

    return {
        aircraft = aircraft,
        from = fromAirport,
        to = toAirport,
        reason = reasonData.reason,
        priority = priority,
        payment = payment,
        notes = string.format('%s - %s to %s',
            reasonData.label,
            Locations.Airports[fromAirport].label,
            Locations.Airports[toAirport].label
        )
    }
end

-- Periodic ferry job generation
CreateThread(function()
    while true do
        Wait(300000) -- Every 5 minutes

        -- Check current available ferry jobs
        local currentJobs = MySQL.scalar.await('SELECT COUNT(*) FROM airline_ferry_jobs WHERE status = ?', { 'available' })

        if currentJobs < 3 then
            local job = GenerateFerryJob()
            if job then
                -- Set deadline 2-4 hours from now
                local deadlineHours = math.random(2, 4)

                MySQL.insert.await([[
                    INSERT INTO airline_ferry_jobs
                    (aircraft_model, from_airport, to_airport, reason, priority, payment, deadline, notes, status)
                    VALUES (?, ?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL ? HOUR), ?, 'available')
                ]], {
                    job.aircraft,
                    job.from,
                    job.to,
                    job.reason,
                    job.priority,
                    job.payment,
                    deadlineHours,
                    job.notes
                })

                -- Notify online pilots
                local players = QBCore.Functions.GetQBPlayers()
                for _, player in pairs(players) do
                    if player.PlayerData.job.name == Config.Job and player.PlayerData.job.onduty then
                        TriggerClientEvent('dps-airlines:client:newFerryJob', player.PlayerData.source, {
                            aircraft = job.aircraft,
                            from_label = Locations.Airports[job.from].label,
                            to_label = Locations.Airports[job.to].label,
                            payment = job.payment,
                            priority = job.priority
                        })
                    end
                end
            end
        end
    end
end)

-- Expire old ferry jobs
CreateThread(function()
    while true do
        Wait(60000)
        MySQL.update.await('UPDATE airline_ferry_jobs SET status = ? WHERE status = ? AND deadline < NOW()', { 'expired', 'available' })
    end
end)

-- =====================================
-- FERRY JOB CALLBACKS
-- =====================================

lib.callback.register('dps-airlines:server:getAvailableFerryJobs', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return {} end

    local jobs = MySQL.query.await([[
        SELECT * FROM airline_ferry_jobs
        WHERE status = 'available'
        AND (deadline IS NULL OR deadline > NOW())
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

    return jobs or {}
end)

lib.callback.register('dps-airlines:server:acceptFerryJob', function(source, jobId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end

    local citizenid = Player.PlayerData.citizenid

    -- Check if job still available
    local job = MySQL.single.await('SELECT * FROM airline_ferry_jobs WHERE id = ? AND status = ?', { jobId, 'available' })

    if not job then
        return false, 'Job no longer available'
    end

    -- Check type rating
    local stats = MySQL.single.await('SELECT type_ratings FROM airline_pilot_stats WHERE citizenid = ?', { citizenid })
    if stats then
        local ratings = json.decode(stats.type_ratings or '[]')
        local hasRating = false
        for _, rating in ipairs(ratings) do
            if rating == job.aircraft_model then
                hasRating = true
                break
            end
        end

        -- Allow if no ratings yet (new pilot) or has the rating
        if #ratings > 0 and not hasRating then
            return false, 'You need a type rating for ' .. job.aircraft_model
        end
    end

    -- Assign job
    MySQL.update.await('UPDATE airline_ferry_jobs SET assigned_to = ?, status = ? WHERE id = ?', {
        citizenid,
        'assigned',
        jobId
    })

    return true, job
end)

RegisterNetEvent('dps-airlines:server:startFerryFlight', function(jobId)
    local source = source
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end

    MySQL.update.await('UPDATE airline_ferry_jobs SET status = ? WHERE id = ? AND assigned_to = ?', {
        'in_progress',
        jobId,
        Player.PlayerData.citizenid
    })
end)

RegisterNetEvent('dps-airlines:server:completeFerryJob', function(jobId)
    local source = source
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid

    local job = MySQL.single.await('SELECT * FROM airline_ferry_jobs WHERE id = ? AND assigned_to = ?', { jobId, citizenid })

    if not job then return end

    -- Mark complete
    MySQL.update.await('UPDATE airline_ferry_jobs SET status = ?, completed_at = NOW() WHERE id = ?', { 'completed', jobId })

    -- Pay pilot
    Player.Functions.AddMoney(Config.PaymentAccount, job.payment, 'ferry-flight-payment')

    -- Log the flight
    if CreateLogbookEntry then
        CreateLogbookEntry(citizenid, {
            flightId = nil,
            flightNumber = 'FERRY-' .. jobId,
            from = job.from_airport,
            to = job.to_airport,
            aircraft = job.aircraft_model,
            flightType = 'ferry',
            passengers = 0,
            cargo = 0,
            departureTime = os.time() - 1800, -- Estimate 30 min ago
            arrivalTime = os.time(),
            payment = job.payment,
            weather = GlobalState.airlineWeather and GlobalState.airlineWeather.weather or 'CLEAR',
            status = 'completed'
        })
    end

    TriggerClientEvent('ox_lib:notify', source, {
        title = 'Ferry Complete',
        description = string.format('Earned $%d for aircraft delivery', job.payment),
        type = 'success'
    })
end)

-- =====================================
-- BOSS: CREATE FERRY JOB
-- =====================================

RegisterNetEvent('dps-airlines:server:createFerryJob', function(data)
    local source = source
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end

    if Player.PlayerData.job.name ~= Config.Job or Player.PlayerData.job.grade.level < Config.BossGrade then
        return
    end

    MySQL.insert.await([[
        INSERT INTO airline_ferry_jobs
        (aircraft_model, from_airport, to_airport, reason, priority, payment, deadline, notes, status)
        VALUES (?, ?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL ? HOUR), ?, 'available')
    ]], {
        data.aircraft,
        data.from,
        data.to,
        data.reason or 'reposition',
        data.priority or 'normal',
        data.payment,
        data.deadline or 4,
        data.notes or ''
    })

    TriggerClientEvent('ox_lib:notify', source, {
        title = 'Ferry Job Created',
        description = 'New ferry job added to the board',
        type = 'success'
    })
end)

print('^2[dps-airlines]^7 Ferry module loaded')
