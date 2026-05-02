Config = {}

Config.App = {
    identifier = 'passwordmanager',
    name = 'Password Manager',
    description = 'Save credentials for your installed phone apps.',
    developer = 'FenixDesign',
    defaultApp = false,
    size = 324,
    price = 0,
    landscape = false,
    icon = ('https://cfx-nui-%s/ui/icon.svg'):format(GetCurrentResourceName())
}

Config.Security = {
    enabled = true,
    useLbPhonePin = true,
    rememberForSeconds = 90,
    lockOnAppOpen = true,
    requireUnlockForEdit = true,
    requireUnlockToRevealPassword = true,
}

--[[
    Discord logs: each category has its own webhook URL.
    Set enabled = false or leave url empty to skip that category.
    Passwords and PIN attempts are never logged.
]]
Config.DiscordLogs = {
    enabled = true,
    username = 'Password Manager',
    avatar_url = '',
    --- Append last 8 chars of license to embeds (set false to omit).
    logLicenseTail = true,
    --- Include username on create/update logs (never logs password).
    logUsername = true,

    categories = {
        entry_created = {
            enabled = true,
            url = '',
            color = 5763719,
        },
        entry_updated = {
            enabled = true,
            url = '',
            color = 16776960,
        },
        entry_deleted = {
            enabled = true,
            url = '',
            color = 15158332,
        },
        unlock_success = {
            enabled = false,
            url = '',
            color = 3066993,
        },
        unlock_failed = {
            enabled = true,
            url = '',
            color = 15158332,
        },
    },
}
