fx_version 'cerulean'
game 'gta5'

author 'DPSRP'
description 'Advanced Airlines Job System'
version '2.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    '@qb-core/shared/locale.lua',
    'shared/config.lua',
    'shared/locations.lua',
}

client_scripts {
    'client/main.lua',
    'client/flight.lua',
    'client/passengers.lua',
    'client/cargo.lua',
    'client/charter.lua',
    'client/school.lua',
    'client/maintenance.lua',
    'client/dispatch.lua',
    'client/blackbox.lua',
    'client/checkride.lua',
    'client/npc.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/flights.lua',
    'server/charter.lua',
    'server/boss.lua',
    'server/dispatch.lua',
}

lua54 'yes'

dependencies {
    'ox_lib',
    'qb-core',
    'oxmysql',
}
