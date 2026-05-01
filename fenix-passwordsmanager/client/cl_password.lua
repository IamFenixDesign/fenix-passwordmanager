local resourceName = GetCurrentResourceName()
local callbackId = 0
local pendingCallbacks = {}
local authState = {
    unlockedAt = 0,
}

local function triggerServerCallback(name, data, cb)
    callbackId = callbackId + 1
    pendingCallbacks[callbackId] = cb
    TriggerServerEvent('fenix-passwordsmanager:triggerServerCallback', name, callbackId, data)
end

RegisterNetEvent('fenix-passwordsmanager:serverCallbackResponse', function(requestId, response)
    local cb = pendingCallbacks[requestId]
    if not cb then return end

    pendingCallbacks[requestId] = nil
    cb(response)
end)

local function normalizeLabel(identifier, data)
    if type(data) == 'table' then
        for _, key in ipairs({ 'name', 'label', 'title', 'app', 'identifier' }) do
            if type(data[key]) == 'string' and data[key] ~= '' then
                return tostring(data[key])
            end
        end
    end

    return tostring(identifier)
end

local function getPhoneApps()
    local apps = {}
    local seen = {}

    if GetResourceState('lb-phone') ~= 'started' then
        return apps
    end

    local settings = nil
    pcall(function()
        settings = exports['lb-phone']:GetSettings()
    end)

    local config = nil
    pcall(function()
        config = exports['lb-phone']:GetConfig()
    end)

    local installedLookup = {}

    local function markInstalled(identifier, label)
        if type(identifier) ~= 'string' or identifier == '' then return end
        if identifier == Config.App.identifier then return end

        if not seen[identifier] then
            seen[identifier] = true
            apps[#apps + 1] = {
                value = identifier,
                label = label and tostring(label) or identifier
            }
        end
    end

    local function scanInstalledTables(node, depth)
        if type(node) ~= 'table' or depth > 6 then return end

        for key, value in pairs(node) do
            if type(value) == 'table' then
                local identifier = value.identifier or value.app or value.id or value.name or (type(key) == 'string' and key or nil)
                local label = value.label or value.title or value.name or value.identifier or identifier
                local installed = value.installed or value.isInstalled or value.downloaded or value.enabled or value.visible

                if type(identifier) == 'string' and installed == true then
                    installedLookup[identifier] = label or identifier
                end

                scanInstalledTables(value, depth + 1)
            elseif type(key) == 'string' and (value == true) then
                local lowerKey = key:lower()
                if lowerKey ~= 'darkmode' and lowerKey ~= 'streamermode' and lowerKey ~= 'airplanemode' then
                    installedLookup[key] = key
                end
            end
        end
    end

    scanInstalledTables(settings, 0)

    for identifier, label in pairs(installedLookup) do
        markInstalled(tostring(identifier), normalizeLabel(identifier, { name = label }))
    end

    local function tryAppRecord(identifier, data)
        if type(identifier) ~= 'string' or identifier == '' then return end
        if identifier == Config.App.identifier then return end
        if seen[identifier] then return end

        if type(data) ~= 'table' then
            markInstalled(identifier, identifier)
            return
        end

        if data.hidden == true then return end
        if data.available == false then return end

        if next(installedLookup) == nil then
            markInstalled(identifier, normalizeLabel(identifier, data))
            return
        end

        if installedLookup[identifier] then
            markInstalled(identifier, normalizeLabel(identifier, data))
            return
        end

        local altName = type(data.name) == 'string' and data.name or nil
        if altName and installedLookup[altName] then
            markInstalled(identifier, normalizeLabel(identifier, data))
        end
    end

    local function scanConfigNode(node, depth)
        if type(node) ~= 'table' or depth > 6 then return end

        for key, value in pairs(node) do
            if type(value) == 'table' then
                local identifier = value.identifier or value.app or value.id
                if type(key) == 'string' and (value.name or value.label or value.ui or value.description or value.icon or value.defaultApp ~= nil) then
                    identifier = identifier or key
                    tryAppRecord(identifier, value)
                elseif type(identifier) == 'string' then
                    tryAppRecord(identifier, value)
                end

                scanConfigNode(value, depth + 1)
            end
        end
    end

    scanConfigNode(config, 0)

    table.sort(apps, function(a, b)
        return a.label:lower() < b.label:lower()
    end)

    return apps
end

local function isUnlocked()
    if not Config.Security or not Config.Security.enabled then
        return true
    end

    local rememberForSeconds = tonumber(Config.Security.rememberForSeconds) or 0
    if rememberForSeconds <= 0 then
        return false
    end

    return (GetGameTimer() - authState.unlockedAt) <= (rememberForSeconds * 1000)
end

local function markUnlocked()
    authState.unlockedAt = GetGameTimer()
end

local function pushSecurityState(reason)
    if GetResourceState('lb-phone') ~= 'started' then return end

    exports['lb-phone']:SendCustomAppMessage(Config.App.identifier, {
        type = 'pm:securityState',
        unlocked = isUnlocked(),
        reason = reason,
        rememberForSeconds = Config.Security and Config.Security.rememberForSeconds or 0,
        requireUnlockForEdit = Config.Security and Config.Security.requireUnlockForEdit == true,
        requireUnlockToRevealPassword = Config.Security and Config.Security.requireUnlockToRevealPassword == true,
        usesLbPhonePin = Config.Security and Config.Security.useLbPhonePin == true,
    })
end

local function registerApp()
    local app = {
        identifier = Config.App.identifier,
        name = Config.App.name,
        description = Config.App.description,
        developer = Config.App.developer,
        defaultApp = Config.App.defaultApp,
        size = Config.App.size,
        price = Config.App.price,
        landscape = Config.App.landscape,
        fixBlur = true,
        ui = resourceName .. '/ui/index.html',
        icon = Config.App.icon,
        onOpen = function()
            if Config.Security and Config.Security.lockOnAppOpen then
                authState.unlockedAt = 0
            end
            pushSecurityState('open')
        end,
        onClose = function()
            pushSecurityState('close')
        end,
    }

    if GetResourceState('lb-phone') == 'started' then
        exports['lb-phone']:AddCustomApp(app)
    end
end

AddEventHandler('onClientResourceStart', function(startedResource)
    if startedResource == 'lb-phone' or startedResource == resourceName then
        Wait(500)
        registerApp()
    end
end)

AddEventHandler('onClientResourceStop', function(stoppedResource)
    if stoppedResource == resourceName and GetResourceState('lb-phone') == 'started' then
        exports['lb-phone']:RemoveCustomApp(Config.App.identifier)
    end
end)

RegisterNUICallback('pm:getEntries', function(_, cb)
    triggerServerCallback('fenix-passwordsmanager:getEntries', {}, function(entries)
        cb(entries or {})
    end)
end)

RegisterNUICallback('pm:getApps', function(_, cb)
    cb(getPhoneApps())
end)

local function detectThemeFromValue(node, depth)
    if depth > 8 then return nil end
    if type(node) ~= 'table' then return nil end

    local directKeys = {
        'theme', 'Theme', 'appearance', 'Appearance', 'colorScheme', 'colorscheme',
        'mode', 'Mode', 'style', 'Style'
    }

    for _, key in ipairs(directKeys) do
        local value = node[key]
        if type(value) == 'string' then
            local normalized = value:lower()
            if normalized:find('dark', 1, true) then
                return 'dark'
            end
            if normalized:find('light', 1, true) then
                return 'light'
            end
        end
    end

    local darkFlags = {
        node.darkMode,
        node.darkmode,
        node.isDarkMode,
        node.isdarkmode,
        node.dark,
        node.isDark,
    }

    for _, value in ipairs(darkFlags) do
        if value == true then
            return 'dark'
        elseif value == false then
            return 'light'
        end
    end

    for key, value in pairs(node) do
        if type(value) == 'table' then
            local nested = detectThemeFromValue(value, depth + 1)
            if nested then
                return nested
            end
        elseif type(value) == 'string' and type(key) == 'string' then
            local lowerKey = key:lower()
            local lowerValue = value:lower()
            if lowerKey:find('theme', 1, true) or lowerKey:find('appearance', 1, true) or lowerKey:find('scheme', 1, true) or lowerKey == 'mode' then
                if lowerValue:find('dark', 1, true) then
                    return 'dark'
                end
                if lowerValue:find('light', 1, true) then
                    return 'light'
                end
            end
        end
    end

    return nil
end

RegisterNUICallback('pm:getTheme', function(_, cb)
    local theme = 'light'

    if GetResourceState('lb-phone') == 'started' then
        local settings = nil
        pcall(function()
            settings = exports['lb-phone']:GetSettings()
        end)

        local detectedTheme = detectThemeFromValue(settings, 0)
        if detectedTheme == 'dark' then
            theme = 'dark'
        end
    end

    cb({ theme = theme })
end)

RegisterNUICallback('pm:getSecurityConfig', function(_, cb)
    cb({
        enabled = Config.Security and Config.Security.enabled == true,
        unlocked = isUnlocked(),
        rememberForSeconds = Config.Security and Config.Security.rememberForSeconds or 0,
        requireUnlockForEdit = Config.Security and Config.Security.requireUnlockForEdit == true,
        requireUnlockToRevealPassword = Config.Security and Config.Security.requireUnlockToRevealPassword == true,
        usesLbPhonePin = Config.Security and Config.Security.useLbPhonePin == true,
    })
end)

RegisterNUICallback('pm:unlockWithPhonePin', function(data, cb)
    triggerServerCallback('fenix-passwordsmanager:unlockWithPhonePin', data, function(response)
        if response and response.ok then
            markUnlocked()
        end

        pushSecurityState('unlock')
        cb(response or { ok = false, message = 'No response from the server.' })
    end)
end)

RegisterNUICallback('pm:createEntry', function(data, cb)
    triggerServerCallback('fenix-passwordsmanager:createEntry', data, function(response)
        cb(response or { ok = false, message = 'No response from the server.' })
    end)
end)

RegisterNUICallback('pm:updateEntry', function(data, cb)
    triggerServerCallback('fenix-passwordsmanager:updateEntry', data, function(response)
        cb(response or { ok = false, message = 'No response from the server.' })
    end)
end)

RegisterNUICallback('pm:deleteEntry', function(data, cb)
    triggerServerCallback('fenix-passwordsmanager:deleteEntry', data, function(response)
        cb(response or { ok = false, message = 'No response from the server.' })
    end)
end)
