-- Private Charter System
-- Updated to work with charter_requests.lua backend
local QBCore = exports['qb-core']:GetCoreObject()

local ActiveCharter = nil
local CharterBlip = nil
local MyCharterRequest = nil

-- =====================================
-- PILOT CHARTER MENU (For Pilots)
-- =====================================

function OpenCharterMenu()
    if not OnDuty then
        lib.notify({ title = 'Airlines', description = 'You must be on duty', type = 'error' })
        return
    end

    local charters = lib.callback.await('dps-airlines:server:getPendingCharters', false)
    local options = {}

    -- Show active charter if any
    if ActiveCharter then
        local pickup = Locations.Airports[ActiveCharter.pickup_airport]
        local dest = Locations.Airports[ActiveCharter.destination_airport]
        table.insert(options, {
            title = '▶ ACTIVE CHARTER',
            description = string.format('%s → %s | %d pax | $%d',
                pickup and pickup.label or ActiveCharter.pickup_airport,
                dest and dest.label or ActiveCharter.destination_airport,
                ActiveCharter.passenger_count,
                ActiveCharter.quoted_price
            ),
            icon = 'fas fa-plane-departure',
            onSelect = function()
                OpenActiveCharterMenu()
            end
        })
    end

    if not charters or #charters == 0 then
        table.insert(options, {
            title = 'No Charter Requests',
            description = 'Check back later for private charter requests',
            icon = 'fas fa-info-circle',
            disabled = true
        })
    else
        for _, charter in ipairs(charters) do
            local pickup = Locations.Airports[charter.pickup_airport]
            local dest = Locations.Airports[charter.destination_airport]
            local vipTag = charter.vip_service and ' [VIP]' or ''
            local urgencyColor = charter.flexibility == 'asap' and '^1' or ''

            table.insert(options, {
                title = string.format('%s → %s%s',
                    pickup and pickup.label or charter.pickup_airport,
                    dest and dest.label or charter.destination_airport,
                    vipTag
                ),
                description = string.format('%d passengers | $%d | %s',
                    charter.passenger_count,
                    charter.quoted_price,
                    charter.flexibility:upper()
                ),
                icon = charter.vip_service and 'fas fa-crown' or 'fas fa-user-tie',
                disabled = ActiveCharter ~= nil,
                metadata = {
                    { label = 'Client', value = charter.client_name },
                    { label = 'Passengers', value = tostring(charter.passenger_count) },
                    { label = 'Luggage', value = (charter.luggage_kg or 0) .. ' kg' },
                    { label = 'VIP Service', value = charter.vip_service and 'Yes' or 'No' },
                    { label = 'Price', value = '$' .. charter.quoted_price }
                },
                onSelect = function()
                    AcceptCharterRequest(charter)
                end
            })
        end
    end

    lib.registerContext({
        id = 'airlines_charter_menu',
        title = 'Charter Requests',
        menu = 'airlines_main_menu',
        options = options
    })

    lib.showContext('airlines_charter_menu')
end

function AcceptCharterRequest(charter)
    local pickup = Locations.Airports[charter.pickup_airport]
    local dest = Locations.Airports[charter.destination_airport]

    local confirm = lib.alertDialog({
        header = 'Accept Charter Request',
        content = string.format([[
**Client:** %s
**From:** %s
**To:** %s
**Passengers:** %d
**Luggage:** %d kg
**VIP Service:** %s
**Special Requests:** %s

**Your Payment:** $%d (80%% of fare)

Accept this charter?
        ]],
            charter.client_name,
            pickup and pickup.label or charter.pickup_airport,
            dest and dest.label or charter.destination_airport,
            charter.passenger_count,
            charter.luggage_kg or 0,
            charter.vip_service and 'Yes' or 'No',
            charter.special_requests or 'None',
            math.floor(charter.quoted_price * 0.8)
        ),
        centered = true,
        cancel = true
    })

    if confirm == 'confirm' then
        local success, result = lib.callback.await('dps-airlines:server:acceptCharter', false, charter.id)

        if success then
            ActiveCharter = result
            local pickupAirport = Locations.Airports[result.pickup_airport]

            if pickupAirport then
                SetNewWaypoint(pickupAirport.coords.x, pickupAirport.coords.y)
                CreateCharterBlip(pickupAirport.coords, 'Charter Pickup', 5)
            end

            lib.notify({
                title = 'Charter Accepted',
                description = 'Head to pickup location',
                type = 'success'
            })
        else
            lib.notify({
                title = 'Charter',
                description = result or 'Failed to accept charter',
                type = 'error'
            })
        end
    end
end

function OpenActiveCharterMenu()
    if not ActiveCharter then return end

    local pickup = Locations.Airports[ActiveCharter.pickup_airport]
    local dest = Locations.Airports[ActiveCharter.destination_airport]

    local options = {
        {
            title = 'Charter Details',
            description = string.format('%s → %s',
                pickup and pickup.label or ActiveCharter.pickup_airport,
                dest and dest.label or ActiveCharter.destination_airport
            ),
            icon = 'fas fa-info-circle',
            disabled = true,
            metadata = {
                { label = 'Client', value = ActiveCharter.client_name },
                { label = 'Passengers', value = tostring(ActiveCharter.passenger_count) },
                { label = 'Payment', value = '$' .. math.floor(ActiveCharter.quoted_price * 0.8) }
            }
        },
        {
            title = 'Set Waypoint to Pickup',
            icon = 'fas fa-map-marker-alt',
            onSelect = function()
                if pickup then
                    SetNewWaypoint(pickup.coords.x, pickup.coords.y)
                    CreateCharterBlip(pickup.coords, 'Charter Pickup', 5)
                    lib.notify({ title = 'Navigation', description = 'Pickup waypoint set', type = 'success' })
                end
            end
        },
        {
            title = 'Set Waypoint to Destination',
            icon = 'fas fa-flag-checkered',
            onSelect = function()
                if dest then
                    SetNewWaypoint(dest.coords.x, dest.coords.y)
                    CreateCharterBlip(dest.coords, 'Charter Destination', 2)
                    lib.notify({ title = 'Navigation', description = 'Destination waypoint set', type = 'success' })
                end
            end
        },
        {
            title = 'Start Charter Flight',
            description = 'Mark client as picked up',
            icon = 'fas fa-plane-departure',
            onSelect = function()
                StartCharterFlight()
            end
        },
        {
            title = 'Complete Charter',
            description = 'Mark charter as delivered',
            icon = 'fas fa-check-circle',
            onSelect = function()
                CompleteCharterFlight()
            end
        },
        {
            title = 'Cancel Charter',
            description = 'Return charter to pool',
            icon = 'fas fa-times-circle',
            onSelect = function()
                CancelCharter()
            end
        }
    }

    lib.registerContext({
        id = 'airlines_active_charter',
        title = 'Active Charter',
        menu = 'airlines_charter_menu',
        options = options
    })

    lib.showContext('airlines_active_charter')
end

function CreateCharterBlip(coords, label, color)
    if CharterBlip then
        RemoveBlip(CharterBlip)
    end

    CharterBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(CharterBlip, 280)
    SetBlipColour(CharterBlip, color)
    SetBlipScale(CharterBlip, 0.8)
    SetBlipRoute(CharterBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label)
    EndTextCommandSetBlipName(CharterBlip)
end

function StartCharterFlight()
    if not ActiveCharter then return end

    TriggerServerEvent('dps-airlines:server:startCharter', ActiveCharter.id)

    local dest = Locations.Airports[ActiveCharter.destination_airport]
    if dest then
        SetNewWaypoint(dest.coords.x, dest.coords.y)
        CreateCharterBlip(dest.coords, 'Charter Destination', 2)
    end

    lib.notify({
        title = 'Charter Started',
        description = 'Client aboard! Head to destination',
        type = 'success'
    })
end

function CompleteCharterFlight()
    if not ActiveCharter then return end

    local dest = Locations.Airports[ActiveCharter.destination_airport]

    -- Check if near destination
    if dest then
        local playerPos = GetEntityCoords(PlayerPedId())
        local dist = #(playerPos - vector3(dest.coords.x, dest.coords.y, dest.coords.z))

        if dist > 300 then
            lib.notify({
                title = 'Charter',
                description = 'You are not at the destination',
                type = 'error'
            })
            return
        end
    end

    TriggerServerEvent('dps-airlines:server:completeCharter', ActiveCharter.id)

    if CharterBlip then
        RemoveBlip(CharterBlip)
        CharterBlip = nil
    end

    ActiveCharter = nil
end

-- =====================================
-- PUBLIC CHARTER REQUEST (For Any Player)
-- =====================================

function OpenPublicCharterMenu()
    -- Build airport options
    local airportOptions = {}
    for name, airport in pairs(Locations.Airports) do
        table.insert(airportOptions, { value = name, label = airport.label })
    end

    local input = lib.inputDialog('Request Private Charter', {
        {
            type = 'select',
            label = 'Pickup Airport',
            options = airportOptions,
            required = true
        },
        {
            type = 'select',
            label = 'Destination Airport',
            options = airportOptions,
            required = true
        },
        {
            type = 'number',
            label = 'Number of Passengers',
            min = 1,
            max = 10,
            default = 1,
            required = true
        },
        {
            type = 'number',
            label = 'Luggage (kg)',
            min = 0,
            max = 200,
            default = 20
        },
        {
            type = 'checkbox',
            label = 'VIP Service (+50% for premium experience)'
        },
        {
            type = 'select',
            label = 'Timing Flexibility',
            options = {
                { value = 'asap', label = 'ASAP - As soon as possible' },
                { value = 'flexible_1hr', label = 'Flexible - Within 1 hour' },
                { value = 'flexible_day', label = 'Anytime Today' }
            },
            default = 'flexible_1hr'
        },
        {
            type = 'textarea',
            label = 'Special Requests (optional)',
            placeholder = 'Any special requirements...'
        }
    })

    if not input then return end

    if input[1] == input[2] then
        lib.notify({ title = 'Charter', description = 'Pickup and destination must be different', type = 'error' })
        return
    end

    local charterData = {
        pickup = input[1],
        destination = input[2],
        passengers = input[3],
        luggage = input[4] or 0,
        vip = input[5],
        flexibility = input[6],
        specialRequests = input[7]
    }

    -- Get price quote
    local success, result = lib.callback.await('dps-airlines:server:requestCharter', false, charterData)

    if success then
        MyCharterRequest = result.requestId

        lib.alertDialog({
            header = 'Charter Requested!',
            content = string.format([[
**Quoted Price:** $%d

Your charter request has been submitted. A pilot will be notified and will contact you shortly.

**Request ID:** #%d

You can check the status of your request at the airport terminal.
            ]], result.quotedPrice, result.requestId),
            centered = true
        })

        lib.notify({
            title = 'Charter Requested',
            description = 'A pilot will contact you shortly',
            type = 'success',
            duration = 8000
        })
    else
        lib.notify({
            title = 'Charter Request Failed',
            description = result or 'Could not submit request',
            type = 'error'
        })
    end
end

function ViewMyCharterStatus()
    local requests = lib.callback.await('dps-airlines:server:getMyCharterRequests', false)

    local options = {}

    if not requests or #requests == 0 then
        table.insert(options, {
            title = 'No Charter Requests',
            description = 'You have not made any charter requests',
            icon = 'fas fa-info-circle',
            disabled = true
        })
    else
        for _, request in ipairs(requests) do
            local pickup = Locations.Airports[request.pickup_airport]
            local dest = Locations.Airports[request.destination_airport]

            local statusLabels = {
                pending = 'Waiting for pilot',
                quoted = 'Quote ready',
                confirmed = 'Confirmed',
                assigned = 'Pilot assigned',
                in_progress = 'In flight',
                completed = 'Completed',
                cancelled = 'Cancelled'
            }

            local statusIcons = {
                pending = 'fas fa-clock',
                assigned = 'fas fa-user-check',
                in_progress = 'fas fa-plane',
                completed = 'fas fa-check-circle',
                cancelled = 'fas fa-times-circle'
            }

            table.insert(options, {
                title = string.format('%s → %s',
                    pickup and pickup.label or request.pickup_airport,
                    dest and dest.label or request.destination_airport
                ),
                description = string.format('$%d | %s',
                    request.quoted_price,
                    statusLabels[request.status] or request.status
                ),
                icon = statusIcons[request.status] or 'fas fa-plane',
                metadata = {
                    { label = 'Passengers', value = tostring(request.passenger_count) },
                    { label = 'VIP', value = request.vip_service and 'Yes' or 'No' },
                    { label = 'Status', value = statusLabels[request.status] or request.status }
                },
                onSelect = function()
                    if request.status == 'pending' or request.status == 'quoted' then
                        local confirm = lib.alertDialog({
                            header = 'Cancel Charter?',
                            content = 'Do you want to cancel this charter request?',
                            centered = true,
                            cancel = true
                        })
                        if confirm == 'confirm' then
                            TriggerServerEvent('dps-airlines:server:cancelCharter', request.id, 'Client cancelled')
                            lib.notify({ title = 'Charter', description = 'Request cancelled', type = 'warning' })
                        end
                    end
                end
            })
        end
    end

    -- Add new request button
    table.insert(options, {
        title = 'Request New Charter',
        description = 'Book a private flight',
        icon = 'fas fa-plus-circle',
        onSelect = function()
            OpenPublicCharterMenu()
        end
    })

    lib.registerContext({
        id = 'airlines_my_charters',
        title = 'My Charter Requests',
        options = options
    })

    lib.showContext('airlines_my_charters')
end

-- =====================================
-- CHARTER RATING (For Clients)
-- =====================================

RegisterNetEvent('dps-airlines:client:promptCharterRating', function(charterId)
    Wait(2000) -- Let the completion notification show first

    local input = lib.inputDialog('Rate Your Flight', {
        {
            type = 'slider',
            label = 'Overall Rating',
            min = 1,
            max = 5,
            default = 5
        },
        {
            type = 'textarea',
            label = 'Feedback (optional)',
            placeholder = 'How was your experience?'
        }
    })

    if input then
        TriggerServerEvent('dps-airlines:server:rateCharter', charterId, input[1], input[2])
    end
end)

-- =====================================
-- NOTIFICATIONS
-- =====================================

RegisterNetEvent('dps-airlines:client:newCharterRequest', function(data)
    if OnDuty then
        lib.notify({
            title = 'New Charter Request',
            description = string.format('%s to %s | %d pax | $%d',
                data.from, data.to, data.passengers, data.price
            ),
            type = 'inform',
            duration = 10000
        })
        PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', false)
    end
end)

-- =====================================
-- CLEANUP
-- =====================================

function CancelCharter()
    if ActiveCharter then
        TriggerServerEvent('dps-airlines:server:cancelCharter', ActiveCharter.id, 'Pilot cancelled')
        ActiveCharter = nil
        lib.notify({ title = 'Charter', description = 'Charter returned to pool', type = 'warning' })
    end

    if CharterBlip then
        RemoveBlip(CharterBlip)
        CharterBlip = nil
    end
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        if CharterBlip then
            RemoveBlip(CharterBlip)
        end
    end
end)

-- =====================================
-- EXPORTS & COMMANDS
-- =====================================

exports('GetActiveCharter', function() return ActiveCharter end)
exports('CancelCharter', CancelCharter)
exports('OpenPublicCharterMenu', OpenPublicCharterMenu)
exports('ViewMyCharterStatus', ViewMyCharterStatus)

-- Command for players to request a charter
RegisterCommand('charter', function()
    ViewMyCharterStatus()
end, false)

print('^2[dps-airlines]^7 Charter module loaded')
