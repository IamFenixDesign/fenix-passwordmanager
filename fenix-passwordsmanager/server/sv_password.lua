local callbacks = {}

local function getDb()
    if MySQL and MySQL.query and MySQL.query.await then
        return MySQL
    end

    if GetResourceState('oxmysql') == 'started' then
        return {
            query = {
                await = function(query, params)
                    return exports.oxmysql:query_async(query, params or {})
                end
            },
            insert = {
                await = function(query, params)
                    return exports.oxmysql:insert_async(query, params or {})
                end
            },
            update = {
                await = function(query, params)
                    return exports.oxmysql:update_async(query, params or {})
                end
            },
            scalar = {
                await = function(query, params)
                    return exports.oxmysql:scalar_async(query, params or {})
                end
            }
        }
    end

    return nil
end

local function ensureDatabase()
    local db = getDb()
    if not db then
        print('[fenix-passwordsmanager] oxmysql is not started. Database init skipped.')
        return false
    end

    db.query.await([[
        CREATE TABLE IF NOT EXISTS lb_passwordmanager (
            id INT AUTO_INCREMENT PRIMARY KEY,
            owner VARCHAR(80) NOT NULL,
            app_name VARCHAR(100) NOT NULL,
            username VARCHAR(100) NOT NULL,
            password TEXT NOT NULL,
            notes TEXT NULL,
            created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            INDEX idx_owner (owner)
        )
    ]])

    print('[fenix-passwordsmanager] Database table checked/created successfully.')
    return true
end

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    CreateThread(function()
        local attempts = 0
        while attempts < 20 do
            if ensureDatabase() then
                return
            end
            attempts = attempts + 1
            Wait(1000)
        end

        print('[fenix-passwordsmanager] Failed to initialize database table after multiple attempts.')
    end)
end)

RegisterNetEvent('fenix-passwordsmanager:triggerServerCallback', function(name, requestId, data)
    local src = source
    local cb = callbacks[name]
    if not cb then
        TriggerClientEvent('fenix-passwordsmanager:serverCallbackResponse', src, requestId, {
            ok = false,
            message = ('Callback not found: %s'):format(name)
        })
        return
    end

    local ok, result = pcall(cb, src, data)
    if not ok then
        print(('[fenix-passwordsmanager] Server callback error (%s): %s'):format(name, result))
        TriggerClientEvent('fenix-passwordsmanager:serverCallbackResponse', src, requestId, {
            ok = false,
            message = 'Internal server error.'
        })
        return
    end

    TriggerClientEvent('fenix-passwordsmanager:serverCallbackResponse', src, requestId, result)
end)

local function registerCallback(name, cb)
    callbacks[name] = cb
end

local function getIdentifier(source)
    for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
        if identifier:find('license:') == 1 then
            return identifier
        end
    end

    return ('player:%s'):format(source)
end

local function sanitizeText(value)
    if type(value) ~= 'string' then
        return ''
    end

    value = value:gsub('^%s+', ''):gsub('%s+$', '')
    return value
end

local function discordLogEntryCreated(source, appName, username)
    if not FenixPasswordManagerDiscordShouldLog('entry_created') then
        return
    end
    CreateThread(function()
        local fields = FenixPasswordManagerPlayerFields(source)
        fields[#fields + 1] = {
            name = 'App',
            value = FenixPasswordManagerDiscordSafe(appName),
            inline = true,
        }
        if Config.DiscordLogs and Config.DiscordLogs.logUsername then
            fields[#fields + 1] = {
                name = 'Username',
                value = FenixPasswordManagerDiscordSafe(username),
                inline = true,
            }
        end
        FenixPasswordManagerDiscordLog('entry_created', {
            title = 'Password entry created',
            fields = fields,
        })
    end)
end

local function discordLogEntryUpdated(source, entryId, appName, username)
    if not FenixPasswordManagerDiscordShouldLog('entry_updated') then
        return
    end
    CreateThread(function()
        local fields = FenixPasswordManagerPlayerFields(source)
        fields[#fields + 1] = {
            name = 'Entry ID',
            value = tostring(entryId),
            inline = true,
        }
        fields[#fields + 1] = {
            name = 'App',
            value = FenixPasswordManagerDiscordSafe(appName),
            inline = true,
        }
        if Config.DiscordLogs and Config.DiscordLogs.logUsername then
            fields[#fields + 1] = {
                name = 'Username',
                value = FenixPasswordManagerDiscordSafe(username),
                inline = true,
            }
        end
        FenixPasswordManagerDiscordLog('entry_updated', {
            title = 'Password entry updated',
            fields = fields,
        })
    end)
end

local function discordLogEntryDeleted(source, entryId)
    if not FenixPasswordManagerDiscordShouldLog('entry_deleted') then
        return
    end
    CreateThread(function()
        local fields = FenixPasswordManagerPlayerFields(source)
        fields[#fields + 1] = {
            name = 'Entry ID',
            value = tostring(entryId),
            inline = true,
        }
        FenixPasswordManagerDiscordLog('entry_deleted', {
            title = 'Password entry deleted',
            fields = fields,
        })
    end)
end

local function discordLogUnlockSuccess(source)
    if not FenixPasswordManagerDiscordShouldLog('unlock_success') then
        return
    end
    CreateThread(function()
        FenixPasswordManagerDiscordLog('unlock_success', {
            title = 'Password Manager unlocked',
            fields = FenixPasswordManagerPlayerFields(source),
        })
    end)
end

local function discordLogUnlockFailed(source, reason)
    if not FenixPasswordManagerDiscordShouldLog('unlock_failed') then
        return
    end
    CreateThread(function()
        local fields = FenixPasswordManagerPlayerFields(source)
        fields[#fields + 1] = {
            name = 'Reason',
            value = FenixPasswordManagerDiscordSafe(reason),
            inline = false,
        }
        FenixPasswordManagerDiscordLog('unlock_failed', {
            title = 'Password Manager unlock failed',
            fields = fields,
        })
    end)
end

local function getEntries(source)
    local db = getDb()
    if not db then
        return {}
    end

    local owner = getIdentifier(source)

    local rows = db.query.await([[
        SELECT id, app_name, username, password, notes, created_at, updated_at
        FROM lb_passwordmanager
        WHERE owner = ?
        ORDER BY app_name ASC, username ASC
    ]], { owner })

    return rows or {}
end

local function getPlayerPhoneNumber(source)
    if GetResourceState('lb-phone') ~= 'started' then
        return nil
    end

    local ok, phoneNumber = pcall(function()
        return exports['lb-phone']:GetEquippedPhoneNumber(source)
    end)

    if not ok or type(phoneNumber) ~= 'string' or phoneNumber == '' then
        return nil
    end

    return phoneNumber
end

registerCallback('fenix-passwordsmanager:getEntries', function(source)
    return getEntries(source)
end)

registerCallback('fenix-passwordsmanager:unlockWithPhonePin', function(source, data)
    if not Config.Security or not Config.Security.enabled or not Config.Security.useLbPhonePin then
        return { ok = true, message = 'Security disabled.' }
    end

    if GetResourceState('lb-phone') ~= 'started' then
        discordLogUnlockFailed(source, 'LB Phone is not started.')
        return { ok = false, message = 'LB Phone is not started.' }
    end

    local pinAttempt = sanitizeText(data and data.pin)
    if pinAttempt == '' then
        return { ok = false, message = 'Enter your phone PIN.' }
    end

    local phoneNumber = getPlayerPhoneNumber(source)
    if not phoneNumber then
        discordLogUnlockFailed(source, 'No equipped LB Phone found.')
        return { ok = false, message = 'No equipped LB Phone found.' }
    end

    local ok, phonePin = pcall(function()
        return exports['lb-phone']:GetPin(phoneNumber)
    end)

    if not ok then
        discordLogUnlockFailed(source, 'Could not read LB Phone PIN.')
        return { ok = false, message = 'Could not read LB Phone PIN.' }
    end

    phonePin = tostring(phonePin or '')
    if phonePin == '' then
        discordLogUnlockFailed(source, 'No LB Phone PIN is configured for this phone.')
        return { ok = false, message = 'No LB Phone PIN is configured for this phone.' }
    end

    if pinAttempt ~= phonePin then
        discordLogUnlockFailed(source, 'Incorrect phone PIN.')
        return { ok = false, message = 'Incorrect phone PIN.' }
    end

    discordLogUnlockSuccess(source)

    local settings = nil
    pcall(function()
        settings = exports['lb-phone']:GetSettings(phoneNumber)
    end)

    return {
        ok = true,
        method = 'lb-phone-pin',
        faceIdEnabled = type(settings) == 'table' and (
            settings.faceid == true or
            settings.faceId == true or
            settings.biometric == true or
            settings.biometrics == true
        ) or false,
    }
end)

registerCallback('fenix-passwordsmanager:createEntry', function(source, data)
    local db = getDb()
    if not db then
        return { ok = false, message = 'Database unavailable.' }
    end

    local owner = getIdentifier(source)
    local appName = sanitizeText(data and data.app_name)
    local username = sanitizeText(data and data.username)
    local password = sanitizeText(data and data.password)
    local notes = sanitizeText(data and data.notes)

    if appName == '' then
        return { ok = false, message = 'Installed App is required.' }
    end

    if username == '' then
        return { ok = false, message = 'Username is required.' }
    end

    if password == '' then
        return { ok = false, message = 'Password is required.' }
    end

    db.insert.await([[
        INSERT INTO lb_passwordmanager (owner, app_name, username, password, notes)
        VALUES (?, ?, ?, ?, ?)
    ]], { owner, appName, username, password, notes })

    discordLogEntryCreated(source, appName, username)

    return { ok = true, entries = getEntries(source) }
end)

registerCallback('fenix-passwordsmanager:updateEntry', function(source, data)
    local db = getDb()
    if not db then
        return { ok = false, message = 'Database unavailable.' }
    end

    local owner = getIdentifier(source)
    local entryId = tonumber(data and data.id)
    local appName = sanitizeText(data and data.app_name)
    local username = sanitizeText(data and data.username)
    local password = sanitizeText(data and data.password)
    local notes = sanitizeText(data and data.notes)

    if not entryId then
        return { ok = false, message = 'Invalid entry.' }
    end

    if appName == '' or username == '' or password == '' then
        return { ok = false, message = 'Installed App, Username and Password are required.' }
    end

    local affected = db.update.await([[
        UPDATE lb_passwordmanager
        SET app_name = ?, username = ?, password = ?, notes = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ? AND owner = ?
    ]], { appName, username, password, notes, entryId, owner })

    if affected == 0 then
        return { ok = false, message = 'Could not update the entry.' }
    end

    discordLogEntryUpdated(source, entryId, appName, username)

    return { ok = true, entries = getEntries(source) }
end)

registerCallback('fenix-passwordsmanager:deleteEntry', function(source, data)
    local db = getDb()
    if not db then
        return { ok = false, message = 'Database unavailable.' }
    end

    local owner = getIdentifier(source)
    local entryId = tonumber(data and data.id)

    if not entryId then
        return { ok = false, message = 'Invalid entry.' }
    end

    local affected = db.update.await('DELETE FROM lb_passwordmanager WHERE id = ? AND owner = ?', { entryId, owner })

    if affected == 0 then
        return { ok = false, message = 'Could not delete the entry.' }
    end

    discordLogEntryDeleted(source, entryId)

    return { ok = true, entries = getEntries(source) }
end)
