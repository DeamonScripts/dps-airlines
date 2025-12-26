-- Player Charter Request System
-- Any player can request a private charter flight
local QBCore = exports['qb-core']:GetCoreObject()

-- =====================================
-- CHARTER PRICING
-- =====================================

local function CalculateCharterPrice(from, to, passengers, vip, luggage)
    local fromAirport = Locations.Airports[from]
    local toAirport = Locations.Airports[to]

    if not fromAirport or not toAirport then return 0 end

    local distance = toAirport.distance or 10
    local baseFee = Config.Charter.baseFee or 500
    local perKmFee = Config.Charter.perKmFee or 5

    local price = baseFee + (distance * perKmFee)

    -- Passenger surcharge
    price = price + (passengers * 50)

    -- VIP service (premium pricing)
    if vip then
        price = price * 1.5
    end

    -- Luggage fee
    if luggage > 50 then
        price = price + ((luggage - 50) * 2)
    end

    return math.floor(price)
end

-- =====================================
-- PLAYER CHARTER REQUESTS
-- =====================================

lib.callback.register('dps-airlines:server:requestCharter', function(source, data)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end

    local citizenid = Player.PlayerData.citizenid
    local charinfo = Player.PlayerData.charinfo

    -- Check for existing pending request
    local existing = MySQL.single.await([[
        SELECT id FROM airline_charter_requests
        WHERE client_citizenid = ? AND status IN ('pending', 'quoted', 'confirmed', 'assigned')
    ]], { citizenid })

    if existing then
        return false, 'You already have an active charter request'
    end

    -- Calculate price
    local quotedPrice = CalculateCharterPrice(
        data.pickup,
        data.destination,
        data.passengers,
        data.vip,
        data.luggage
    )

    -- Get player phone
    local phone = Player.PlayerData.charinfo.phone or 'Unknown'

    -- Create request
    local requestId = MySQL.insert.await([[
        INSERT INTO airline_charter_requests (
            client_citizenid, client_name, client_phone,
            pickup_airport, destination_airport, passenger_count,
            flexibility, vip_service, luggage_kg, special_requests,
            quoted_price, status
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')
    ]], {
        citizenid,
        string.format('%s %s', charinfo.firstname, charinfo.lastname),
        phone,
        data.pickup,
        data.destination,
        data.passengers,
        data.flexibility or 'flexible_1hr',
        data.vip or false,
        data.luggage or 0,
        data.specialRequests,
        quotedPrice
    })

    -- Notify online pilots/managers
    local players = QBCore.Functions.GetQBPlayers()
    for _, player in pairs(players) do
        if player.PlayerData.job.name == Config.Job and player.PlayerData.job.onduty then
            TriggerClientEvent('dps-airlines:client:newCharterRequest', player.PlayerData.source, {
                id = requestId,
                client = string.format('%s %s', charinfo.firstname, charinfo.lastname),
                from = Locations.Airports[data.pickup].label,
                to = Locations.Airports[data.destination].label,
                passengers = data.passengers,
                vip = data.vip,
                price = quotedPrice
            })
        end
    end

    return true, {
        requestId = requestId,
        quotedPrice = quotedPrice,
        message = 'Charter request submitted. A pilot will contact you shortly.'
    }
end)

lib.callback.register('dps-airlines:server:getMyCharterRequests', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return {} end

    local requests = MySQL.query.await([[
        SELECT * FROM airline_charter_requests
        WHERE client_citizenid = ?
        ORDER BY created_at DESC
        LIMIT 10
    ]], { Player.PlayerData.citizenid })

    return requests or {}
end)

-- =====================================
-- PILOT CHARTER MANAGEMENT
-- =====================================

lib.callback.register('dps-airlines:server:getPendingCharters', function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return {} end

    if Player.PlayerData.job.name ~= Config.Job then return {} end

    local charters = MySQL.query.await([[
        SELECT * FROM airline_charter_requests
        WHERE status IN ('pending', 'quoted', 'confirmed')
        ORDER BY
            CASE flexibility
                WHEN 'asap' THEN 1
                WHEN 'exact' THEN 2
                WHEN 'flexible_1hr' THEN 3
                ELSE 4
            END,
            vip_service DESC,
            created_at ASC
        LIMIT 20
    ]])

    return charters or {}
end)

lib.callback.register('dps-airlines:server:acceptCharter', function(source, charterId)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return false end

    if Player.PlayerData.job.name ~= Config.Job then return false end

    local citizenid = Player.PlayerData.citizenid

    -- Check charter exists and is available
    local charter = MySQL.single.await([[
        SELECT * FROM airline_charter_requests WHERE id = ? AND status IN ('pending', 'quoted', 'confirmed')
    ]], { charterId })

    if not charter then
        return false, 'Charter no longer available'
    end

    -- Assign to pilot
    MySQL.update.await([[
        UPDATE airline_charter_requests SET
            assigned_pilot = ?,
            status = 'assigned'
        WHERE id = ?
    ]], { citizenid, charterId })

    -- Notify client if online
    local Client = QBCore.Functions.GetPlayerByCitizenId(charter.client_citizenid)
    if Client then
        TriggerClientEvent('ox_lib:notify', Client.PlayerData.source, {
            title = 'Charter Update',
            description = 'A pilot has accepted your charter! They will contact you shortly.',
            type = 'success'
        })
    end

    return true, charter
end)

RegisterNetEvent('dps-airlines:server:startCharter', function(charterId)
    local source = source
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end

    MySQL.update.await([[
        UPDATE airline_charter_requests SET
            status = 'in_progress',
            pickup_time = NOW()
        WHERE id = ? AND assigned_pilot = ?
    ]], { charterId, Player.PlayerData.citizenid })
end)

RegisterNetEvent('dps-airlines:server:completeCharter', function(charterId)
    local source = source
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid

    local charter = MySQL.single.await([[
        SELECT * FROM airline_charter_requests WHERE id = ? AND assigned_pilot = ?
    ]], { charterId, citizenid })

    if not charter then return end

    -- Mark complete
    MySQL.update.await([[
        UPDATE airline_charter_requests SET
            status = 'completed',
            final_price = quoted_price,
            dropoff_time = NOW()
        WHERE id = ?
    ]], { charterId })

    -- Pay pilot (80% of charter price, 20% to company)
    local pilotPay = math.floor(charter.quoted_price * 0.8)
    local companyPay = charter.quoted_price - pilotPay

    Player.Functions.AddMoney(Config.PaymentAccount, pilotPay, 'charter-payment')

    -- Add to society if enabled
    if Config.UseSocietyFunds then
        pcall(function()
            exports['qb-management']:AddMoney('pilot', companyPay)
        end)
    end

    -- Log the flight
    if CreateLogbookEntry then
        CreateLogbookEntry(citizenid, {
            flightNumber = 'CHARTER-' .. charterId,
            from = charter.pickup_airport,
            to = charter.destination_airport,
            aircraft = charter.assigned_aircraft or 'luxor',
            flightType = 'charter',
            passengers = charter.passenger_count,
            cargo = charter.luggage_kg or 0,
            departureTime = os.time() - 1800,
            arrivalTime = os.time(),
            payment = pilotPay,
            status = 'completed'
        })
    end

    TriggerClientEvent('ox_lib:notify', source, {
        title = 'Charter Complete',
        description = string.format('Earned $%d for charter flight', pilotPay),
        type = 'success'
    })

    -- Notify client
    local Client = QBCore.Functions.GetPlayerByCitizenId(charter.client_citizenid)
    if Client then
        TriggerClientEvent('ox_lib:notify', Client.PlayerData.source, {
            title = 'Thank You!',
            description = 'Thank you for flying with DPS Airlines',
            type = 'success'
        })

        -- Prompt for rating
        TriggerClientEvent('dps-airlines:client:promptCharterRating', Client.PlayerData.source, charterId)
    end
end)

-- =====================================
-- CLIENT RATING
-- =====================================

RegisterNetEvent('dps-airlines:server:rateCharter', function(charterId, rating, feedback)
    local source = source
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end

    MySQL.update.await([[
        UPDATE airline_charter_requests SET
            pilot_rating = ?,
            client_feedback = ?
        WHERE id = ? AND client_citizenid = ?
    ]], { rating, feedback, charterId, Player.PlayerData.citizenid })

    TriggerClientEvent('ox_lib:notify', source, {
        title = 'Thank You',
        description = 'Your feedback has been recorded',
        type = 'success'
    })
end)

-- =====================================
-- CHARTER CANCELLATION
-- =====================================

RegisterNetEvent('dps-airlines:server:cancelCharter', function(charterId, reason)
    local source = source
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid

    -- Can cancel if client or assigned pilot
    local charter = MySQL.single.await([[
        SELECT * FROM airline_charter_requests WHERE id = ?
    ]], { charterId })

    if not charter then return end

    if charter.client_citizenid ~= citizenid and charter.assigned_pilot ~= citizenid then
        -- Check if boss
        if Player.PlayerData.job.name ~= Config.Job or Player.PlayerData.job.grade.level < Config.BossGrade then
            return
        end
    end

    local newStatus = 'cancelled'
    if charter.assigned_pilot == citizenid then
        -- Pilot cancelled, make available again
        MySQL.update.await([[
            UPDATE airline_charter_requests SET
                status = 'confirmed',
                assigned_pilot = NULL
            WHERE id = ?
        ]], { charterId })
    else
        MySQL.update.await('UPDATE airline_charter_requests SET status = ? WHERE id = ?', { newStatus, charterId })
    end

    TriggerClientEvent('ox_lib:notify', source, {
        title = 'Charter',
        description = 'Charter has been cancelled',
        type = 'warning'
    })
end)

print('^2[dps-airlines]^7 Charter Requests module loaded')
