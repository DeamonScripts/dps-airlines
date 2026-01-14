--[[
    dps-airlines Server Bridge
    Framework Abstraction for QB/QBX/ESX
]]

local QBCore, ESX = nil, nil

-- Initialize framework objects
CreateThread(function()
    if Bridge.Framework == 'qb' or Bridge.Framework == 'qbx' then
        QBCore = exports['qb-core']:GetCoreObject()
    elseif Bridge.Framework == 'esx' then
        ESX = exports['es_extended']:getSharedObject()
    end
end)

-- ═══════════════════════════════════════════════════════
-- PLAYER FUNCTIONS
-- ═══════════════════════════════════════════════════════

function Bridge.GetPlayer(source)
    if Bridge.Framework == 'qb' or Bridge.Framework == 'qbx' then
        return QBCore and QBCore.Functions.GetPlayer(source)
    elseif Bridge.Framework == 'esx' then
        return ESX and ESX.GetPlayerFromId(source)
    end
    return nil
end

function Bridge.GetPlayerByIdentifier(identifier)
    if Bridge.Framework == 'qb' or Bridge.Framework == 'qbx' then
        return QBCore and QBCore.Functions.GetPlayerByCitizenId(identifier)
    elseif Bridge.Framework == 'esx' then
        return ESX and ESX.GetPlayerFromIdentifier(identifier)
    end
    return nil
end

function Bridge.GetIdentifier(source)
    local player = Bridge.GetPlayer(source)
    if not player then return nil end

    if Bridge.Framework == 'qb' or Bridge.Framework == 'qbx' then
        return player.PlayerData.citizenid
    elseif Bridge.Framework == 'esx' then
        return player.identifier
    end
    return nil
end

function Bridge.GetPlayerName(source)
    local player = Bridge.GetPlayer(source)
    if not player then return 'Unknown' end

    if Bridge.Framework == 'qb' or Bridge.Framework == 'qbx' then
        local charinfo = player.PlayerData.charinfo
        return charinfo.firstname .. ' ' .. charinfo.lastname
    elseif Bridge.Framework == 'esx' then
        return player.getName()
    end
    return 'Unknown'
end

-- ═══════════════════════════════════════════════════════
-- JOB FUNCTIONS
-- ═══════════════════════════════════════════════════════

function Bridge.GetPlayerJob(source)
    local player = Bridge.GetPlayer(source)
    if not player then return nil end

    if Bridge.Framework == 'qb' or Bridge.Framework == 'qbx' then
        return player.PlayerData.job
    elseif Bridge.Framework == 'esx' then
        return player.job
    end
    return nil
end

function Bridge.GetJobName(source)
    local job = Bridge.GetPlayerJob(source)
    return job and job.name or nil
end

function Bridge.GetJobGrade(source)
    local job = Bridge.GetPlayerJob(source)
    if not job then return 0 end

    if Bridge.Framework == 'qb' or Bridge.Framework == 'qbx' then
        return job.grade.level
    elseif Bridge.Framework == 'esx' then
        return job.grade
    end
    return 0
end

function Bridge.IsOnDuty(source)
    local player = Bridge.GetPlayer(source)
    if not player then return false end

    if Bridge.Framework == 'qb' or Bridge.Framework == 'qbx' then
        return player.PlayerData.job.onduty
    elseif Bridge.Framework == 'esx' then
        -- ESX doesn't have native duty system, use metadata or always true
        return true
    end
    return false
end

function Bridge.SetJobDuty(source, onDuty)
    local player = Bridge.GetPlayer(source)
    if not player then return false end

    if Bridge.Framework == 'qb' or Bridge.Framework == 'qbx' then
        player.Functions.SetJobDuty(onDuty)
        return true
    elseif Bridge.Framework == 'esx' then
        -- ESX typically uses external duty system
        return true
    end
    return false
end

function Bridge.SetJob(source, jobName, grade)
    local player = Bridge.GetPlayer(source)
    if not player then return false end

    if Bridge.Framework == 'qb' or Bridge.Framework == 'qbx' then
        player.Functions.SetJob(jobName, grade)
        return true
    elseif Bridge.Framework == 'esx' then
        player.setJob(jobName, grade)
        return true
    end
    return false
end

-- ═══════════════════════════════════════════════════════
-- MONEY FUNCTIONS
-- ═══════════════════════════════════════════════════════

function Bridge.AddMoney(source, account, amount, reason)
    local player = Bridge.GetPlayer(source)
    if not player then return false end

    if Bridge.Framework == 'qb' or Bridge.Framework == 'qbx' then
        return player.Functions.AddMoney(account, amount, reason)
    elseif Bridge.Framework == 'esx' then
        if account == 'cash' then
            player.addMoney(amount)
        elseif account == 'bank' then
            player.addAccountMoney('bank', amount)
        end
        return true
    end
    return false
end

function Bridge.RemoveMoney(source, account, amount, reason)
    local player = Bridge.GetPlayer(source)
    if not player then return false end

    if Bridge.Framework == 'qb' or Bridge.Framework == 'qbx' then
        return player.Functions.RemoveMoney(account, amount, reason)
    elseif Bridge.Framework == 'esx' then
        if account == 'cash' then
            player.removeMoney(amount)
        elseif account == 'bank' then
            player.removeAccountMoney('bank', amount)
        end
        return true
    end
    return false
end

function Bridge.GetMoney(source, account)
    local player = Bridge.GetPlayer(source)
    if not player then return 0 end

    if Bridge.Framework == 'qb' or Bridge.Framework == 'qbx' then
        return player.PlayerData.money[account] or 0
    elseif Bridge.Framework == 'esx' then
        if account == 'cash' then
            return player.getMoney()
        elseif account == 'bank' then
            return player.getAccount('bank').money
        end
    end
    return 0
end

-- ═══════════════════════════════════════════════════════
-- SOCIETY / MANAGEMENT FUNDS
-- ═══════════════════════════════════════════════════════

function Bridge.GetSocietyMoney(society)
    -- Try qb-management first
    local success, money = pcall(function()
        return exports['qb-management']:GetAccount(society)
    end)
    if success and money then return money end

    -- Try qb-banking
    success, money = pcall(function()
        return exports['qb-banking']:GetAccountBalance(society)
    end)
    if success and money then return money end

    -- Try esx_society
    if Bridge.Framework == 'esx' then
        success, money = pcall(function()
            local result = MySQL.single.await('SELECT money FROM addon_account_data WHERE account_name = ? AND owner = ?',
                { 'society_' .. society, 'society_' .. society })
            return result and result.money or 0
        end)
        if success and money then return money end
    end

    return 0
end

function Bridge.AddSocietyMoney(society, amount)
    -- Try qb-management
    local success = pcall(function()
        exports['qb-management']:AddMoney(society, amount)
    end)
    if success then return true end

    -- Try qb-banking
    success = pcall(function()
        exports['qb-banking']:AddMoney(society, amount, 'deposit')
    end)
    if success then return true end

    -- Try esx_addonaccount
    if Bridge.Framework == 'esx' then
        success = pcall(function()
            TriggerEvent('esx_addonaccount:getSharedAccount', 'society_' .. society, function(account)
                if account then account.addMoney(amount) end
            end)
        end)
        if success then return true end
    end

    return false
end

function Bridge.RemoveSocietyMoney(society, amount)
    -- Try qb-management
    local success, result = pcall(function()
        return exports['qb-management']:RemoveMoney(society, amount)
    end)
    if success then return result end

    -- Try qb-banking
    success, result = pcall(function()
        return exports['qb-banking']:RemoveMoney(society, amount, 'withdraw')
    end)
    if success then return result end

    -- Try esx_addonaccount
    if Bridge.Framework == 'esx' then
        success = pcall(function()
            TriggerEvent('esx_addonaccount:getSharedAccount', 'society_' .. society, function(account)
                if account then account.removeMoney(amount) end
            end)
        end)
        if success then return true end
    end

    return false
end

-- ═══════════════════════════════════════════════════════
-- INVENTORY FUNCTIONS
-- ═══════════════════════════════════════════════════════

function Bridge.AddItem(source, item, count, metadata)
    -- Try ox_inventory first
    local success = pcall(function()
        exports.ox_inventory:AddItem(source, item, count, metadata)
    end)
    if success then return true end

    -- Try qs-inventory
    success = pcall(function()
        exports['qs-inventory']:AddItem(source, item, count, nil, metadata)
    end)
    if success then return true end

    -- Try qb-inventory
    if Bridge.Framework == 'qb' or Bridge.Framework == 'qbx' then
        local player = Bridge.GetPlayer(source)
        if player then
            player.Functions.AddItem(item, count, nil, metadata)
            TriggerClientEvent('inventory:client:ItemBox', source, QBCore.Shared.Items[item], 'add')
            return true
        end
    elseif Bridge.Framework == 'esx' then
        -- ESX native inventory
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            xPlayer.addInventoryItem(item, count)
            return true
        end
    end

    return false
end

function Bridge.RemoveItem(source, item, count)
    -- Try ox_inventory first
    local success = pcall(function()
        exports.ox_inventory:RemoveItem(source, item, count)
    end)
    if success then return true end

    -- Try qs-inventory
    success = pcall(function()
        exports['qs-inventory']:RemoveItem(source, item, count)
    end)
    if success then return true end

    -- Try qb-inventory
    if Bridge.Framework == 'qb' or Bridge.Framework == 'qbx' then
        local player = Bridge.GetPlayer(source)
        if player then
            player.Functions.RemoveItem(item, count)
            TriggerClientEvent('inventory:client:ItemBox', source, QBCore.Shared.Items[item], 'remove')
            return true
        end
    elseif Bridge.Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            xPlayer.removeInventoryItem(item, count)
            return true
        end
    end

    return false
end

function Bridge.HasItem(source, item, count)
    count = count or 1

    -- Try ox_inventory first
    local success, result = pcall(function()
        return exports.ox_inventory:GetItemCount(source, item) >= count
    end)
    if success then return result end

    -- Try qs-inventory
    success, result = pcall(function()
        return exports['qs-inventory']:GetItemTotalAmount(source, item) >= count
    end)
    if success then return result end

    -- Try qb-inventory
    if Bridge.Framework == 'qb' or Bridge.Framework == 'qbx' then
        local player = Bridge.GetPlayer(source)
        if player then
            local itemData = player.Functions.GetItemByName(item)
            return itemData and itemData.amount >= count
        end
    elseif Bridge.Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            local itemData = xPlayer.getInventoryItem(item)
            return itemData and itemData.count >= count
        end
    end

    return false
end

-- ═══════════════════════════════════════════════════════
-- COMMANDS
-- ═══════════════════════════════════════════════════════

function Bridge.AddCommand(name, help, params, restricted, callback)
    if Bridge.Framework == 'qb' or Bridge.Framework == 'qbx' then
        QBCore.Commands.Add(name, help, params or {}, false, callback, restricted and 'admin' or false)
    elseif Bridge.Framework == 'esx' then
        ESX.RegisterCommand(name, restricted and 'admin' or 'user', function(xPlayer, args, showError)
            callback(xPlayer.source, args)
        end, true, { help = help })
    else
        -- Fallback to ox_lib command
        lib.addCommand(name, {
            help = help,
            restricted = restricted and 'group.admin' or false
        }, callback)
    end
end

-- ═══════════════════════════════════════════════════════
-- NOTIFICATIONS
-- ═══════════════════════════════════════════════════════

function Bridge.Notify(source, title, message, notifyType, duration)
    notifyType = notifyType or 'inform'
    duration = duration or 5000

    -- Always use ox_lib (required dependency)
    TriggerClientEvent('ox_lib:notify', source, {
        title = title,
        description = message,
        type = notifyType,
        duration = duration
    })
end

-- ═══════════════════════════════════════════════════════
-- PLAYER LIST (for weather alerts, etc.)
-- ═══════════════════════════════════════════════════════

function Bridge.GetPlayers()
    if Bridge.Framework == 'qb' or Bridge.Framework == 'qbx' then
        return QBCore.Functions.GetQBPlayers()
    elseif Bridge.Framework == 'esx' then
        return ESX.GetExtendedPlayers()
    end
    return {}
end

function Bridge.GetPlayersByJob(jobName)
    local players = {}

    if Bridge.Framework == 'qb' or Bridge.Framework == 'qbx' then
        local qbPlayers = QBCore.Functions.GetQBPlayers()
        for _, player in pairs(qbPlayers) do
            if player.PlayerData.job.name == jobName then
                table.insert(players, {
                    source = player.PlayerData.source,
                    identifier = player.PlayerData.citizenid,
                    job = player.PlayerData.job,
                    onDuty = player.PlayerData.job.onduty
                })
            end
        end
    elseif Bridge.Framework == 'esx' then
        local esxPlayers = ESX.GetExtendedPlayers('job', jobName)
        for _, player in ipairs(esxPlayers) do
            table.insert(players, {
                source = player.source,
                identifier = player.identifier,
                job = player.job,
                onDuty = true -- ESX doesn't have native duty
            })
        end
    end

    return players
end

-- ═══════════════════════════════════════════════════════
-- WEATHER INTEGRATION
-- ═══════════════════════════════════════════════════════

function Bridge.GetCurrentWeather()
    -- Try qb-weathersync
    local success, weather = pcall(function()
        return exports['qb-weathersync']:getWeatherState()
    end)
    if success and weather then return weather end

    -- Try cd_easytime
    success, weather = pcall(function()
        return exports['cd_easytime']:GetWeather()
    end)
    if success and weather then return weather end

    -- Try vSync
    success, weather = pcall(function()
        return GlobalState.Weather or 'CLEAR'
    end)
    if success and weather then return weather end

    return 'CLEAR'
end

-- ═══════════════════════════════════════════════════════
-- PLAYER LOADED EVENT HANDLERS
-- ═══════════════════════════════════════════════════════

function Bridge.OnPlayerLoaded(callback)
    if Bridge.Framework == 'qb' or Bridge.Framework == 'qbx' then
        AddEventHandler('QBCore:Server:PlayerLoaded', function(Player)
            callback(Player.PlayerData.source, Player)
        end)
    elseif Bridge.Framework == 'esx' then
        RegisterNetEvent('esx:playerLoaded', function(playerId, xPlayer)
            callback(playerId, xPlayer)
        end)
    end
end

function Bridge.OnPlayerDropped(callback)
    AddEventHandler('playerDropped', function(reason)
        local src = source
        local identifier = Bridge.GetIdentifier(src)
        callback(src, identifier, reason)
    end)
end
