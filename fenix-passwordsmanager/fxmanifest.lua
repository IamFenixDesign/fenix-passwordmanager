fx_version 'cerulean'
game 'gta5'

lua54 'yes'

author 'FenixDesign'
description 'Password Manager app for LB Phone'
version '1.0.0'


files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
    'ui/icon.svg'
}

shared_script 'config.lua'

client_script 'client/cl_password.lua'

server_scripts {
    'server/sv_password.lua',
    'server/version.lua'
}

dependencies {
    'oxmysql',
    'lb-phone'
}
