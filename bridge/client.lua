--[[
    dps-airlines Client Bridge
    Framework Abstraction
]]

local QBCore, ESX = nil, nil
local PlayerData = {}

-- Initialize framework objects
CreateThread(function()
    if Bridge.Framework == 'qb' or Bridge.Framework == 'qbx' then
        QBCore = exports['qb-core']:GetCoreObject()
    elseif Bridge.Framework == 'esx' then
        ESX = exports['es_extended']:getSharedObject()
    end
end)

-- ═══════════════════════════════════════════════════════
-- PLAYER DATA
-- ═══════════════════════════════════════════════════════

function Bridge.GetPlayerData()
    if Bridge.Framework == 'qb' or Bridge.Framework == 'qbx' then
        return QBCore and QBCore.Functions.GetPlayerData() or {}
    elseif Bridge.Framework == 'esx' then
        return ESX and ESX.GetPlayerData() or {}
    end
    return {}
end

function Bridge.GetIdentifier()
    local data = Bridge.GetPlayerData()

    if Bridge.Framework == 'qb' or Bridge.Framework == 'qbx' then
        return data.citizenid
    elseif Bridge.Framework == 'esx' then
        return data.identifier
    end
    return nil
end

function Bridge.GetJob()
    local data = Bridge.GetPlayerData()

    if Bridge.Framework == 'qb' or Bridge.Framework == 'qbx' then
        return data.job
    elseif Bridge.Framework == 'esx' then
        return data.job
    end
    return nil
end

function Bridge.GetJobName()
    local job = Bridge.GetJob()
    return job and job.name or nil
end

function Bridge.IsOnDuty()
    local job = Bridge.GetJob()
    if not job then return false end

    if Bridge.Framework == 'qb' or Bridge.Framework == 'qbx' then
        return job.onduty
    elseif Bridge.Framework == 'esx' then
        -- ESX doesn't have native duty, check external system or return true
        return true
    end
    return false
end

function Bridge.GetJobGrade()
    local job = Bridge.GetJob()
    if not job then return 0 end

    if Bridge.Framework == 'qb' or Bridge.Framework == 'qbx' then
        return job.grade and job.grade.level or 0
    elseif Bridge.Framework == 'esx' then
        return job.grade or 0
    end
    return 0
end

function Bridge.GetCharName()
    local data = Bridge.GetPlayerData()

    if Bridge.Framework == 'qb' or Bridge.Framework == 'qbx' then
        local charinfo = data.charinfo
        if charinfo then
            return charinfo.firstname .. ' ' .. charinfo.lastname
        end
    elseif Bridge.Framework == 'esx' then
        return data.firstName and (data.firstName .. ' ' .. (data.lastName or '')) or 'Pilot'
    end
    return 'Pilot'
end

-- ═══════════════════════════════════════════════════════
-- NOTIFICATIONS
-- ═══════════════════════════════════════════════════════

function Bridge.Notify(title, message, notifyType, duration)
    notifyType = notifyType or 'inform'
    duration = duration or 5000

    lib.notify({
        title = title,
        description = message,
        type = notifyType,
        duration = duration
    })
end

-- ═══════════════════════════════════════════════════════
-- PLAYER LOADED EVENT HANDLERS
-- ═══════════════════════════════════════════════════════

-- Event names for each framework
Bridge.Events = {
    PlayerLoaded = Bridge.Framework == 'esx' and 'esx:playerLoaded' or 'QBCore:Client:OnPlayerLoaded',
    PlayerUnloaded = Bridge.Framework == 'esx' and 'esx:onPlayerLogout' or 'QBCore:Client:OnPlayerUnload',
    JobUpdated = Bridge.Framework == 'esx' and 'esx:setJob' or 'QBCore:Client:OnJobUpdate'
}

-- QB/QBX Event Handlers
if Bridge.Framework == 'qb' or Bridge.Framework == 'qbx' then
    RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
        TriggerEvent('dps-airlines:client:playerLoaded')
    end)

    RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
        TriggerEvent('dps-airlines:client:playerUnloaded')
    end)

    RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
        TriggerEvent('dps-airlines:client:jobUpdated', job)
    end)
end

-- ESX Event Handlers
if Bridge.Framework == 'esx' then
    RegisterNetEvent('esx:playerLoaded', function(xPlayer)
        PlayerData = xPlayer
        TriggerEvent('dps-airlines:client:playerLoaded')
    end)

    RegisterNetEvent('esx:onPlayerLogout', function()
        PlayerData = {}
        TriggerEvent('dps-airlines:client:playerUnloaded')
    end)

    RegisterNetEvent('esx:setJob', function(job)
        TriggerEvent('dps-airlines:client:jobUpdated', job)
    end)
end

-- ═══════════════════════════════════════════════════════
-- INVENTORY CHECKS
-- ═══════════════════════════════════════════════════════

function Bridge.HasItem(item, count)
    count = count or 1

    -- Try ox_inventory
    local success, result = pcall(function()
        return exports.ox_inventory:GetItemCount(item) >= count
    end)
    if success then return result end

    -- Try qs-inventory
    success, result = pcall(function()
        return exports['qs-inventory']:GetItemTotalAmount(item) >= count
    end)
    if success then return result end

    -- Fallback to callback
    return lib.callback.await('dps-airlines:server:hasItem', false, item, count)
end

-- ═══════════════════════════════════════════════════════
-- UTILITY
-- ═══════════════════════════════════════════════════════

function Bridge.IsLoggedIn()
    if LocalPlayer.state.isLoggedIn ~= nil then
        return LocalPlayer.state.isLoggedIn
    end

    local data = Bridge.GetPlayerData()

    if Bridge.Framework == 'qb' or Bridge.Framework == 'qbx' then
        return data.citizenid ~= nil
    elseif Bridge.Framework == 'esx' then
        return data.identifier ~= nil
    end

    return false
end
