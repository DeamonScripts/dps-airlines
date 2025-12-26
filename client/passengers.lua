-- Passenger System
local QBCore = exports['qb-core']:GetCoreObject()

local PassengerPeds = {}
local SeatedPassengers = {}  -- Passengers currently "in" the plane
local BoardingInProgress = false

-- =====================================
-- PASSENGER NPC FUNCTIONS
-- With Logic Culling optimization
-- =====================================

local function GetRandomPassengerModel()
    local models = Config.Passengers.models
    return models[math.random(1, #models)]
end

local function SpawnPassengerPed(coords)
    local model = GetHashKey(GetRandomPassengerModel())
    lib.requestModel(model)

    local ped = CreatePed(4, model, coords.x, coords.y, coords.z - 1.0, coords.w or 0.0, true, true)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)

    return ped
end

-- =====================================
-- NPC LOGIC CULLING
-- Freeze passengers once seated to prevent physics/pathing calculations
-- =====================================

local function SeatPassengerInPlane(ped, plane)
    if not DoesEntityExist(ped) or not DoesEntityExist(plane) then return end

    -- Mark as mission entity to prevent cleanup
    SetEntityAsMissionEntity(ped, true, true)

    -- Freeze the ped completely - no physics, no AI
    FreezeEntityPosition(ped, true)
    SetEntityCollision(ped, false, false)
    SetEntityVisible(ped, false, false)  -- Hide since they're "inside"
    SetEntityInvincible(ped, true)

    -- Stop all AI processing
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)

    -- Track as seated
    SeatedPassengers[ped] = {
        plane = plane,
        seatedAt = GetGameTimer()
    }

    if Config.Debug then
        print('[dps-airlines] Passenger seated and frozen: ' .. ped)
    end
end

local function UnfreezePassenger(ped)
    if not DoesEntityExist(ped) then return end

    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)
    SetEntityVisible(ped, true, true)
    SetEntityInvincible(ped, false)
    SetBlockingOfNonTemporaryEvents(ped, false)
    SetPedCanRagdoll(ped, true)

    SeatedPassengers[ped] = nil
end

-- Get count of currently seated passengers
function GetSeatedPassengerCount()
    local count = 0
    for _ in pairs(SeatedPassengers) do
        count = count + 1
    end
    return count
end

exports('GetSeatedPassengerCount', GetSeatedPassengerCount)

-- =====================================
-- BOARDING SYSTEM
-- =====================================

function StartBoarding(passengerCount, gateCoords, planeCoords)
    if BoardingInProgress then
        lib.notify({ title = 'Airlines', description = 'Boarding already in progress', type = 'error' })
        return
    end

    if passengerCount <= 0 then return end

    BoardingInProgress = true

    lib.notify({
        title = 'Boarding',
        description = string.format('Boarding %d passengers...', passengerCount),
        type = 'inform'
    })

    -- Spawn passengers at gate
    for i = 1, passengerCount do
        local offset = vector3(
            math.random(-3, 3),
            math.random(-3, 3),
            0
        )
        local spawnPos = vector4(
            gateCoords.x + offset.x,
            gateCoords.y + offset.y,
            gateCoords.z,
            gateCoords.w or 0.0
        )

        local ped = SpawnPassengerPed(spawnPos)
        table.insert(PassengerPeds, ped)

        -- Make passenger walk to plane
        CreateThread(function()
            Wait(i * 500) -- Stagger departures

            TaskGoToCoordAnyMeans(ped, planeCoords.x, planeCoords.y, planeCoords.z, 1.0, 0, false, 786603, 0xbf800000)

            -- Wait for arrival then delete
            local timeout = 30000
            local startTime = GetGameTimer()

            while DoesEntityExist(ped) and GetGameTimer() - startTime < timeout do
                local pedCoords = GetEntityCoords(ped)
                local dist = #(pedCoords - vector3(planeCoords.x, planeCoords.y, planeCoords.z))

                if dist < 5.0 then
                    -- Fade out and delete
                    Wait(500)
                    if DoesEntityExist(ped) then
                        DeleteEntity(ped)
                    end
                    break
                end
                Wait(500)
            end

            -- Cleanup if timeout
            if DoesEntityExist(ped) then
                DeleteEntity(ped)
            end
        end)
    end

    -- Progress bar for boarding
    local success = lib.progressBar({
        duration = passengerCount * Config.Passengers.boardingTime,
        label = string.format('Boarding %d passengers...', passengerCount),
        useWhileDead = false,
        canCancel = false,
        disable = { move = false, car = false, combat = true }
    })

    BoardingInProgress = false
    CleanupPassengers()

    if success then
        lib.notify({
            title = 'Boarding Complete',
            description = string.format('%d passengers boarded', passengerCount),
            type = 'success'
        })
        return true
    end

    return false
end

-- =====================================
-- DEPLANING SYSTEM
-- =====================================

function StartDeplaning(passengerCount, planeCoords, terminalCoords)
    if passengerCount <= 0 then return true end

    lib.notify({
        title = 'Deplaning',
        description = string.format('%d passengers disembarking...', passengerCount),
        type = 'inform'
    })

    -- Spawn passengers at plane, walk to terminal
    for i = 1, passengerCount do
        local offset = vector3(
            math.random(-2, 2),
            math.random(-2, 2),
            0
        )
        local spawnPos = vector4(
            planeCoords.x + offset.x,
            planeCoords.y + offset.y,
            planeCoords.z,
            0.0
        )

        local ped = SpawnPassengerPed(spawnPos)
        table.insert(PassengerPeds, ped)

        CreateThread(function()
            Wait(i * 300)

            TaskGoToCoordAnyMeans(ped, terminalCoords.x, terminalCoords.y, terminalCoords.z, 1.0, 0, false, 786603, 0xbf800000)

            local timeout = 60000
            local startTime = GetGameTimer()

            while DoesEntityExist(ped) and GetGameTimer() - startTime < timeout do
                local pedCoords = GetEntityCoords(ped)
                local dist = #(pedCoords - vector3(terminalCoords.x, terminalCoords.y, terminalCoords.z))

                if dist < 10.0 then
                    Wait(1000)
                    if DoesEntityExist(ped) then
                        DeleteEntity(ped)
                    end
                    break
                end
                Wait(1000)
            end

            if DoesEntityExist(ped) then
                DeleteEntity(ped)
            end
        end)
    end

    local success = lib.progressBar({
        duration = passengerCount * 2000,
        label = string.format('%d passengers disembarking...', passengerCount),
        useWhileDead = false,
        canCancel = false,
        disable = { move = false, car = false, combat = true }
    })

    Wait(5000)
    CleanupPassengers()

    return true
end

-- =====================================
-- CLEANUP
-- =====================================

function CleanupPassengers()
    for _, ped in ipairs(PassengerPeds) do
        if DoesEntityExist(ped) then
            DeleteEntity(ped)
        end
    end
    PassengerPeds = {}
end

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        CleanupPassengers()
    end
end)

-- =====================================
-- EXPORTS
-- =====================================

exports('StartBoarding', StartBoarding)
exports('StartDeplaning', StartDeplaning)
exports('CleanupPassengers', CleanupPassengers)
