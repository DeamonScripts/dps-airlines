# DPS Airlines

A comprehensive airlines job system for FiveM servers with realistic pilot career progression.

**Version:** 3.0.0
**Framework:** QB-Core / QBX / ESX (auto-detected)

## Features

### Core Systems
- **Passenger Flights** - Transport NPC passengers between airports
- **Cargo Transport** - Haul freight with weight-based payouts
- **Private Charters** - VIP transport services for players
- **Ferry Flights** - Aircraft repositioning jobs

### Career Progression
- **Flight School** - 3-lesson training program for pilot certification
- **Pilot Logbook NUI** - Visual flight history and statistics
- **Type Ratings** - Aircraft certifications per model
- **Reputation System** - Build rep for better planes and assignments
- **Checkride System** - Recurrent training for inactive pilots

### Operations
- **Aircraft Maintenance** - Service and repair company aircraft
- **Boss Menu** - Manage employees, view finances, hire/fire pilots
- **Dispatch System** - Available jobs board with priority assignments
- **ATC Clearance** - Realistic flight plan approval system
- **Weather Delays** - Dynamic weather impacts on flight operations
- **Emergency Scenarios** - Engine fires, gear failures, bird strikes

### Technical Features
- **Black Box Recorder** - Flight telemetry and crash analysis
- **State Bag Weather Sync** - Server-synced weather via GlobalState
- **Altitude-Based Throttling** - CPU optimization during cruise
- **Multi-Framework Bridge** - QB-Core, QBX, and ESX support

## Requirements

- [ox_lib](https://github.com/overextended/ox_lib)
- [ox_target](https://github.com/overextended/ox_target)
- [oxmysql](https://github.com/overextended/oxmysql)
- One of: qb-core, qbx_core, or es_extended

## Installation

1. Download and extract to your resources folder:
   ```
   resources/[standalone]/[dps]/dps-airlines/
   ```

2. Run `sql/install.sql` in your database

3. Add the pilot job to your framework:

   **QBCore/QBX** (`qb-core/shared/jobs.lua`):
   ```lua
   ['pilot'] = {
       label = 'Los Santos Airlines',
       type = 'transportation',
       defaultDuty = false,
       offDutyPay = false,
       grades = {
           ['0'] = { name = 'Trainee', payment = 50 },
           ['1'] = { name = 'Pilot', payment = 75 },
           ['2'] = { name = 'Chief Pilot', isboss = true, payment = 150 },
       },
   },
   ```

   **ESX** (database):
   ```sql
   INSERT INTO jobs (name, label) VALUES ('pilot', 'Los Santos Airlines');
   INSERT INTO job_grades (job_name, grade, name, label, salary) VALUES
     ('pilot', 0, 'trainee', 'Trainee', 50),
     ('pilot', 1, 'pilot', 'Pilot', 75),
     ('pilot', 2, 'chief', 'Chief Pilot', 150);
   ```

4. Add `pilots_license` item to your inventory:

   **ox_inventory** (`ox_inventory/data/items.lua`):
   ```lua
   ['pilots_license'] = {
       label = 'Pilot License',
       weight = 10,
       stack = false,
       description = 'FAA Commercial Pilot License'
   },
   ```

5. Add to your `server.cfg`:
   ```cfg
   ensure dps-airlines
   ```

## Airports

| Airport | Type | Available Planes |
|---------|------|------------------|
| Los Santos International (LSIA) | Hub/International | All |
| Sandy Shores Airfield | Regional | Luxor, Shamal |
| Grapeseed Airstrip | Rural | Luxor only |
| Fort Zancudo | Military (Restricted) | All |
| Roxwood International | International | All |
| Paleto Regional | Regional | Luxor, Shamal, Nimbus |

## Aircraft

| Model | Category | Passengers | Cargo | Reputation Required |
|-------|----------|------------|-------|---------------------|
| Luxor | Small | 4 | 500kg | 0 |
| Shamal | Medium | 8 | 1000kg | 30 |
| Nimbus | Large | 12 | 2000kg | 60 |
| Miljet | Executive | 16 | 3000kg | 100 |

## Configuration

### Main Config (`shared/config.lua`)

```lua
Config = {}

Config.Debug = false
Config.UseTarget = true
Config.Job = 'pilot'
Config.BossGrade = 2

-- Economy
Config.PaymentAccount = 'bank'
Config.UseSocietyFunds = true

-- Weather
Config.Weather = {
    enabled = true,
    checkInterval = 60000,
    groundedWeather = { 'THUNDER' },
    delays = {
        ['RAIN'] = { chance = 30, delayMinutes = 15, payBonus = 1.2 },
        ['THUNDER'] = { chance = 60, delayMinutes = 30, payBonus = 1.5 },
    }
}

-- Maintenance
Config.Maintenance = {
    enabled = true,
    flightsBeforeService = 10,
    breakdownChance = 5,
}

-- Flight School
Config.FlightSchool = {
    enabled = true,
    licenseCost = 2500,
    requiredLessons = 3,
}

-- Emergency Scenarios
Config.Emergencies = {
    enabled = true,
    multiplier = 1.0,
    minAltitude = 100,
}
```

### Locations (`shared/locations.lua`)

Configure airport coordinates, spawn points, runways, gates, and NPC positions.

## Database Tables

The SQL script creates these tables:
- `airline_flights` - Flight records
- `airline_pilot_stats` - Pilot statistics and hours
- `airline_pilot_logbook` - Detailed flight log
- `airline_ferry_jobs` - Aircraft repositioning jobs
- `airline_charter_requests` - Player charter requests
- `airline_maintenance` - Aircraft service records
- `airline_charters` - Active charter bookings
- `airline_dispatch` - Available flight jobs
- `airline_blackbox` - Flight recorder data
- `airline_crashes` - Crash records
- `airline_checkrides` - Training records
- `airline_incidents` - Emergency events

## Admin Commands

| Command | Permission | Description |
|---------|------------|-------------|
| `/setpilotgrade [id] [grade]` | admin | Set pilot job grade |
| `/resetpilotstats [id]` | admin | Reset pilot statistics |

## Exports

### Server Exports

```lua
-- Get weather state
local weather = exports['dps-airlines']:GetWeatherState()
-- Returns: { weather, canFly, delayMinutes, payBonus, lastUpdate }

-- Create logbook entry (internal use)
exports['dps-airlines']:CreateLogbookEntry(identifier, logbookData)
```

### Client Exports

```lua
-- Check duty status
local onDuty = exports['dps-airlines']:IsOnDuty()

-- Get current flight
local flight = exports['dps-airlines']:GetCurrentFlight()

-- Get current plane entity
local plane = exports['dps-airlines']:GetCurrentPlane()

-- ATC Functions
exports['dps-airlines']:RequestClearance(runway)
exports['dps-airlines']:LandingClearance(airport)
exports['dps-airlines']:ResetClearance()

-- Weather
local conditions = exports['dps-airlines']:CheckWeatherConditions()
local canFly, bonus = exports['dps-airlines']:ApplyWeatherDelay()
local weather = exports['dps-airlines']:GetCachedWeather()

-- Flight Phase
local phase = exports['dps-airlines']:GetFlightPhase()
local hasClearance = exports['dps-airlines']:HasClearance()
local callsign = exports['dps-airlines']:GetCallsign()

-- Black Box
exports['dps-airlines']:StartBlackBox(flightNumber)
exports['dps-airlines']:StopBlackBox(reason)
exports['dps-airlines']:RecordBlackBoxEvent(eventType, data)
exports['dps-airlines']:RecordEmergency(emergencyType, details)
exports['dps-airlines']:IsRecording()
```

## Framework Support

### Automatic Detection
The bridge automatically detects your framework:
- QBX (`qbx_core`)
- QBCore (`qb-core`)
- ESX (`es_extended`)

### Inventory Support
Automatic detection for:
- ox_inventory
- qs-inventory
- qb-inventory (native)
- ESX inventory

### Society Funds
Automatic detection for:
- qb-management
- qb-banking
- esx_addonaccount

### Weather Sync
Automatic detection for:
- qb-weathersync
- cd_easytime
- vSync GlobalState

## Flight School System

1. Players interact with Flight Instructor NPC
2. Complete 3 training lessons:
   - Takeoff & Landing
   - Navigation
   - Emergency Procedures
3. Purchase pilot license ($2,500)
4. License item added to inventory

## Emergency Scenarios

Random in-flight emergencies with reputation consequences:
- Engine Fire (+10/-25 rep)
- Gear Failure (+8/-15 rep)
- Fuel Leak (+8/-20 rep)
- Electrical Failure (+5/-10 rep)
- Hydraulic Failure (+7/-15 rep)
- Bird Strike (+3/-5 rep)

## Pilot Logbook NUI

Interactive web-based logbook with:
- Overview tab: Hours, landings, license, earnings
- Flight Log tab: Filterable flight history
- Type Ratings tab: Aircraft certifications
- Incidents tab: Safety record

Access via `/logbook` or configured keybind.

## Performance

- State bag weather sync (no client polling)
- Altitude-based loop throttling
- Batched database operations
- Configurable spawn delays
- Memory cleanup for blackbox records

## Troubleshooting

**Players can't clock in?**
- Verify job is configured in framework
- Check `Config.Job` matches job name

**License not given?**
- Check inventory resource is running
- Verify `pilots_license` item exists

**Weather not syncing?**
- Check weather resource is running
- Enable `Config.Debug` for state bag logs

**Planes not spawning?**
- Check spawn points in `locations.lua`
- Verify ox_target is working

## Changelog

### v3.0.0
- Multi-framework support (QB/QBX/ESX)
- Bridge architecture for abstraction
- Removed qb-core hard dependency
- Inventory abstraction (ox/qs/qb/esx)
- Society funds abstraction
- Weather system abstraction
- Improved State Bag usage

### v2.2.0
- Pilot Logbook NUI
- Emergency Scenarios
- Black Box recorder

### v2.1.0
- Ferry flights
- Charter system
- Realistic pilot stats

### v2.0.0
- Performance optimizations
- Advanced features

### v1.0.0
- Initial release

## License

This resource is provided for use on DPSRP servers. Free to modify for your own use.

## Credits

- DaemonAlex
- DPSRP Development Team
- Overextended (ox_lib, ox_target, oxmysql)
- QBCore/ESX Framework Teams
