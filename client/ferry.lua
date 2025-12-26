-- Ferry Flight Client
-- Repositioning aircraft between locations
local QBCore = exports['qb-core']:GetCoreObject()

local ActiveFerryJob = nil

-- =====================================
-- FERRY JOBS MENU
-- =====================================

function OpenFerryJobsMenu()
    if not OnDuty then
        lib.notify({ title = 'Airlines', description = 'You must be on duty', type = 'error' })
        return
    end

    local jobs = lib.callback.await('dps-airlines:server:getAvailableFerryJobs', false)

    local options = {
        {
            title = 'Ferry Flight Operations',
            description = 'Reposition aircraft between locations',
            icon = 'fas fa-plane-arrival',
            disabled = true
        }
    }

    if ActiveFerryJob then
        local toAirport = Locations.Airports[ActiveFerryJob.to_airport]
        table.insert(options, {
            title = '▶ ACTIVE: Deliver to ' .. (toAirport and toAirport.label or ActiveFerryJob.to_airport),
            description = string.format('%s | $%d', ActiveFerryJob.aircraft_model:upper(), ActiveFerryJob.payment),
            icon = 'fas fa-plane-departure',
            onSelect = function()
                OpenActiveFerryMenu()
            end
        })
    end

    if #jobs == 0 then
        table.insert(options, {
            title = 'No Ferry Jobs Available',
            description = 'Check back later',
            icon = 'fas fa-clock',
            disabled = true
        })
    else
        for _, job in ipairs(jobs) do
            local fromAirport = Locations.Airports[job.from_airport]
            local toAirport = Locations.Airports[job.to_airport]
            local planeData = Config.Planes[job.aircraft_model]

            local reasonLabels = {
                new_delivery = 'New Aircraft',
                reposition = 'Reposition',
                maintenance = 'Maintenance',
                lease_return = 'Lease Return'
            }

            table.insert(options, {
                title = string.format('%s → %s',
                    fromAirport and fromAirport.label or job.from_airport,
                    toAirport and toAirport.label or job.to_airport
                ),
                description = string.format('[%s] %s | %s | $%d',
                    job.priority:upper(),
                    reasonLabels[job.reason] or job.reason,
                    planeData and planeData.label or job.aircraft_model,
                    job.payment
                ),
                icon = 'fas fa-truck-plane',
                disabled = ActiveFerryJob ~= nil,
                metadata = {
                    { label = 'Aircraft', value = planeData and planeData.label or job.aircraft_model },
                    { label = 'Reason', value = reasonLabels[job.reason] or job.reason },
                    { label = 'Priority', value = job.priority:upper() },
                    { label = 'Payment', value = '$' .. job.payment }
                },
                onSelect = function()
                    AcceptFerryJob(job)
                end
            })
        end
    end

    lib.registerContext({
        id = 'airlines_ferry_menu',
        title = 'Ferry Flight Board',
        options = options
    })

    lib.showContext('airlines_ferry_menu')
end

function OpenActiveFerryMenu()
    if not ActiveFerryJob then return end

    local fromAirport = Locations.Airports[ActiveFerryJob.from_airport]
    local toAirport = Locations.Airports[ActiveFerryJob.to_airport]

    local options = {
        {
            title = 'Current Ferry Job',
            description = string.format('%s → %s',
                fromAirport and fromAirport.label or ActiveFerryJob.from_airport,
                toAirport and toAirport.label or ActiveFerryJob.to_airport
            ),
            icon = 'fas fa-info-circle',
            disabled = true,
            metadata = {
                { label = 'Aircraft', value = ActiveFerryJob.aircraft_model },
                { label = 'Payment', value = '$' .. ActiveFerryJob.payment }
            }
        },
        {
            title = 'Set Waypoint to Pickup',
            icon = 'fas fa-map-marker-alt',
            onSelect = function()
                if fromAirport then
                    SetNewWaypoint(fromAirport.coords.x, fromAirport.coords.y)
                    lib.notify({ title = 'Navigation', description = 'Pickup waypoint set', type = 'success' })
                end
            end
        },
        {
            title = 'Set Waypoint to Destination',
            icon = 'fas fa-flag-checkered',
            onSelect = function()
                if toAirport then
                    SetNewWaypoint(toAirport.coords.x, toAirport.coords.y)
                    lib.notify({ title = 'Navigation', description = 'Destination waypoint set', type = 'success' })
                end
            end
        }
    }

    lib.registerContext({
        id = 'airlines_active_ferry',
        title = 'Active Ferry Job',
        menu = 'airlines_ferry_menu',
        options = options
    })

    lib.showContext('airlines_active_ferry')
end

-- =====================================
-- FERRY JOB ACCEPTANCE
-- =====================================

function AcceptFerryJob(job)
    local confirm = lib.alertDialog({
        header = 'Accept Ferry Job',
        content = string.format([[
**Aircraft:** %s
**From:** %s
**To:** %s
**Reason:** %s
**Payment:** $%d

You will need to travel to the pickup location to get the aircraft.

Accept this ferry job?
        ]],
            Config.Planes[job.aircraft_model] and Config.Planes[job.aircraft_model].label or job.aircraft_model,
            Locations.Airports[job.from_airport] and Locations.Airports[job.from_airport].label or job.from_airport,
            Locations.Airports[job.to_airport] and Locations.Airports[job.to_airport].label or job.to_airport,
            job.reason,
            job.payment
        ),
        centered = true,
        cancel = true
    })

    if confirm == 'confirm' then
        local success, result = lib.callback.await('dps-airlines:server:acceptFerryJob', false, job.id)

        if success then
            ActiveFerryJob = result
            local fromAirport = Locations.Airports[job.from_airport]
            if fromAirport then
                SetNewWaypoint(fromAirport.coords.x, fromAirport.coords.y)
            end
            lib.notify({
                title = 'Ferry Job Accepted',
                description = 'Head to pickup location',
                type = 'success'
            })
        else
            lib.notify({
                title = 'Ferry Job',
                description = result or 'Failed to accept job',
                type = 'error'
            })
        end
    end
end

-- =====================================
-- FERRY JOB COMPLETION MONITOR
-- =====================================

CreateThread(function()
    while true do
        Wait(3000)

        if ActiveFerryJob and CurrentPlane and DoesEntityExist(CurrentPlane) then
            local toAirport = Locations.Airports[ActiveFerryJob.to_airport]
            if toAirport then
                local coords = GetEntityCoords(CurrentPlane)
                local dist = #(coords - vector3(toAirport.coords.x, toAirport.coords.y, toAirport.coords.z))
                local heightAboveGround = GetEntityHeightAboveGround(CurrentPlane)
                local speed = GetEntitySpeed(CurrentPlane)

                -- Check if landed at destination
                if dist < 200 and heightAboveGround < 5 and speed < 10 then
                    CompleteFerryJob()
                end
            end
        end
    end
end)

function CompleteFerryJob()
    if not ActiveFerryJob then return end

    TriggerServerEvent('dps-airlines:server:completeFerryJob', ActiveFerryJob.id)

    lib.notify({
        title = 'Ferry Complete',
        description = 'Aircraft delivered successfully',
        type = 'success'
    })

    ActiveFerryJob = nil
end

-- =====================================
-- NOTIFICATIONS
-- =====================================

RegisterNetEvent('dps-airlines:client:newFerryJob', function(job)
    if OnDuty then
        lib.notify({
            title = 'New Ferry Job',
            description = string.format('[%s] %s to %s | $%d',
                job.priority:upper(),
                job.from_label,
                job.to_label,
                job.payment
            ),
            type = 'inform',
            duration = 8000
        })
        PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', false)
    end
end)

-- =====================================
-- EXPORTS
-- =====================================

exports('OpenFerryJobsMenu', OpenFerryJobsMenu)
exports('GetActiveFerryJob', function() return ActiveFerryJob end)
