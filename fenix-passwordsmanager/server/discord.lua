--- Discord webhook helpers (no passwords or PINs are ever sent).

local function utcIso8601()
    return os.date('!%Y-%m-%dT%H:%M:%SZ')
end

local function truncate(str, maxLen)
    maxLen = maxLen or 900
    if type(str) ~= 'string' then
        return ''
    end
    if #str <= maxLen then
        return str
    end
    return str:sub(1, maxLen - 3) .. '...'
end

local function discordEscape(str)
    if type(str) ~= 'string' then
        return ''
    end
    return str
        :gsub('\\', '\\\\')
        :gsub('`', '\\`')
end

function FenixPasswordManagerDiscordSafe(str)
    if type(str) ~= 'string' then
        str = tostring(str or '')
    end
    return discordEscape(truncate(str, 240))
end

local function webhookPayload(username, avatarUrl, embed)
    local payload = {
        username = username,
        embeds = { embed },
    }
    if avatarUrl and avatarUrl ~= '' then
        payload.avatar_url = avatarUrl
    end
    return json.encode(payload)
end

function FenixPasswordManagerDiscordShouldLog(category)
    local root = Config.DiscordLogs
    if not root or root.enabled ~= true then
        return false
    end
    local cat = root.categories and root.categories[category]
    if not cat or cat.enabled ~= true then
        return false
    end
    if type(cat.url) ~= 'string' or cat.url == '' then
        return false
    end
    return true
end

---@param category string key under Config.DiscordLogs.categories
---@param embed table Discord embed object (color can be omitted; taken from category config)
function FenixPasswordManagerDiscordLog(category, embed)
    local root = Config.DiscordLogs
    if not root or root.enabled ~= true then
        return
    end

    local cat = root.categories and root.categories[category]
    if not cat or cat.enabled ~= true then
        return
    end

    local url = cat.url
    if type(url) ~= 'string' or url == '' then
        return
    end

    if type(embed) ~= 'table' then
        return
    end

    embed.color = embed.color or cat.color
    embed.timestamp = embed.timestamp or utcIso8601()

    local body = webhookPayload(root.username, root.avatar_url, embed)
    PerformHttpRequest(url, function() end, 'POST', body, {
        ['Content-Type'] = 'application/json',
    })
end

function FenixPasswordManagerPlayerFields(source)
    local fields = {}
    local name = GetPlayerName(source)
    if type(name) == 'string' and name ~= '' then
        fields[#fields + 1] = {
            name = 'Player',
            value = discordEscape(truncate(name, 80)),
            inline = true,
        }
    end
    fields[#fields + 1] = {
        name = 'Server ID',
        value = tostring(source),
        inline = true,
    }

    local licenseShort = nil
    local dl = Config.DiscordLogs
    if dl and dl.logLicenseTail ~= false then
        for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
            if identifier:find('license:', 1, true) == 1 then
                licenseShort = identifier:sub(-8)
                break
            end
        end
        if licenseShort then
            fields[#fields + 1] = {
                name = 'License (final)',
                value = discordEscape(licenseShort),
                inline = true,
            }
        end
    end

    return fields
end
