Locations = {}

-- Main Hub (Los Santos International)
Locations.Hub = {
    name = 'LSIA',
    label = 'Los Santos International Airport',
    coords = vector4(-1037.67, -2963.63, 13.95, 330.0),

    -- Clock in/out and job menu
    jobMenu = vector4(-1037.67, -2963.63, 13.95, 330.0),

    -- Plane spawn points (multiple to avoid collision)
    planeSpawns = {
        vector4(-960.34, -2933.75, 13.95, 148.94),
        vector4(-998.45, -2881.23, 13.95, 148.94),
        vector4(-1032.15, -2848.67, 13.95, 148.94),
    },

    -- Runways for takeoff
    runways = {
        { label = 'Runway 03', coords = vector4(-1630.58, -2721.92, 13.94, 329.76) },
        { label = 'Runway 12L', coords = vector4(-1547.32, -2827.42, 13.98, 239.25) },
        { label = 'Runway 12R', coords = vector4(-1620.11, -2979.68, 13.94, 236.86) },
    },

    -- Taxiway gates for boarding/deplaning
    gates = {
        vector4(-1155.93, -2922.1, 13.95, 323.56),
        vector4(-1230.38, -2877.72, 13.95, 326.8),
        vector4(-1272.81, -2862.23, 13.95, 314.29),
    },

    -- Fueling location
    fuel = vector4(-978.8, -2890.05, 13.95, 144.28),

    -- Maintenance hangar
    maintenance = vector4(-1024.56, -2891.34, 13.95, 150.0),

    -- Passenger terminal (NPC spawn)
    terminal = vector4(-1034.89, -2732.98, 20.17, 240.0),

    -- Cargo loading area
    cargo = vector4(-1089.45, -2915.67, 13.95, 330.0),

    -- Flight school location
    flightSchool = vector4(-1143.45, -2698.12, 13.95, 330.0),

    -- Boss office
    bossOffice = vector4(-1145.67, -2694.34, 13.95, 60.0),
}

-- Destination Airports
Locations.Airports = {
    ['sandy'] = {
        name = 'sandy',
        label = 'Sandy Shores Airfield',
        coords = vector4(1482.13, 3154.87, 41.24, 289.67),
        landing = vector4(1735.72, 3294.28, 41.16, 10.65),
        fuel = vector4(1683.37, 3269.24, 40.76, 242.55),
        terminal = vector4(1735.72, 3294.28, 41.16, 10.65),
        cargo = vector4(1680.0, 3280.0, 40.76, 240.0),
        distance = 8.5, -- km from hub
        type = 'regional',
        availablePlanes = { 'luxor', 'shamal' }, -- Larger planes can't land here
    },
    ['grapeseed'] = {
        name = 'grapeseed',
        label = 'Grapeseed Airstrip',
        coords = vector4(2036.67, 4759.05, 41.08, 293.98),
        landing = vector4(2128.13, 4794.33, 41.14, 206.88),
        fuel = vector4(2164.9, 4807.79, 41.22, 27.01),
        terminal = vector4(2128.13, 4794.33, 41.14, 206.88),
        cargo = vector4(2160.0, 4800.0, 41.22, 30.0),
        distance = 12.3,
        type = 'rural',
        availablePlanes = { 'luxor' }, -- Only small planes
    },
    ['zancudo'] = {
        name = 'zancudo',
        label = 'Fort Zancudo (Military)',
        coords = vector4(-2272.15, 3011.23, 32.9, 55.78),
        landing = vector4(-2122.17, 3134.38, 32.81, 324.87),
        fuel = vector4(-2104.59, 3214.67, 32.81, 153.68),
        terminal = vector4(-2122.17, 3134.38, 32.81, 324.87),
        cargo = vector4(-2100.0, 3200.0, 32.81, 150.0),
        distance = 10.8,
        type = 'military',
        availablePlanes = { 'luxor', 'shamal', 'nimbus', 'miljet' },
        restricted = true, -- Special clearance needed
    },
    ['lsia'] = {
        name = 'lsia',
        label = 'Los Santos International',
        coords = vector4(-1470.58, -2796.59, 13.94, 48.14),
        landing = vector4(-1344.08, -2690.38, 13.94, 330.83),
        fuel = vector4(-978.8, -2890.05, 13.95, 144.28),
        terminal = vector4(-1034.89, -2732.98, 20.17, 240.0),
        cargo = vector4(-1089.45, -2915.67, 13.95, 330.0),
        distance = 0,
        type = 'international',
        availablePlanes = { 'luxor', 'shamal', 'nimbus', 'miljet' },
        isHub = true,
    },

    -- CUSTOM AIRPORTS

    ['roxwood'] = {
        name = 'roxwood',
        label = 'Roxwood International Airport',
        coords = vector4(0.0, 0.0, 0.0, 0.0), -- TODO: Update coords
        landing = vector4(0.0, 0.0, 0.0, 0.0), -- TODO: Update coords
        fuel = vector4(0.0, 0.0, 0.0, 0.0), -- TODO: Update coords
        terminal = vector4(0.0, 0.0, 0.0, 0.0), -- TODO: Update coords
        cargo = vector4(0.0, 0.0, 0.0, 0.0), -- TODO: Update coords
        distance = 15.0, -- km from LSIA hub
        type = 'international',
        availablePlanes = { 'luxor', 'shamal', 'nimbus', 'miljet' }, -- Full international, all planes
    },
    ['paleto'] = {
        name = 'paleto',
        label = 'Paleto Regional Airport',
        coords = vector4(0.0, 0.0, 0.0, 0.0), -- TODO: Update coords
        landing = vector4(0.0, 0.0, 0.0, 0.0), -- TODO: Update coords
        fuel = vector4(0.0, 0.0, 0.0, 0.0), -- TODO: Update coords
        terminal = vector4(0.0, 0.0, 0.0, 0.0), -- TODO: Update coords
        cargo = vector4(0.0, 0.0, 0.0, 0.0), -- TODO: Update coords
        distance = 18.0, -- km from LSIA hub
        type = 'regional',
        availablePlanes = { 'luxor', 'shamal', 'nimbus' }, -- Regional, no miljet
    },
}

-- Flight Routes (auto-generated based on airports, but can add custom)
Locations.Routes = {
    -- Standard routes between airports
    { from = 'lsia', to = 'sandy', flightType = 'passenger', priority = 'normal' },
    { from = 'lsia', to = 'grapeseed', flightType = 'passenger', priority = 'normal' },
    { from = 'lsia', to = 'zancudo', flightType = 'cargo', priority = 'high', restricted = true },
    { from = 'sandy', to = 'grapeseed', flightType = 'passenger', priority = 'low' },
    { from = 'sandy', to = 'lsia', flightType = 'passenger', priority = 'normal' },
    { from = 'grapeseed', to = 'sandy', flightType = 'cargo', priority = 'normal' },
    { from = 'grapeseed', to = 'lsia', flightType = 'passenger', priority = 'normal' },

    -- Roxwood International routes
    { from = 'lsia', to = 'roxwood', flightType = 'passenger', priority = 'high' },
    { from = 'roxwood', to = 'lsia', flightType = 'passenger', priority = 'high' },
    { from = 'roxwood', to = 'paleto', flightType = 'passenger', priority = 'normal' },
    { from = 'roxwood', to = 'sandy', flightType = 'cargo', priority = 'normal' },

    -- Paleto Regional routes
    { from = 'lsia', to = 'paleto', flightType = 'passenger', priority = 'normal' },
    { from = 'paleto', to = 'lsia', flightType = 'passenger', priority = 'normal' },
    { from = 'paleto', to = 'grapeseed', flightType = 'cargo', priority = 'low' },
    { from = 'paleto', to = 'roxwood', flightType = 'passenger', priority = 'normal' },
}

-- NPC Spawn Points at Hub
Locations.NPCs = {
    {
        id = 'dispatch',
        label = 'Dispatch Officer',
        coords = vector4(-1037.67, -2963.63, 13.95, 330.0),
        model = 's_m_m_pilot_02',
        scenario = 'WORLD_HUMAN_CLIPBOARD',
        interaction = 'dispatch', -- Links to menu type
    },
    {
        id = 'flightschool',
        label = 'Flight Instructor',
        coords = vector4(-1143.45, -2698.12, 13.95, 330.0),
        model = 's_m_m_pilot_01',
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        interaction = 'school',
    },
    {
        id = 'mechanic',
        label = 'Aircraft Mechanic',
        coords = vector4(-1024.56, -2891.34, 13.95, 150.0),
        model = 's_m_y_airworker',
        scenario = 'WORLD_HUMAN_WELDING',
        interaction = 'maintenance',
    },
    {
        id = 'cargo',
        label = 'Cargo Handler',
        coords = vector4(-1089.45, -2915.67, 13.95, 330.0),
        model = 's_m_m_ups_01',
        scenario = 'WORLD_HUMAN_BUM_STANDING',
        interaction = 'cargo',
    },
    {
        id = 'charter_desk',
        label = 'Charter Services',
        coords = vector4(-1034.89, -2732.98, 20.17, 240.0), -- At terminal
        model = 's_f_m_shop_high',
        scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
        interaction = 'charter', -- Public charter requests
        public = true, -- Any player can interact
    },
}

-- Blip Configuration
Locations.Blips = {
    hub = {
        sprite = 423, -- Plane icon
        color = 3, -- Blue
        scale = 0.8,
        label = 'Los Santos Airlines',
    },
    airport = {
        sprite = 423,
        color = 2, -- Green
        scale = 0.6,
        label = 'Airport',
    },
    flightSchool = {
        sprite = 90, -- Checkered flag
        color = 5, -- Yellow
        scale = 0.7,
        label = 'Flight School',
    },
}
