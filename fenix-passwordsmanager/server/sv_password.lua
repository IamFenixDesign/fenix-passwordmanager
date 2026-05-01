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

local function getDiscordLogConfig()
    return Config and Config.DiscordLogs or {}
end

local function isDiscordLogEnabled(eventName)
    local logConfig = getDiscordLogConfig()
    if not logConfig.enabled or type(logConfig.webhook) ~= 'string' or logConfig.webhook == '' then
        return false
    end

    if type(logConfig.events) ~= 'table' then
        return true
    end

    return logConfig.events[eventName] == true
end

local function formatDiscordFieldValue(value)
    value = tostring(value or 'N/A')

    if #value > 1000 then
        return value:sub(1, 997) .. '...'
    end

    return value
end

local function addDiscordField(fields, name, value, inline)
    fields[#fields + 1] = {
        name = name,
        value = formatDiscordFieldValue(value),
        inline = inline == true
    }
end

local function sendDiscordLog(eventName, title, description, fields)
    if not isDiscordLogEnabled(eventName) then
        return
    end

    local logConfig = getDiscordLogConfig()
    local payload = {
        username = logConfig.botName or 'Fenix Password Manager',
        avatar_url = logConfig.avatarUrl ~= '' and logConfig.avatarUrl or nil,
        embeds = {
            {
                title = title,
                description = description,
                color = logConfig.color or 16753920,
                fields = fields or {},
                footer = {
                    text = GetCurrentResourceName()
                },
                timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ')
            }
        }
    }

    PerformHttpRequest(logConfig.webhook, function(status)
        status = tonumber(status) or 0

        if status < 200 or status >= 300 then
            print(('[fenix-passwordsmanager] Discord log failed (%s): HTTP %s'):format(eventName, status))
        end
    end, 'POST', json.encode(payload), {
        ['Content-Type'] = 'application/json'
    })
end

local function buildPlayerLogFields(source)
    local fields = {}
    addDiscordField(fields, 'Player', GetPlayerName(source) or ('ID %s'):format(source), true)
    addDiscordField(fields, 'Server ID', source, true)

    local logConfig = getDiscordLogConfig()
    if logConfig.includeIdentifiers ~= false then
        addDiscordField(fields, 'Identifier', getIdentifier(source), false)
    end

    return fields
end

local function addEntryLogFields(fields, entryId, appName, username, notes)
    local logConfig = getDiscordLogConfig()
    if logConfig.includeEntryDetails ~= true then
        addDiscordField(fields, 'Entry ID', entryId or 'N/A', true)
        return
    end

    addDiscordField(fields, 'Entry ID', entryId or 'N/A', true)
    addDiscordField(fields, 'App', appName or 'N/A', true)
    addDiscordField(fields, 'Username', username or 'N/A', true)

    if notes and notes ~= '' then
        addDiscordField(fields, 'Notes', notes, false)
    end
end

local function sanitizeText(value)
    if type(value) ~= 'string' then
        return ''
    end

    value = value:gsub('^%s+', ''):gsub('%s+$', '')
    return value
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
    local function failUnlock(message)
        local fields = buildPlayerLogFields(source)
        addDiscordField(fields, 'Reason', message, false)
        sendDiscordLog('unlockFailed', 'Password Manager unlock failed', 'A player failed to unlock the password manager.', fields)

        return { ok = false, message = message }
    end

    if not Config.Security or not Config.Security.enabled or not Config.Security.useLbPhonePin then
        return { ok = true, message = 'Security disabled.' }
    end

    if GetResourceState('lb-phone') ~= 'started' then
        return failUnlock('LB Phone is not started.')
    end

    local pinAttempt = sanitizeText(data and data.pin)
    if pinAttempt == '' then
        return failUnlock('Enter your phone PIN.')
    end

    local phoneNumber = getPlayerPhoneNumber(source)
    if not phoneNumber then
        return failUnlock('No equipped LB Phone found.')
    end

    local ok, phonePin = pcall(function()
        return exports['lb-phone']:GetPin(phoneNumber)
    end)

    if not ok then
        return failUnlock('Could not read LB Phone PIN.')
    end

    phonePin = tostring(phonePin or '')
    if phonePin == '' then
        return failUnlock('No LB Phone PIN is configured for this phone.')
    end

    if pinAttempt ~= phonePin then
        return failUnlock('Incorrect phone PIN.')
    end

    local settings = nil
    pcall(function()
        settings = exports['lb-phone']:GetSettings(phoneNumber)
    end)

    local fields = buildPlayerLogFields(source)
    addDiscordField(fields, 'Method', 'LB Phone PIN', true)
    sendDiscordLog('unlockSuccess', 'Password Manager unlocked', 'A player unlocked the password manager.', fields)

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

    local entryId = db.insert.await([[
        INSERT INTO lb_passwordmanager (owner, app_name, username, password, notes)
        VALUES (?, ?, ?, ?, ?)
    ]], { owner, appName, username, password, notes })

    local fields = buildPlayerLogFields(source)
    addEntryLogFields(fields, entryId, appName, username, notes)
    sendDiscordLog('createEntry', 'Password entry created', 'A player created a password manager entry.', fields)

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

    local fields = buildPlayerLogFields(source)
    addEntryLogFields(fields, entryId, appName, username, notes)
    sendDiscordLog('updateEntry', 'Password entry updated', 'A player updated a password manager entry.', fields)

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

    local entry = db.query.await([[
        SELECT app_name, username, notes
        FROM lb_passwordmanager
        WHERE id = ? AND owner = ?
        LIMIT 1
    ]], { entryId, owner })

    local affected = db.update.await('DELETE FROM lb_passwordmanager WHERE id = ? AND owner = ?', { entryId, owner })

    if affected == 0 then
        return { ok = false, message = 'Could not delete the entry.' }
    end

    entry = entry and entry[1] or {}

    local fields = buildPlayerLogFields(source)
    addEntryLogFields(fields, entryId, entry.app_name, entry.username, entry.notes)
    sendDiscordLog('deleteEntry', 'Password entry deleted', 'A player deleted a password manager entry.', fields)

    return { ok = true, entries = getEntries(source) }
end)
