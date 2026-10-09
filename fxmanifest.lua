fx_version 'cerulean'
game 'gta5'

author 'TL | Sammy'
description 'Advanced Drug Dealer System with Night Aggro & LB Phone'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client.lua'
}

server_scripts {
    'server.lua'
}

ui_page 'nui/index.html'

files {
    'nui/index.html',
    'nui/style.css',
    'nui/script.js'
}

dependencies {
    'qb-core',
    'ox_target',
    'ox_inventory',
    'ox_lib',
    'lb-tablet'
}