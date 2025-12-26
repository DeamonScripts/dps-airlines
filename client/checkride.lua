-- Checkride System for Recurrent Training
-- Pilots inactive for 14+ days must complete a checkride
local QBCore = exports['qb-core']:GetCoreObject()

-- =====================================
-- CONFIGURATION
-- =====================================

local CheckrideConfig = {
    inactivityDays = 14,         -- Days before checkride required
    warningDays = 10,            -- Days to start warning
    checkrideTimeLimit = 300000, -- 5 minutes to complete checkride
}

local CheckrideActive = false
local CheckrideData = nil

-- =====================================
-- CHECKRIDE STATUS CHECK
-- Called when pilot clocks in
-- =====================================

function CheckRecurrentTrainingStatus()
    local status = lib.callback.await('dps-airlines:server:getCheckrideStatus', false)

    if not status then return true end -- Allow if can't check

    if status.required then
        -- Checkride required
        local daysInactive = status.daysInactive or 14

        lib.alertDialog({
            header = 'Recurrent Training Required',
            content = string.format([[
**You have been inactive for %d days.**

FAA regulations require pilots to complete recurrent training after extended periods of inactivity.

You must complete a checkride before taking flight assignments.

**What to expect:**
- Basic takeoff and landing
- Navigation checkpoint
- Emergency procedure demonstration

Would you like to begin your checkride now?
            ]], daysInactive),
            centered = true,
            cancel = false,
            labels = {
                confirm = 'Begin Checkride'
            }
        })

        StartCheckride()
        return false
    elseif status.warning then
        -- Warning period
        local daysRemaining = status.daysRemaining or 4

        lib.notify({
            title = 'Training Reminder',
            description = string.format('Recurrent training due in %d days. Stay active to avoid checkride.', daysRemaining),
            type = 'warning',
            duration = 10000
        })
    end

    return true
end

-- =====================================
-- CHECKRIDE EXECUTION
-- =====================================

function StartCheckride()
    if CheckrideActive then return end

    CheckrideActive = true
    CheckrideData = {
        startTime = GetGameTimer(),
        phases = {
            takeoff = false,
            altitude = false,
            navigation = false,
            landing = false
        },
        score = 100,
        penalties = {}
    }

    -- Spawn training aircraft
    local spawnPoint = Locations.Hub.planeSpawns[1]
    local hash = GetHashKey('luxor')
    lib.requestModel(hash)

    local plane = CreateVehicle(hash, spawnPoint.x, spawnPoint.y, spawnPoint.z, spawnPoint.w, true, false)
    SetVehicleOnGroundProperly(plane)
    SetEntityAsMissionEntity(plane, true, true)

    CheckrideData.plane = plane
    SetPedIntoVehicle(PlayerPedId(), plane, -1)

    lib.notify({
        title = 'Checkride Started',
        description = 'Complete all phases: Takeoff → Navigate to checkpoint → Land safely',
        type = 'inform',
        duration = 10000
    })

    -- Set navigation checkpoint
    local checkpoint = Locations.Airports['sandy']
    if checkpoint then
        SetNewWaypoint(checkpoint.coords.x, checkpoint.coords.y)
        CheckrideData.checkpoint = checkpoint
    end

    -- Start monitoring thread
    CreateThread(function()
        MonitorCheckride()
    end)
end

function MonitorCheckride()
    local phase = 'ground'

    while CheckrideActive do
        Wait(500)

        -- Timeout check
        if GetGameTimer() - CheckrideData.startTime > CheckrideConfig.checkrideTimeLimit then
            FailCheckride('Time limit exceeded')
            break
        end

        local plane = CheckrideData.plane
        if not plane or not DoesEntityExist(plane) then
            FailCheckride('Aircraft destroyed')
            break
        end

        local coords = GetEntityCoords(plane)
        local altitude = coords.z
        local heightAboveGround = GetEntityHeightAboveGround(plane)
        local speed = GetEntitySpeed(plane) * 3.6
        local health = GetEntityHealth(plane)

        -- Damage penalty
        if health < 800 and not CheckrideData.damagePenaltyApplied then
            AddPenalty('Aircraft damage', 10)
            CheckrideData.damagePenaltyApplied = true
        end

        -- Phase: Takeoff
        if phase == 'ground' then
            if heightAboveGround > 30 then
                phase = 'flying'
                CheckrideData.phases.takeoff = true
                lib.notify({
                    title = 'Checkride',
                    description = 'Phase 1: Takeoff complete. Navigate to Sandy Shores.',
                    type = 'success'
                })
            end
        end

        -- Phase: Reach altitude
        if phase == 'flying' and not CheckrideData.phases.altitude then
            if altitude > 300 then
                CheckrideData.phases.altitude = true
                lib.notify({
                    title = 'Checkride',
                    description = 'Good altitude. Continue to checkpoint.',
                    type = 'inform'
                })
            end
        end

        -- Phase: Navigate to checkpoint
        if phase == 'flying' and CheckrideData.phases.takeoff then
            local checkpoint = CheckrideData.checkpoint
            if checkpoint then
                local dist = #(coords - vector3(checkpoint.coords.x, checkpoint.coords.y, checkpoint.coords.z))

                if dist < 500 then
                    if not CheckrideData.phases.navigation then
                        CheckrideData.phases.navigation = true
                        lib.notify({
                            title = 'Checkride',
                            description = 'Phase 2: Navigation complete. Return to LSIA and land.',
                            type = 'success'
                        })

                        -- Set waypoint back to LSIA
                        SetNewWaypoint(Locations.Hub.coords.x, Locations.Hub.coords.y)
                    end
                end
            end
        end

        -- Phase: Landing
        if CheckrideData.phases.navigation then
            local hubDist = #(coords - vector3(Locations.Hub.coords.x, Locations.Hub.coords.y, Locations.Hub.coords.z))

            if hubDist < 500 and heightAboveGround < 5 and speed < 10 then
                -- Check landing quality
                if speed > 5 then
                    AddPenalty('Hard landing', 5)
                end

                CheckrideData.phases.landing = true
                CompleteCheckride()
                break
            end
        end
    end
end

function AddPenalty(reason, points)
    CheckrideData.score = math.max(0, CheckrideData.score - points)
    table.insert(CheckrideData.penalties, { reason = reason, points = points })

    lib.notify({
        title = 'Checkride Penalty',
        description = string.format('-%d points: %s', points, reason),
        type = 'error'
    })
end

-- =====================================
-- CHECKRIDE COMPLETION
-- =====================================

function CompleteCheckride()
    if not CheckrideActive then return end

    local passed = CheckrideData.score >= 70

    CheckrideActive = false

    -- Build results message
    local penaltyText = ''
    if #CheckrideData.penalties > 0 then
        penaltyText = '\n\n**Deductions:**'
        for _, penalty in ipairs(CheckrideData.penalties) do
            penaltyText = penaltyText .. string.format('\n- %s: -%d', penalty.reason, penalty.points)
        end
    end

    lib.alertDialog({
        header = passed and 'Checkride Passed!' or 'Checkride Failed',
        content = string.format([[
**Final Score:** %d/100

%s
%s

%s
        ]],
            CheckrideData.score,
            passed and 'Congratulations! Your pilot certification has been renewed.' or 'You did not meet the minimum score of 70.',
            penaltyText,
            passed and 'You may now accept flight assignments.' or 'Please try again to continue working as a pilot.'
        ),
        centered = true,
        cancel = false
    })

    -- Report to server
    TriggerServerEvent('dps-airlines:server:completeCheckride', {
        passed = passed,
        score = CheckrideData.score,
        penalties = CheckrideData.penalties
    })

    CleanupCheckride()
end

function FailCheckride(reason)
    if not CheckrideActive then return end

    CheckrideActive = false

    lib.notify({
        title = 'Checkride Failed',
        description = reason,
        type = 'error',
        duration = 5000
    })

    TriggerServerEvent('dps-airlines:server:completeCheckride', {
        passed = false,
        score = 0,
        reason = reason
    })

    CleanupCheckride()
end

function CleanupCheckride()
    if CheckrideData and CheckrideData.plane and DoesEntityExist(CheckrideData.plane) then
        local ped = PlayerPedId()
        if IsPedInVehicle(ped, CheckrideData.plane, false) then
            TaskLeaveVehicle(ped, CheckrideData.plane, 0)
            Wait(2000)
        end
        DeleteEntity(CheckrideData.plane)
    end

    CheckrideData = nil
    CheckrideActive = false
end

-- =====================================
-- SERVER HANDLERS
-- =====================================

RegisterNetEvent('dps-airlines:client:requireCheckride', function()
    StartCheckride()
end)

-- =====================================
-- DUTY CHECK HOOK
-- =====================================

RegisterNetEvent('dps-airlines:client:dutyChanged', function(onDuty)
    if onDuty then
        -- Check if checkride required before allowing duty
        CheckRecurrentTrainingStatus()
    end
end)

-- Cleanup on resource stop
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        CleanupCheckride()
    end
end)

-- =====================================
-- EXPORTS
-- =====================================

exports('IsCheckrideActive', function() return CheckrideActive end)
exports('StartCheckride', StartCheckride)
exports('CheckRecurrentTrainingStatus', CheckRecurrentTrainingStatus)
