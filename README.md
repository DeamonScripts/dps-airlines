# DPS Airlines

**The most immersive pilot career system for FiveM.**

Transform your server's aviation into a full roleplay experience. Players don't just fly planes - they build careers as commercial pilots with training, certifications, flight logs, and real consequences.

---

## What Players Experience

### Start as a Trainee Pilot
New pilots begin at **Flight School** where they complete hands-on training:
- **Takeoff & Landing** - Master the basics at LSIA
- **Navigation** - Learn to fly waypoint routes between airports
- **Emergency Procedures** - Handle engine failures and emergency landings

Pass all three lessons and purchase your **Pilot License** ($2,500) to join the airline.

### Build Your Career
Every flight matters. The system tracks:
- **Total Flight Hours** - Just like real pilots, hours = experience
- **PIC Hours** - Pilot in Command time
- **Night Flying Hours** - Flights after dark
- **IFR Hours** - Instrument conditions flying

Your **reputation score** unlocks better aircraft. Start in a small Luxor, work your way up to the executive Miljet.

### The Pilot Logbook
A beautiful in-game logbook (NUI) shows your complete career:
- Flight history with routes, times, and earnings
- Type ratings for each aircraft you're certified on
- Safety record including any incidents
- Career statistics and achievements

### Real Consequences
This isn't arcade flying. Pilots face:
- **Weather Delays** - Thunderstorms ground flights, rain causes delays
- **Maintenance Requirements** - Aircraft need servicing every 10 flights
- **Emergency Scenarios** - Random engine fires, gear failures, bird strikes
- **Crash Records** - Your safety record follows you

Handle emergencies well? Gain reputation. Crash? It goes on your permanent record.

---

## Flight Types

### Passenger Flights
Transport NPC passengers between airports. Watch them board, fly them safely, earn per-passenger bonuses. The Miljet holds 16 passengers for maximum payouts.

### Cargo Runs
Haul freight across San Andreas:
- **Mail & Packages** - Standard pay
- **Medical Supplies** - 1.5x pay multiplier
- **General Freight** - High volume, lower rate
- **Valuables** - 2.5x pay, high responsibility

### Private Charters
Real players can request charter flights! A customer books a flight, you get dispatched to pick them up and fly them to their destination. True pilot-passenger roleplay.

### Ferry Flights
Reposition aircraft between airports. Sometimes a plane needs to be somewhere else - you're the one to move it. Simple flights, decent pay.

---

## The Dispatch System

No wandering around wondering what to do. The **Dispatch Board** shows available flights:
- Priority levels (Urgent pays 1.5x)
- Route and distance
- Required aircraft type
- Passenger/cargo counts
- Expiring assignments

Accept a job, spawn your aircraft, request ATC clearance, and fly.

---

## Air Traffic Control

Before takeoff, pilots must:
1. Select their runway
2. Request clearance from ATC
3. Wait for approval (5-15 seconds, simulating radio comms)
4. Receive their callsign (e.g., "DPS-742, cleared for takeoff")

It's a small touch that makes every departure feel real.

---

## Weather System

Weather affects operations server-wide (synced via State Bags):

| Condition | Effect |
|-----------|--------|
| Clear | Normal operations |
| Rain | 30% chance of 15-min delay, 1.2x pay bonus |
| Fog | 20% chance of 10-min delay, 1.1x pay bonus |
| Snow | 40% chance of 20-min delay, 1.3x pay bonus |
| Thunder | **All flights grounded** |

Pilots who fly in bad weather earn bonuses for the risk.

---

## Aircraft Fleet

| Aircraft | Size | Passengers | Cargo | Unlock At |
|----------|------|------------|-------|-----------|
| **Luxor** | Small | 4 | 500kg | 0 rep |
| **Shamal** | Medium | 8 | 1,000kg | 30 rep |
| **Nimbus** | Large | 12 | 2,000kg | 60 rep |
| **Miljet** | Executive | 16 | 3,000kg | 100 rep |

Each aircraft has different fuel consumption and base pay rates.

---

## Airports

| Location | Type | Notes |
|----------|------|-------|
| **Los Santos International** | Hub | All aircraft, main base |
| **Sandy Shores Airfield** | Regional | Small/medium planes only |
| **Grapeseed Airstrip** | Rural | Luxor only (short runway) |
| **Fort Zancudo** | Military | Restricted access |
| **Roxwood International** | International | Full service |
| **Paleto Regional** | Regional | No executive jets |

---

## For Server Owners

### Why Add This?

**Player Retention** - The career progression keeps pilots coming back. They want to hit 100 hours, unlock the Miljet, build their logbook.

**Passive Economy** - Pilots earn money flying, creating economic activity without admin intervention. Society funds integration means the airline pays from its own account.

**Roleplay Depth** - Charter flights create pilot-passenger interactions. Emergency scenarios create dramatic moments. The logbook gives pilots an identity.

**Low Maintenance** - Once configured, it runs itself. Dispatch jobs generate automatically, maintenance happens naturally, weather syncs from your weather script.

### Framework Support

Works with your existing setup - no migrations needed:
- **QBCore** / **QBX** / **ESX** (auto-detected)
- **ox_inventory** / **qs-inventory** / **qb-inventory**
- **qb-management** / **qb-banking** / **esx_addonaccount**
- **qb-weathersync** / **cd_easytime** / **vSync**

### Performance

Built for busy servers:
- State Bag weather sync (no client polling)
- Altitude-based loop throttling (less CPU at cruise)
- Memory-managed flight recorder
- Efficient database queries

---

## Quick Start

1. Drop in `resources/[jobs]/dps-airlines`
2. Run `sql/install.sql`
3. Add the `pilot` job to your framework
4. Add `pilots_license` item to your inventory
5. `ensure dps-airlines`

Full installation details below.

---

## Installation

### Database
```sql
-- Run sql/install.sql in your database
-- Creates 12 tables for flights, stats, logbook, etc.
```

### Job Setup

**QBCore/QBX** - Add to `qb-core/shared/jobs.lua`:
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

**ESX** - Run in database:
```sql
INSERT INTO jobs (name, label) VALUES ('pilot', 'Los Santos Airlines');
INSERT INTO job_grades (job_name, grade, name, label, salary) VALUES
  ('pilot', 0, 'trainee', 'Trainee', 50),
  ('pilot', 1, 'pilot', 'Pilot', 75),
  ('pilot', 2, 'chief', 'Chief Pilot', 150);
```

### License Item

**ox_inventory** - Add to `data/items.lua`:
```lua
['pilots_license'] = {
    label = 'Pilot License',
    weight = 10,
    stack = false,
    description = 'FAA Commercial Pilot License'
},
```

---

## Configuration

All settings in `shared/config.lua`:

```lua
Config.Job = 'pilot'           -- Job name
Config.BossGrade = 2           -- Grade needed for boss menu
Config.PaymentAccount = 'bank' -- Where pilots get paid
Config.UseSocietyFunds = true  -- Pay from company account

-- Flight School
Config.FlightSchool.licenseCost = 2500
Config.FlightSchool.requiredLessons = 3

-- Maintenance
Config.Maintenance.flightsBeforeService = 10
Config.Maintenance.breakdownChance = 5  -- % per flight when overdue

-- Emergencies
Config.Emergencies.enabled = true
Config.Emergencies.multiplier = 1.0  -- Adjust frequency
```

Airport locations configured in `shared/locations.lua`.

---

## Admin Commands

| Command | Description |
|---------|-------------|
| `/setpilotgrade [id] [0-2]` | Set player's pilot rank |
| `/resetpilotstats [id]` | Wipe player's flight history |

---

## Dependencies

**Required:**
- [ox_lib](https://github.com/overextended/ox_lib)
- [ox_target](https://github.com/overextended/ox_target)
- [oxmysql](https://github.com/overextended/oxmysql)

**Framework (one of):**
- qb-core / qbx_core / es_extended

---

## Version History

**v3.0.0** - Multi-framework support (QB/QBX/ESX), bridge architecture
**v2.2.0** - Pilot Logbook NUI, emergency scenarios, black box recorder
**v2.1.0** - Ferry flights, charter system, realistic pilot stats
**v2.0.0** - Performance optimizations, advanced features
**v1.0.0** - Initial release

---

## Credits

- **DaemonAlex** - Original concept and development
- **DPSRP Development Team**
- Overextended (ox_lib, ox_target, oxmysql)

---

*DPS Airlines - Where every flight tells a story.*
