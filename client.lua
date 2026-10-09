local QBCore = exports['qb-core']:GetCoreObject()
local ActiveNegotiations = {}
local isCarryingBodybag = false
local currentBodybag = nil
local PlayerData = {}
local ActiveBlips = {}
local TrackingBlips = {} -- New: For shared phone tracking

local disposalBlip = nil

function UpdateDisposalBlip()
    if not PlayerData or not PlayerData.job then return end
    
    local isAuthorized = false
    for _, job in ipairs(Config.BodybagJobs) do
        if PlayerData.job.name == job then
            isAuthorized = true
            break
        end
    end
    
    if isAuthorized then
        if not disposalBlip then
            disposalBlip = AddBlipForCoord(Config.DisposalLocation.x, Config.DisposalLocation.y, Config.DisposalLocation.z)
            SetBlipSprite(disposalBlip, 305)
            SetBlipColour(disposalBlip, 1)
            SetBlipScale(disposalBlip, 0.8)
            SetBlipAsShortRange(disposalBlip, true)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString("Gerichtsmedizin")
            EndTextCommandSetBlipName(disposalBlip)
        end
    else
        if disposalBlip then
            RemoveBlip(disposalBlip)
            disposalBlip = nil
        end
    end
end

function InitDisposalZone()
    exports.ox_target:addBoxZone({
        name = 'dispose_bodybag_zone',
        coords = Config.DisposalLocation,
        size = vector3(Config.DisposalRadius * 2, Config.DisposalRadius * 2, 4.0),
        rotation = 0,
        debug = false,
        options = {
            {
                name = 'dispose_bodybag_option',
                label = "Leichensack entsorgen",
                icon = "fas fa-trash-alt",
                groups = Config.BodybagJobs,
                onSelect = function()
                    DisposeBodybag(currentBodybag)
                end,
                canInteract = function()
                    return isCarryingBodybag and currentBodybag ~= nil
                end
            }
        }
    })
end

-- Update PlayerData on start
CreateThread(function()
    while QBCore.Functions.GetPlayerData().job == nil do
        Wait(100)
    end
    PlayerData = QBCore.Functions.GetPlayerData()
    UpdateDisposalBlip()
    InitDisposalZone()
    if PlayerData.job and PlayerData.job.name == Config.PoliceJob then
        TriggerServerEvent("qb-drugs:server:RequestAlerts")
    end
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    PlayerData = QBCore.Functions.GetPlayerData()
    UpdateDisposalBlip()
    if PlayerData.job and PlayerData.job.name == Config.PoliceJob then
        TriggerServerEvent("qb-drugs:server:RequestAlerts")
    end
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(JobInfo)
    PlayerData.job = JobInfo
    UpdateDisposalBlip()
    if PlayerData.job and PlayerData.job.name == Config.PoliceJob then
        TriggerServerEvent("qb-drugs:server:RequestAlerts")
    end
end)

-- TIME CHECK
function IsNightTime()
    local hour = GetClockHours()
    return (hour >= Config.NightStart or hour < Config.NightEnd)
end

function GetAggroChance(isPoliceAlone)
    if isPoliceAlone then
        return IsNightTime() and Config.NightPoliceAloneChance or Config.DayPoliceAloneChance
    else
        return IsNightTime() and Config.NightAggroChance or Config.DayAggroChance
    end
end

-- COUNT POLICE
function GetNearbyPoliceCount(coords)
    local count = 0
    local players = GetActivePlayers()
    for i = 1, #players do
        local player = players[i]
        local ped = GetPlayerPed(player)
        if #(GetEntityCoords(ped) - coords) <= Config.PoliceCheckRadius then
            -- We assume the player is a cop if they are in the police job
            -- This is a bit of a hack, but without server help it's hard.
            count = count + 1
        end
    end
    return count
end

-- TARGET INITIALIZATION
AddStateBagChangeHandler('isDrugDealer', nil, function(bagName, key, value, _unused, replicated)
    if not value then return end
    local entity = GetEntityFromStateBagName(bagName)
    if entity == 0 then return end
    
    -- Sync Model if it differs (Server-side CreatePed should handle it, but this is a fallback)
    local state = Entity(entity).state
    if state.dealerModel and GetEntityModel(entity) ~= state.dealerModel then
        RequestModel(state.dealerModel)
        while not HasModelLoaded(state.dealerModel) do Wait(0) end
        SetEntityModel(entity, state.dealerModel)
        SetModelAsNoLongerNeeded(state.dealerModel)
    end

    -- Apply Ped Properties for Dealers
    FreezeEntityPosition(entity, true)
    SetBlockingOfNonTemporaryEvents(entity, true)
    SetPedCanRagdoll(entity, false)
    SetEntityInvincible(entity, false)
end)

CreateThread(function()
    print("^3[DrugSelling] Initializing ox_target for drug dealers...^7")
    exports.ox_target:addGlobalPed({
        {
            name = 'sell_drugs',
            label = "Drogen verkaufen",
            icon = "fas fa-cannabis",
            distance = 2.5,
            onSelect = function(data)
                TriggerServerEvent("qb-drugs:server:StartNegotiation", NetworkGetNetworkIdFromEntity(data.entity))
            end,
            canInteract = function(entity)
                return Entity(entity).state.isDrugDealer and not IsEntityDead(entity) and (PlayerData and PlayerData.job and PlayerData.job.name ~= Config.PoliceJob)
            end
        },
        {
            name = 'pay_protection',
            label = "Schutzgeld zahlen",
            icon = "fas fa-shield-alt",
            distance = 2.5,
            onSelect = function(data)
                TriggerServerEvent("qb-drugs:server:PayProtection", NetworkGetNetworkIdFromEntity(data.entity))
            end,
            canInteract = function(entity)
                return Config.EnableProtection and Entity(entity).state.isDrugDealer and not IsEntityDead(entity) and (PlayerData and PlayerData.job and PlayerData.job.name ~= Config.PoliceJob)
            end
        },
        {
            name = 'put_in_bodybag',
            label = "In Leichensack packen",
            icon = "fas fa-box",
            distance = 2.5,
            canInteract = function(entity)
                if not Entity(entity).state.isDrugDealer then return false end
                if not IsEntityDead(entity) then return false end
                if not (PlayerData and PlayerData.job) then return false end
                local isAuthorized = false
                for _, job in ipairs(Config.BodybagJobs) do
                    if PlayerData.job.name == job then 
                        isAuthorized = true
                        break
                    end
                end
                return isAuthorized
            end,
            onSelect = function(data)
                PutInBodybag(data.entity)
            end,
        },
        {
            name = 'check_dealer',
            label = "Dealer kontrollieren",
            icon = "fas fa-user-shield",
            distance = 2.5,
            canInteract = function(entity)
                return Entity(entity).state.isDrugDealer and not IsEntityDead(entity) and (PlayerData and PlayerData.job and PlayerData.job.name == Config.PoliceJob)
            end,
            onSelect = function(data)
                HandlePoliceInteraction(data.entity)
            end,
        },
        {
            name = 'loot_dealer',
            label = "Dealer durchsuchen",
            icon = "fas fa-hands",
            distance = 2.5,
            canInteract = function(entity)
                local isPolice = PlayerData and PlayerData.job and PlayerData.job.name == Config.PoliceJob
                return Entity(entity).state.isDrugDealer and IsEntityDead(entity) and not isPolice
            end,
            onSelect = function(data)
                TriggerServerEvent("qb-drugs:server:LootDealer", NetworkGetNetworkIdFromEntity(data.entity))
            end,
        }
    })
end)

-- POLICE INTERACTION
function HandlePoliceInteraction(ped)
    TaskStartScenarioInPlace(PlayerPedId(), "CODE_HUMAN_MEDIC_TEND_TO_DEAD", 0, true)
    local success = lib.skillCheck(Config.InterrogationSkillCheck, {'w', 'a', 's', 'd'})
    ClearPedTasks(PlayerPedId())
    
    if not success then
        lib.notify({
            title = 'Kontrolle',
            description = "Die Kontrolle ist fehlgeschlagen! Der Dealer flieht!",
            type = 'error'
        })
        
        FreezeEntityPosition(ped, false)
        Wait(100)
        TaskSmartFleePed(ped, PlayerPedId(), 200.0, -1)
        SetPedAsNoLongerNeeded(ped)

        local dealerIdx = Entity(ped).state.dealerIdx
        if dealerIdx then
            TriggerServerEvent("qb-drugs:server:DealerDiedOrFled", dealerIdx)
        end
        return
    end

    local coords = GetEntityCoords(ped)
    local policeCount = GetNearbyPoliceCount(coords)
    local isAlone = policeCount <= 1
    local chance = GetAggroChance(isAlone)
    local dealerIdx = Entity(ped).state.dealerIdx

    if math.random(1,100) <= chance then
        FreezeEntityPosition(ped, false)
        Wait(100)
        local weapon = Config.NPCWeapons[math.random(#Config.NPCWeapons)]
        GiveWeaponToPed(ped, GetHashKey(weapon), 100, false, true)
        TaskCombatPed(ped, PlayerPedId(), 0, 16)

        -- Trigger server side removal
        if dealerIdx then
            TriggerServerEvent("qb-drugs:server:DealerDiedOrFled", dealerIdx)
        end

        -- Backup for Dealer
        if Config.EnableBackup and math.random(1, 100) <= Config.BackupChance then
            local amount = math.random(1, 2)
            for i = 1, amount do
                local offsetX = math.random(15, 25) * (math.random(0, 1) == 0 and 1 or -1)
                local offsetY = math.random(15, 25) * (math.random(0, 1) == 0 and 1 or -1)
                local offset = GetOffsetFromEntityInWorldCoords(ped, offsetX * 1.0, offsetY * 1.0, 0.0)
                
                local model = Config.DealerModels[math.random(#Config.DealerModels)]
                RequestModel(model)
                while not HasModelLoaded(model) do Wait(0) end
                local associate = CreatePed(0, model, offset.x, offset.y, offset.z, 0.0, true, true)
                local aWeapon = Config.NPCWeapons[math.random(#Config.NPCWeapons)]
                GiveWeaponToPed(associate, GetHashKey(aWeapon), 100, false, true)
                TaskCombatPed(associate, PlayerPedId(), 0, 16)
                SetPedAsNoLongerNeeded(associate)
            end
        end

        lib.notify({
            title = 'Dealer',
            description = "Der Dealer und seine Gang leisten Widerstand!",
            type = 'error'
        })
        return
    end

    if not PlayerData.job or not PlayerData.job.grade or PlayerData.job.grade.level < Config.MinInterrogationRank then
        lib.notify({
            title = 'Interrogation',
            description = "Du hast nicht genug Erfahrung, um diesen Dealer zum Reden zu bringen.",
            type = 'error'
        })
        return
    end

    TaskHandsUp(ped, 5000, PlayerPedId(), -1, true)
    Wait(5000)
    ClearPedTasks(ped)
    FreezeEntityPosition(ped, false)
    Wait(100)
    TaskSmartFleePed(ped, PlayerPedId(), 200.0, -1)

    TriggerServerEvent("qb-drugs:server:InterrogationSuccess", NetworkGetNetworkIdFromEntity(ped))

    -- Trigger server side removal
    if dealerIdx then
        TriggerServerEvent("qb-drugs:server:DealerDiedOrFled", dealerIdx)
    end

    lib.notify({
        title = 'Dealer',
        description = "Dealer flieht.",
        type = 'success'
    })
end

RegisterNetEvent("qb-drugs:client:ShowOffer", function(netId, price, amount)
    local confirm = lib.alertDialog({
        header = '🤝 **Preisverhandlung**',
        content = ('Der Dealer begutachtet deine Ware...\n\n' ..
                   '💰 Angebot: **$%s**  \n' ..
                   '📦 Menge: **%sx** Einheiten  \n\n' ..
                   'Akzeptierst du diesen Deal?'):format(price, amount),
        centered = true,
        cancel = true,
        labels = {
            confirm = 'Deal annehmen',
            cancel = 'Ablehnen'
        }
    })

    if confirm == 'confirm' then
        TriggerServerEvent("qb-drugs:server:CompleteSale", netId)
    else
        TriggerServerEvent("qb-drugs:server:DeclineOffer", netId)
    end
end)

RegisterNetEvent("qb-drugs:client:CheckDealers", function(activeDealers)
    local dealers = 0
    for _, data in ipairs(activeDealers) do
        dealers = dealers + 1
        local coords = data.coords
        local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
        SetBlipSprite(blip, 1)
        SetBlipColour(blip, 2)
        SetBlipScale(blip, 0.8)
        SetBlipAsShortRange(blip, false)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString("Aktiver Dealer")
        EndTextCommandSetBlipName(blip)
        
        CreateThread(function()
            Wait(30000)
            RemoveBlip(blip)
        end)
    end
    
    lib.notify({
        title = 'Admin',
        description = "Es wurden " .. dealers .. " aktive Dealer gefunden. Sie wurden für 30 Sekunden auf der Karte markiert.",
        type = 'inform'
    })
end)

RegisterNetEvent("qb-drugs:client:DealerFlee", function(netId)
    local ped = NetworkGetEntityFromNetworkId(netId)
    if DoesEntityExist(ped) then
        FreezeEntityPosition(ped, false)
        TaskSmartFleePed(ped, PlayerPedId(), 200.0, -1)
        SetPedAsNoLongerNeeded(ped)
    end
end)

RegisterNetEvent("qb-drugs:client:RespawnAllDealers", function()
    -- Server handles the actual delete and spawn now
    lib.notify({
        title = 'Admin',
        description = "Alle Dealer werden neu gespawnt.",
        type = 'success'
    })
end)

-- POLICE ALERT
RegisterNetEvent("qb-drugs:client:PoliceAlert", function(coords, alertId, customTime)
    local playerData = QBCore.Functions.GetPlayerData()
    if not (playerData and playerData.job and playerData.job.name == Config.PoliceJob) then return end
    
    -- Prevent duplicate blips for same alertId (especially during sync)
    if alertId and ActiveBlips[alertId] then return end

    local blip = AddBlipForRadius(coords.x, coords.y, coords.z, Config.AlertRadius)
    SetBlipColour(blip, 44) -- Dark Green
    SetBlipAlpha(blip, 120)
    SetBlipFlashes(blip, true)

    local marker = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(marker, 9) -- Suspicious activity icon
    SetBlipColour(marker, 44) -- Dark Green
    SetBlipScale(marker, 0.0)
    SetBlipFlashes(marker, true)
    /*BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Verdächtiger Handel")
    EndTextCommandSetBlipName(marker)*/

    if alertId then
        ActiveBlips[alertId] = { blip = blip, marker = marker }
    end

    -- Only notify if it's a NEW alert (no customTime provided)
    if not customTime then
        lib.notify({
            title = 'Polizei Alert',
            description = 'Verdächtiger Drogenhandel gemeldet',
            type = 'inform',
            icon = 'hand-holding-dollar'
        })
    end

    local waitTime = customTime or 300000 -- 5 minutes or remaining time
    Wait(waitTime)
    
    RemoveBlip(blip)
    RemoveBlip(marker)
    if alertId then
        ActiveBlips[alertId] = nil
    end
end)

-- NPC DEATH CHECK & DISPATCH & PLAYER ROBBERY
CreateThread(function()
    local robbedRecently = false
    while true do
        Wait(2000)
        local playerPed = PlayerPedId()
        local isPolice = (PlayerData and PlayerData.job and PlayerData.job.name == Config.PoliceJob)

        -- Check if player is dead and killed by dealer
        if IsEntityDead(playerPed) and not robbedRecently then
            local killer = GetPedSourceOfDeath(playerPed)
            if Entity(killer).state.isDrugDealer then
                robbedRecently = true
                TriggerServerEvent("qb-drugs:server:ProcessRobbery", NetworkGetNetworkIdFromEntity(killer))
                CreateThread(function()
                    Wait(60000)
                    robbedRecently = false
                end)
            end
        end

        local peds = GetGamePool('CPed')
        for _, ped in ipairs(peds) do
            if Entity(ped).state.isDrugDealer and IsEntityDead(ped) then
                local killer = GetPedSourceOfDeath(ped)
                if killer == playerPed and not isPolice then
                    local coords = GetEntityCoords(ped)
                    TriggerServerEvent("qb-drugs:server:SendDispatch", coords)
                end
                
                local dealerIdx = Entity(ped).state.dealerIdx
                if dealerIdx then
                    TriggerServerEvent("qb-drugs:server:DealerDiedOrFled", dealerIdx)
                end
            end
        end
    end
end)

-- ROBBERY SYSTEM
RegisterNetEvent("qb-drugs:client:RobberyStarted", function(netId)
    local ped = NetworkGetEntityFromNetworkId(netId)
    if not DoesEntityExist(ped) then return end

    local playerPed = PlayerPedId()
    local dealerIdx = Entity(ped).state.dealerIdx

    -- Dealer Aggro
    FreezeEntityPosition(ped, false)
    Wait(100)
    local weapon = Config.NPCWeapons[math.random(#Config.NPCWeapons)]
    GiveWeaponToPed(ped, GetHashKey(weapon), 100, false, true)
    TaskCombatPed(ped, playerPed, 0, 16)

    -- Trigger server side removal
    if dealerIdx then
        TriggerServerEvent("qb-drugs:server:DealerDiedOrFled", dealerIdx)
    end

    -- Spawn Associates
    local amount = math.random(Config.MinAssociates, Config.MaxAssociates)
    local associates = {}
    
    for i = 1, amount do
        local offsetX = math.random(15, 25) * (math.random(0, 1) == 0 and 1 or -1)
        local offsetY = math.random(15, 25) * (math.random(0, 1) == 0 and 1 or -1)
        local offset = GetOffsetFromEntityInWorldCoords(ped, offsetX * 1.0, offsetY * 1.0, 0.0)

        local model = Config.DealerModels[math.random(#Config.DealerModels)]
        RequestModel(model)
        while not HasModelLoaded(model) do Wait(0) end

        local associate = CreatePed(0, model, offset.x, offset.y, offset.z, 0.0, true, true)
        local aWeapon = Config.NPCWeapons[math.random(#Config.NPCWeapons)]
        GiveWeaponToPed(associate, GetHashKey(aWeapon), 100, false, true)
        TaskCombatPed(associate, playerPed, 0, 16)
        table.insert(associates, associate)
    end

    lib.notify({
        title = 'Überfall',
        description = "Der Dealer und seine Freunde rauben dich aus!",
        type = 'error'
    })

    Wait(10000)

    -- Process Robbery on Server
    TriggerServerEvent("qb-drugs:server:ProcessRobbery", netId)

    -- Wait and Flee
    Wait(Config.RobberyWait)
    
    FreezeEntityPosition(ped, false)
    Wait(100)
    TaskSmartFleePed(ped, playerPed, 200.0, -1)
    
    for _, associate in ipairs(associates) do
        TaskSmartFleePed(associate, playerPed, 200.0, -1)
        SetPedAsNoLongerNeeded(associate)
    end
end)

-- BODYBAG FUNCTIONS
function PutInBodybag(ped)
    local coords = GetEntityCoords(ped)
    
    if lib.progressBar({
        duration = 5000,
        label = 'Packe NPC in Leichensack...',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, mouse = false, combat = true },
        anim = { dict = 'amb@medic@standing@tendtodead@idle_a', clip = 'idle_a' },
    }) then
        DeleteEntity(ped)
        
        local model = Config.BodybagModel
        RequestModel(model)
        while not HasModelLoaded(model) do Wait(0) end
        
        local bag = CreateObject(model, coords.x, coords.y, coords.z, true, true, true)
        PlaceObjectOnGroundProperly(bag)
        
        exports.ox_target:addLocalEntity(bag, {
            {
                name = 'carry_bodybag',
                label = "Aufheben",
                icon = "fas fa-hand-holding",
                distance = 2.0,
                canInteract = function() return not isCarryingBodybag end,
                onSelect = function(data)
                    CarryBodybag(data.entity)
                end,
            }
        })
    end
end

function CarryBodybag(bag)
    local playerPed = PlayerPedId()
    
    RequestAnimDict("anim@heists@box_carry@")
    while not HasAnimDictLoaded("anim@heists@box_carry@") do Wait(0) end
    TaskPlayAnim(playerPed, "anim@heists@box_carry@", "idle", 8.0, 8.0, -1, 50, 0, false, false, false)
    
    AttachEntityToEntity(bag, playerPed, GetPedBoneIndex(playerPed, 28422), 0.0, -0.3, -0.2, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
    
    isCarryingBodybag = true
    currentBodybag = bag
    
    lib.notify({ title = 'Leichensack', description = "Du trägst den Leichensack. Nutze Target auf ein Fahrzeug zum Beladen.", type = 'inform' })
    
    -- Option to Drop or Load
    exports.ox_target:addGlobalVehicle({
        {
            name = 'load_bodybag_veh',
            label = "Leichensack einladen",
            icon = "fas fa-truck-loading",
            distance = 2.5,
            canInteract = function() return isCarryingBodybag end,
            onSelect = function(data)
                LoadInVehicle(data.entity, currentBodybag)
            end,
        }
    })

    exports.ox_target:addLocalEntity(playerPed, {
        {
            name = 'drop_bodybag',
            label = "Leichensack ablegen",
            icon = "fas fa-hand-rock",
            distance = 2.0,
            canInteract = function() return isCarryingBodybag end,
            onSelect = function()
                DropBodybag()
            end,
        }
    })
end

function DropBodybag()
    if not isCarryingBodybag or not currentBodybag then return end
    
    local playerPed = PlayerPedId()
    DetachEntity(currentBodybag, true, true)
    PlaceObjectOnGroundProperly(currentBodybag)
    ClearPedTasks(playerPed)
    
    exports.ox_target:removeGlobalVehicle('load_bodybag_veh')
    exports.ox_target:removeLocalEntity(playerPed, 'drop_bodybag')

    isCarryingBodybag = false
    currentBodybag = nil
end

function LoadInVehicle(vehicle, bag)
    local playerPed = PlayerPedId()
    
    if not vehicle then return end
    
    if lib.progressBar({
        duration = 3000,
        label = 'Lade Leichensack ein...',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, mouse = false, combat = true },
    }) then
        DetachEntity(bag, true, true)
        SetEntityVisible(bag, false, false)
        -- Attach to vehicle, usually trunk area
        AttachEntityToEntity(bag, vehicle, 0, 0.0, -2.5, 0.5, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
        
        exports.ox_target:removeGlobalVehicle('load_bodybag_veh')
        exports.ox_target:removeLocalEntity(playerPed, 'drop_bodybag')

        isCarryingBodybag = false
        currentBodybag = nil
        ClearPedTasks(playerPed)
        
        lib.notify({ title = 'Leichensack', description = "Leichensack im Fahrzeug verstaut.", type = 'success' })
        
        -- Add target to vehicle to unload
        exports.ox_target:addLocalEntity(vehicle, {
            {
                name = 'unload_bodybag',
                label = "Leichensack ausladen",
                icon = "fas fa-truck-loading",
                distance = 2.5,
                onSelect = function()
                    UnloadFromVehicle(vehicle, bag)
                end,
            }
        })
    end
end

function UnloadFromVehicle(vehicle, bag)
    local playerPed = PlayerPedId()
    
    if lib.progressBar({
        duration = 3000,
        label = 'Lade Leichensack aus...',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, mouse = false, combat = true },
    }) then
        SetEntityVisible(bag, true, false)
        DetachEntity(bag, true, true)
        PlaceObjectOnGroundProperly(bag)
        
        exports.ox_target:removeLocalEntity(vehicle, 'unload_bodybag')
        lib.notify({ title = 'Leichensack', description = "Leichensack ausgeladen.", type = 'success' })
    end
end

function DisposeBodybag(bag)
    if lib.progressBar({
        duration = 4000,
        label = 'Entsorge Leichensack...',
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, mouse = false, combat = true },
    }) then
        if isCarryingBodybag and currentBodybag == bag then
            DropBodybag()
        end
        DeleteEntity(bag)
        lib.notify({ title = 'Leichensack', description = "Leichensack erfolgreich entsorgt.", type = 'success' })
    end
end

-- RESPAWN LOGIC
function HandleDealerRemoval(index)
    local dealer = spawnedDealers[index]
    if not dealer or not dealer.ped then return end

    local netId = NetworkGetNetworkIdFromEntity(dealer.ped)
    TriggerServerEvent("qb-drugs:server:ClearDealerData", netId)

    if not dealer.spawnIdx then
        table.remove(spawnedDealers, index)
        return
    end

    local spawnIdx = dealer.spawnIdx
    table.remove(spawnedDealers, index)

    CreateThread(function()
        Wait(Config.DealerRespawnTime)
        usedSpawns[spawnIdx] = nil
        local amount = #spawnedDealers
        if amount < Config.MaxDealers then
            SpawnDealer(Config.PossibleDealerSpawns[spawnIdx], spawnIdx)
            usedSpawns[spawnIdx] = true
        end
    end)
end

-- PHONE TRACKING SYSTEM
RegisterCommand("trackphone", function()
    if not PlayerData or not PlayerData.job or PlayerData.job.name ~= Config.PoliceJob then
        return
    end

    if PlayerData.job.grade.level < 4 then
        lib.notify({ title = 'System', description = "Zugriff verweigert. Rang 4+ benötigt.", type = 'error' })
        return
    end

    QBCore.Functions.TriggerCallback('qb-drugs:server:GetTrackingData', function(data)
        SetNuiFocus(true, true)
        SendNUIMessage({
            action = 'open',
            rank = PlayerData.job.grade.level,
            activeTracksCount = data.activeTracksCount,
            pendingCount = data.pendingCount,
            activities = data.activities,
            permits = data.permits,
            pendingPermits = data.pendingPermits
        })
    end)
end)

RegisterNUICallback('close', function(_, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('submitRequest', function(data, cb)
    TriggerServerEvent('qb-drugs:server:SubmitTrackingRequest', data.number, data.reason)
    cb('ok')
end)

RegisterNUICallback('approveRequest', function(data, cb)
    TriggerServerEvent('qb-drugs:server:ApproveTrackingRequest', data.id)
    cb('ok')
end)

RegisterNUICallback('denyRequest', function(data, cb)
    TriggerServerEvent('qb-drugs:server:DenyTrackingRequest', data.id)
    cb('ok')
end)

RegisterNUICallback('revokePermit', function(data, cb)
    TriggerServerEvent('qb-drugs:server:RevokeTrackingPermit', data.number)
    cb('ok')
end)

RegisterNUICallback('startTracking', function(data, cb)
    TriggerServerEvent('qb-drugs:server:StartPhoneTracking', data.number)
    cb('ok')
end)

-- SHARED TRACKING BLIPS
RegisterNetEvent('qb-drugs:client:UpdateTrackingBlip', function(number, coords)
    if not PlayerData or not PlayerData.job or PlayerData.job.name ~= Config.PoliceJob then return end

    if TrackingBlips[number] then
        RemoveBlip(TrackingBlips[number])
    end

    -- Random center within 200m of the player
    local angle = math.random() * 2 * math.pi
    local dist = math.random(0, 200)
    local offsetX = math.cos(angle) * dist
    local offsetY = math.sin(angle) * dist

    -- Radius circle centered at a random point inside the 200m area
    local blip = AddBlipForRadius(coords.x + offsetX, coords.y + offsetY, coords.z, 200.0)
    SetBlipHighDetail(blip, true)
    SetBlipColour(blip, 1) -- Red
    SetBlipAlpha(blip, 128)

    TrackingBlips[number] = blip

    -- Auto remove after a while if no update comes (fallback)
    SetTimeout(70000, function()
        if TrackingBlips[number] == blip then
            RemoveBlip(blip)
            TrackingBlips[number] = nil
        end
    end)
end)

RegisterNetEvent('qb-drugs:client:StopTrackingBlip', function(number)
    if TrackingBlips[number] then
        RemoveBlip(TrackingBlips[number])
        TrackingBlips[number] = nil
    end
end)

RegisterNetEvent('qb-drugs:client:RefreshTrackingUI', function()
    if not PlayerData or not PlayerData.job or PlayerData.job.name ~= Config.PoliceJob then return end
    
    QBCore.Functions.TriggerCallback('qb-drugs:server:GetTrackingData', function(data)
        SendNUIMessage({
            action = 'update',
            activeTracksCount = data.activeTracksCount,
            pendingCount = data.pendingCount,
            activities = data.activities,
            permits = data.permits,
            pendingPermits = data.pendingPermits
        })
    end)
end)
