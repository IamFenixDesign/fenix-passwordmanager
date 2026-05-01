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
