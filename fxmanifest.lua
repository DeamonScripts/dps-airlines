fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'dps-airlines'
author 'DPSRP'
description 'Advanced Airlines Job System - Multi-Framework'
version '3.0.0'
repository 'https://github.com/DaemonAlex/dps-airlines'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
    'shared/locations.lua',
    'bridge/init.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/server.lua',
    'server/main.lua',
    'server/flights.lua',
    'server/logbook.lua',
    'server/ferry.lua',
    'server/charter.lua',
    'server/charter_requests.lua',
    'server/boss.lua',
    'server/dispatch.lua',
    'server/emergencies.lua',
}

client_scripts {
    'bridge/client.lua',
    'client/main.lua',
    'client/flight.lua',
    'client/passengers.lua',
    'client/cargo.lua',
    'client/charter.lua',
    'client/school.lua',
    'client/maintenance.lua',
    'client/dispatch.lua',
    'client/ferry.lua',
    'client/boss.lua',
    'client/blackbox.lua',
    'client/checkride.lua',
    'client/npc.lua',
    'client/logbook_ui.lua',
    'client/emergencies.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/css/*.css',
    'html/js/*.js',
}

dependencies {
    'ox_lib',
    'oxmysql',
}

-- Optional dependencies (auto-detected)
-- qb-core, qbx_core, or es_extended

provides {
    'dps-airlines'
}
