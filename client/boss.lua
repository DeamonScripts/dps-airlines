-- Boss Management Client
-- Comprehensive pilot roster and company management
local QBCore = exports['qb-core']:GetCoreObject()

-- =====================================
-- MAIN BOSS MENU
-- =====================================

function OpenBossMenu()
    local data = lib.callback.await('dps-airlines:server:getBossData', false)

    if not data then
        lib.notify({ title = 'Airlines', description = 'Access denied', type = 'error' })
        return
    end

    local options = {
        -- Company Overview
        {
            title = 'Company Balance',
            description = string.format('$%s', FormatNumber(data.balance)),
            icon = 'fas fa-wallet',
            onSelect = function()
                OpenFinanceMenu(data.balance)
            end
        },
        -- Pilot Roster
        {
            title = 'Pilot Roster',
            description = string.format('%d pilots | View stats & flight logs', #data.employees),
            icon = 'fas fa-users',
            onSelect = function()
                OpenPilotRosterMenu(data.employees)
            end
        },
        -- Company Statistics
        {
            title = 'Company Statistics',
            description = 'View detailed performance reports',
            icon = 'fas fa-chart-line',
            onSelect = function()
                OpenCompanyStatsMenu()
            end
        },
        -- Flight Log
        {
            title = 'Company Flight Log',
            description = 'View all pilot flights',
            icon = 'fas fa-book',
            onSelect = function()
                OpenCompanyFlightLogMenu()
            end
        },
        -- Charter Requests
        {
            title = 'Charter Requests',
            description = string.format('%d pending requests', data.pendingCharters),
            icon = 'fas fa-concierge-bell',
            onSelect = function()
                OpenCharterManagementMenu()
            end
        },
        -- Ferry Jobs
        {
            title = 'Ferry Operations',
            description = string.format('%d available jobs', data.availableFerry),
            icon = 'fas fa-truck-plane',
            onSelect = function()
                OpenFerryManagementMenu()
            end
        },
        -- Employee Management
        {
            title = 'Employee Management',
            description = 'Hire, fire, promote employees',
            icon = 'fas fa-user-cog',
            onSelect = function()
                OpenEmployeeManagementMenu()
            end
        }
    }

    -- Weekly stats summary
    if data.weeklyStats then
        table.insert(options, 2, {
            title = 'This Week',
            description = string.format('%d flights | $%s revenue',
                data.weeklyStats.total_flights or 0,
                FormatNumber(data.weeklyStats.total_revenue or 0)
            ),
            icon = 'fas fa-calendar-week',
            disabled = true
        })
    end

    lib.registerContext({
        id = 'airlines_boss_main',
        title = 'DPS Airlines - Management',
        options = options
    })

    lib.showContext('airlines_boss_main')
end

-- =====================================
-- PILOT ROSTER
-- =====================================

function OpenPilotRosterMenu(employees)
    local options = {}

    if #employees == 0 then
        table.insert(options, {
            title = 'No Pilots',
            description = 'Hire some pilots to get started',
            icon = 'fas fa-user-slash',
            disabled = true
        })
    else
        for _, pilot in ipairs(employees) do
            local statusIcon = 'fas fa-circle'
            local statusText = ''

            -- Determine status
            if pilot.daysSinceLastFlight and pilot.daysSinceLastFlight >= 14 then
                statusText = ' (CHECKRIDE DUE)'
            elseif pilot.crashes > 2 then
                statusText = ' (SAFETY REVIEW)'
            end

            table.insert(options, {
                title = pilot.name .. statusText,
                description = string.format('%s | %.1f hrs | %d flights | Rep: %d',
                    pilot.gradeName or 'Pilot',
                    pilot.totalHours or 0,
                    pilot.flights or 0,
                    pilot.reputation or 0
                ),
                icon = 'fas fa-user-tie',
                metadata = {
                    { label = 'Total Hours', value = string.format('%.1f', pilot.totalHours or 0) },
                    { label = 'PIC Hours', value = string.format('%.1f', pilot.picHours or 0) },
                    { label = 'Night Hours', value = string.format('%.1f', pilot.nightHours or 0) },
                    { label = 'Landings', value = tostring(pilot.landings or 0) },
                    { label = 'Crashes', value = tostring(pilot.crashes or 0) },
                    { label = 'License', value = (pilot.licenseType or 'student'):upper() }
                },
                onSelect = function()
                    OpenPilotDetailMenu(pilot.citizenid, pilot.name)
                end
            })
        end
    end

    lib.registerContext({
        id = 'airlines_pilot_roster',
        title = 'Pilot Roster',
        menu = 'airlines_boss_main',
        options = options
    })

    lib.showContext('airlines_pilot_roster')
end

function OpenPilotDetailMenu(citizenid, name)
    local details = lib.callback.await('dps-airlines:server:getPilotDetails', false, citizenid)

    if not details then
        lib.notify({ title = 'Error', description = 'Could not load pilot details', type = 'error' })
        return
    end

    local stats = details.stats
    local options = {
        -- Overview
        {
            title = 'Career Overview',
            description = string.format('License: %s | Rep: %d',
                (stats.license_type or 'student'):upper(),
                stats.reputation or 0
            ),
            icon = 'fas fa-id-card',
            disabled = true
        },
        -- Flight Hours Breakdown
        {
            title = 'Flight Hours',
            icon = 'fas fa-clock',
            disabled = true,
            metadata = {
                { label = 'Total', value = string.format('%.1f hrs', stats.total_hours or 0) },
                { label = 'PIC', value = string.format('%.1f hrs', stats.pic_hours or 0) },
                { label = 'Night', value = string.format('%.1f hrs', stats.night_hours or 0) },
                { label = 'IFR', value = string.format('%.1f hrs', stats.ifr_hours or 0) },
                { label = 'Cross-Country', value = string.format('%.1f hrs', stats.cross_country_hours or 0) }
            }
        },
        -- Job Type Hours
        {
            title = 'Hours by Type',
            icon = 'fas fa-chart-pie',
            disabled = true,
            metadata = {
                { label = 'Passenger', value = string.format('%.1f hrs', stats.passenger_hours or 0) },
                { label = 'Cargo', value = string.format('%.1f hrs', stats.cargo_hours or 0) },
                { label = 'Charter', value = string.format('%.1f hrs', stats.charter_hours or 0) },
                { label = 'Ferry', value = string.format('%.1f hrs', stats.ferry_hours or 0) }
            }
        },
        -- Landings
        {
            title = 'Landings',
            description = string.format('%d day | %d night | %d hard',
                stats.day_landings or 0,
                stats.night_landings or 0,
                stats.hard_landings or 0
            ),
            icon = 'fas fa-plane-arrival',
            disabled = true
        },
        -- Safety Record
        {
            title = 'Safety Record',
            description = string.format('%d crashes | %d incidents',
                stats.crashes or 0,
                stats.incidents or 0
            ),
            icon = stats.crashes > 0 and 'fas fa-exclamation-triangle' or 'fas fa-shield-alt',
            disabled = true
        },
        -- Type Ratings
        {
            title = 'Type Ratings',
            description = #details.typeRatings > 0
                and table.concat(details.typeRatings, ', ')
                or 'No type ratings',
            icon = 'fas fa-certificate',
            disabled = true
        },
        -- Earnings
        {
            title = 'Total Earnings',
            description = string.format('$%s', FormatNumber(stats.total_earnings or 0)),
            icon = 'fas fa-dollar-sign',
            disabled = true
        },
        -- View Flight Log
        {
            title = 'View Flight Log',
            description = 'Recent flights for this pilot',
            icon = 'fas fa-list',
            onSelect = function()
                OpenPilotFlightLog(citizenid, name)
            end
        }
    }

    lib.registerContext({
        id = 'airlines_pilot_detail',
        title = name,
        menu = 'airlines_pilot_roster',
        options = options
    })

    lib.showContext('airlines_pilot_detail')
end

function OpenPilotFlightLog(citizenid, name)
    local logbook = lib.callback.await('dps-airlines:server:getPilotLogbook', false, citizenid, 20, 0)

    local options = {}

    if #logbook == 0 then
        table.insert(options, {
            title = 'No Flights Recorded',
            icon = 'fas fa-plane-slash',
            disabled = true
        })
    else
        for _, entry in ipairs(logbook) do
            local fromAirport = Locations.Airports[entry.departure_airport]
            local toAirport = Locations.Airports[entry.arrival_airport]

            table.insert(options, {
                title = string.format('%s → %s',
                    fromAirport and fromAirport.label or entry.departure_airport,
                    toAirport and toAirport.label or entry.arrival_airport
                ),
                description = string.format('%s | %.1f hrs | $%d',
                    entry.flight_type:upper(),
                    entry.flight_time or 0,
                    entry.payment or 0
                ),
                icon = 'fas fa-plane',
                metadata = {
                    { label = 'Aircraft', value = entry.aircraft_model },
                    { label = 'Flight Time', value = string.format('%.1f hrs', entry.flight_time or 0) },
                    { label = 'Conditions', value = string.format('%s / %s', entry.day_night or 'day', entry.ifr_vfr or 'vfr') },
                    { label = 'Landing', value = entry.landing_quality or 'normal' },
                    { label = 'Status', value = entry.status or 'completed' }
                }
            })
        end
    end

    lib.registerContext({
        id = 'airlines_pilot_log',
        title = name .. ' - Flight Log',
        menu = 'airlines_pilot_detail',
        options = options
    })

    lib.showContext('airlines_pilot_log')
end

-- =====================================
-- COMPANY STATISTICS
-- =====================================

function OpenCompanyStatsMenu()
    local options = {
        {
            title = 'Weekly Report',
            description = 'Last 7 days performance',
            icon = 'fas fa-calendar-week',
            onSelect = function()
                ShowCompanyStats('week')
            end
        },
        {
            title = 'Monthly Report',
            description = 'Last 30 days performance',
            icon = 'fas fa-calendar-alt',
            onSelect = function()
                ShowCompanyStats('month')
            end
        },
        {
            title = 'Yearly Report',
            description = 'Last 365 days performance',
            icon = 'fas fa-calendar',
            onSelect = function()
                ShowCompanyStats('year')
            end
        }
    }

    lib.registerContext({
        id = 'airlines_company_stats_menu',
        title = 'Company Statistics',
        menu = 'airlines_boss_main',
        options = options
    })

    lib.showContext('airlines_company_stats_menu')
end

function ShowCompanyStats(period)
    local stats = lib.callback.await('dps-airlines:server:getCompanyStats', false, period)

    if not stats then return end

    local periodLabel = period == 'week' and '7 Days' or (period == 'month' and '30 Days' or '365 Days')

    local options = {
        -- Overview
        {
            title = 'Performance Summary',
            description = string.format('%d flights | %.1f hours | $%s',
                stats.overall.total_flights or 0,
                stats.overall.total_hours or 0,
                FormatNumber(stats.overall.total_revenue or 0)
            ),
            icon = 'fas fa-chart-bar',
            disabled = true
        },
        -- By Flight Type
        {
            title = 'By Flight Type',
            icon = 'fas fa-tags',
            disabled = true
        }
    }

    for _, typeStats in ipairs(stats.byType or {}) do
        table.insert(options, {
            title = '  ' .. typeStats.flight_type:upper(),
            description = string.format('%d flights | %.1f hrs | $%s',
                typeStats.flights,
                typeStats.hours or 0,
                FormatNumber(typeStats.revenue or 0)
            ),
            disabled = true
        })
    end

    -- Top Pilots
    table.insert(options, {
        title = 'Top Pilots',
        icon = 'fas fa-trophy',
        disabled = true
    })

    for i, pilot in ipairs(stats.topPilots or {}) do
        table.insert(options, {
            title = string.format('  #%d %s', i, pilot.name or 'Unknown'),
            description = string.format('%.1f hrs | $%s',
                pilot.hours or 0,
                FormatNumber(pilot.earnings or 0)
            ),
            disabled = true
        })
    end

    -- Safety
    table.insert(options, {
        title = 'Safety Report',
        description = string.format('%d crashes | %d hard landings',
            stats.safety.crashes or 0,
            stats.safety.hard_landings or 0
        ),
        icon = 'fas fa-shield-alt',
        disabled = true
    })

    lib.registerContext({
        id = 'airlines_company_stats_detail',
        title = 'Report - Last ' .. periodLabel,
        menu = 'airlines_company_stats_menu',
        options = options
    })

    lib.showContext('airlines_company_stats_detail')
end

-- =====================================
-- COMPANY FLIGHT LOG
-- =====================================

function OpenCompanyFlightLogMenu()
    local options = {
        {
            title = 'All Flights (7 days)',
            icon = 'fas fa-list',
            onSelect = function()
                ShowCompanyFlightLog({ days = 7 })
            end
        },
        {
            title = 'Passenger Flights',
            icon = 'fas fa-users',
            onSelect = function()
                ShowCompanyFlightLog({ flightType = 'passenger', days = 30 })
            end
        },
        {
            title = 'Cargo Flights',
            icon = 'fas fa-boxes',
            onSelect = function()
                ShowCompanyFlightLog({ flightType = 'cargo', days = 30 })
            end
        },
        {
            title = 'Charter Flights',
            icon = 'fas fa-user-tie',
            onSelect = function()
                ShowCompanyFlightLog({ flightType = 'charter', days = 30 })
            end
        },
        {
            title = 'Ferry Flights',
            icon = 'fas fa-truck-plane',
            onSelect = function()
                ShowCompanyFlightLog({ flightType = 'ferry', days = 30 })
            end
        }
    }

    lib.registerContext({
        id = 'airlines_flight_log_menu',
        title = 'Company Flight Log',
        menu = 'airlines_boss_main',
        options = options
    })

    lib.showContext('airlines_flight_log_menu')
end

function ShowCompanyFlightLog(filters)
    local flights = lib.callback.await('dps-airlines:server:getCompanyFlightLog', false, filters)

    local options = {}

    if #flights == 0 then
        table.insert(options, {
            title = 'No Flights Found',
            icon = 'fas fa-plane-slash',
            disabled = true
        })
    else
        for _, flight in ipairs(flights) do
            local fromAirport = Locations.Airports[flight.departure_airport]
            local toAirport = Locations.Airports[flight.arrival_airport]

            table.insert(options, {
                title = string.format('%s → %s',
                    fromAirport and fromAirport.label or flight.departure_airport,
                    toAirport and toAirport.label or flight.arrival_airport
                ),
                description = string.format('%s | %s | %.1f hrs | $%d',
                    flight.pilotName or 'Unknown',
                    flight.flight_type:upper(),
                    flight.flight_time or 0,
                    flight.payment or 0
                ),
                icon = 'fas fa-plane',
                metadata = {
                    { label = 'Pilot', value = flight.pilotName or 'Unknown' },
                    { label = 'Aircraft', value = flight.aircraft_model },
                    { label = 'Status', value = flight.status or 'completed' }
                }
            })
        end
    end

    lib.registerContext({
        id = 'airlines_flight_log_detail',
        title = 'Flight Log',
        menu = 'airlines_flight_log_menu',
        options = options
    })

    lib.showContext('airlines_flight_log_detail')
end

-- =====================================
-- FINANCE MENU
-- =====================================

function OpenFinanceMenu(balance)
    local options = {
        {
            title = 'Current Balance',
            description = string.format('$%s', FormatNumber(balance)),
            icon = 'fas fa-wallet',
            disabled = true
        },
        {
            title = 'Withdraw',
            description = 'Withdraw from company funds',
            icon = 'fas fa-money-bill-wave',
            onSelect = function()
                local input = lib.inputDialog('Withdraw Funds', {
                    { type = 'number', label = 'Amount', min = 1, max = balance }
                })
                if input and input[1] then
                    TriggerServerEvent('dps-airlines:server:withdrawSociety', input[1])
                end
            end
        },
        {
            title = 'Deposit',
            description = 'Deposit to company funds',
            icon = 'fas fa-piggy-bank',
            onSelect = function()
                local input = lib.inputDialog('Deposit Funds', {
                    { type = 'number', label = 'Amount', min = 1 }
                })
                if input and input[1] then
                    TriggerServerEvent('dps-airlines:server:depositSociety', input[1])
                end
            end
        }
    }

    lib.registerContext({
        id = 'airlines_finance_menu',
        title = 'Company Finances',
        menu = 'airlines_boss_main',
        options = options
    })

    lib.showContext('airlines_finance_menu')
end

-- =====================================
-- CHARTER MANAGEMENT
-- =====================================

function OpenCharterManagementMenu()
    local charters = lib.callback.await('dps-airlines:server:getAllCharters', false, nil)

    local options = {
        {
            title = 'Pending Requests',
            icon = 'fas fa-clock',
            onSelect = function()
                ShowCharters('pending')
            end
        },
        {
            title = 'Active Charters',
            icon = 'fas fa-plane-departure',
            onSelect = function()
                ShowCharters('in_progress')
            end
        },
        {
            title = 'Completed Charters',
            icon = 'fas fa-check-circle',
            onSelect = function()
                ShowCharters('completed')
            end
        }
    }

    lib.registerContext({
        id = 'airlines_charter_mgmt',
        title = 'Charter Management',
        menu = 'airlines_boss_main',
        options = options
    })

    lib.showContext('airlines_charter_mgmt')
end

function ShowCharters(statusFilter)
    local charters = lib.callback.await('dps-airlines:server:getAllCharters', false, statusFilter)

    local options = {}

    if #charters == 0 then
        table.insert(options, {
            title = 'No Charters Found',
            disabled = true
        })
    else
        for _, charter in ipairs(charters) do
            table.insert(options, {
                title = string.format('%s → %s',
                    charter.pickup_airport,
                    charter.destination_airport
                ),
                description = string.format('%s | %d pax | $%d',
                    charter.client_name or 'Unknown',
                    charter.passenger_count,
                    charter.quoted_price or 0
                ),
                metadata = {
                    { label = 'Client', value = charter.client_name or 'Unknown' },
                    { label = 'Pilot', value = charter.pilotName or 'Unassigned' },
                    { label = 'VIP', value = charter.vip_service and 'Yes' or 'No' },
                    { label = 'Status', value = charter.status:upper() }
                }
            })
        end
    end

    lib.registerContext({
        id = 'airlines_charter_list',
        title = 'Charters - ' .. statusFilter:upper(),
        menu = 'airlines_charter_mgmt',
        options = options
    })

    lib.showContext('airlines_charter_list')
end

-- =====================================
-- FERRY MANAGEMENT
-- =====================================

function OpenFerryManagementMenu()
    local options = {
        {
            title = 'View Available Jobs',
            icon = 'fas fa-list',
            onSelect = function()
                OpenFerryJobsMenu()
            end
        },
        {
            title = 'Create Ferry Job',
            description = 'Manually create a ferry job',
            icon = 'fas fa-plus',
            onSelect = function()
                CreateFerryJobDialog()
            end
        }
    }

    lib.registerContext({
        id = 'airlines_ferry_mgmt',
        title = 'Ferry Operations',
        menu = 'airlines_boss_main',
        options = options
    })

    lib.showContext('airlines_ferry_mgmt')
end

function CreateFerryJobDialog()
    local airportOptions = {}
    for name, airport in pairs(Locations.Airports) do
        table.insert(airportOptions, { value = name, label = airport.label })
    end

    local planeOptions = {}
    for model, data in pairs(Config.Planes) do
        table.insert(planeOptions, { value = model, label = data.label })
    end

    local input = lib.inputDialog('Create Ferry Job', {
        { type = 'select', label = 'From Airport', options = airportOptions, required = true },
        { type = 'select', label = 'To Airport', options = airportOptions, required = true },
        { type = 'select', label = 'Aircraft', options = planeOptions, required = true },
        { type = 'number', label = 'Payment ($)', min = 100, default = 500, required = true },
        { type = 'select', label = 'Priority', options = {
            { value = 'low', label = 'Low' },
            { value = 'normal', label = 'Normal' },
            { value = 'high', label = 'High' },
            { value = 'urgent', label = 'Urgent' }
        }, default = 'normal' }
    })

    if input then
        TriggerServerEvent('dps-airlines:server:createFerryJob', {
            from = input[1],
            to = input[2],
            aircraft = input[3],
            payment = input[4],
            priority = input[5],
            reason = 'reposition'
        })
    end
end

-- =====================================
-- EMPLOYEE MANAGEMENT
-- =====================================

function OpenEmployeeManagementMenu()
    local options = {
        {
            title = 'Hire Nearby Player',
            description = 'Hire a player within 5m',
            icon = 'fas fa-user-plus',
            onSelect = function()
                HireNearbyPlayer()
            end
        }
    }

    lib.registerContext({
        id = 'airlines_employee_mgmt',
        title = 'Employee Management',
        menu = 'airlines_boss_main',
        options = options
    })

    lib.showContext('airlines_employee_mgmt')
end

function HireNearbyPlayer()
    local players = lib.getNearbyPlayers(GetEntityCoords(PlayerPedId()), 5.0, false)

    if #players == 0 then
        lib.notify({ title = 'Airlines', description = 'No players nearby', type = 'error' })
        return
    end

    local options = {}
    for _, player in ipairs(players) do
        local serverId = GetPlayerServerId(player.id)
        table.insert(options, {
            title = 'Player ID: ' .. serverId,
            onSelect = function()
                TriggerServerEvent('dps-airlines:server:hireEmployee', serverId)
            end
        })
    end

    lib.registerContext({
        id = 'airlines_hire_menu',
        title = 'Hire Employee',
        menu = 'airlines_employee_mgmt',
        options = options
    })

    lib.showContext('airlines_hire_menu')
end

-- =====================================
-- UTILITY
-- =====================================

function FormatNumber(n)
    local formatted = tostring(math.floor(n))
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then break end
    end
    return formatted
end

-- =====================================
-- EXPORTS
-- =====================================

exports('OpenBossMenu', OpenBossMenu)
