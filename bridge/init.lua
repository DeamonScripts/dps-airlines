--[[
    dps-airlines Bridge Initialization
    Framework Detection for QB/QBX/ESX
]]

Bridge = Bridge or {}

-- Framework Detection
local function DetectFramework()
    if GetResourceState('qbx_core') == 'started' then
        return 'qbx'
    elseif GetResourceState('qb-core') == 'started' then
        return 'qb'
    elseif GetResourceState('es_extended') == 'started' then
        return 'esx'
    end
    return 'standalone'
end

-- Initialize Bridge
Bridge.Framework = DetectFramework()

-- Debug helper
function Bridge.Debug(...)
    if Config.Debug then
        print('^3[dps-airlines]^7', ...)
    end
end

-- Print startup info
if IsDuplicityVersion() then
    print('^2[dps-airlines]^7 Bridge initialized')
    print('^2[dps-airlines]^7 Framework: ^3' .. Bridge.Framework .. '^7')
end
