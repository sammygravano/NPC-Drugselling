local QBCore = exports['qb-core']:GetCoreObject()
local ActiveDealers = {}
local DealerPeds = {}
local PendingOffers = {}
local UsedSpawnIndices = {}
local DealerStolenItems = {}
local LootedPeds = {}
local FailedNegotiations = {} -- Tracks failures per [netId][src]
local ProtectedPlayers = {} -- Tracks protection expiry per citizenid
local ActiveAlerts = {} -- Tracks active police alerts
local TrackingPermits = {} -- Stores permits: {id, status, number, requester, reason, expiry}
local ActiveTrackings = {} -- Stores live trackings: {number, startTime}

-- SEED RANDOM
math.randomseed(os.time())

-- SERVER SIDE SPAWNING
function SpawnDealer(coords, spawnIdx)
    local model = Config.DealerModels[math.random(#Config.DealerModels)]
    
    -- PedType 4 is PED_TYPE_CIVMALE
    local ped = CreatePed(4, model, coords.x, coords.y, coords.z, coords.w, true, true)
    
    -- Wait for entity to exist
    local timeout = 0
    while not DoesEntityExist(ped) and timeout < 50 do
        Wait(50)
        timeout = timeout + 1
    end

    if DoesEntityExist(ped) then
        -- Set state for client-side syncing
        Entity(ped).state.isDrugDealer = true
        Entity(ped).state.dealerIdx = spawnIdx
        Entity(ped).state.dealerModel = model
        
        DealerPeds[spawnIdx] = {
            ped = ped,
            spawnIdx = spawnIdx
        }
        print("^2[DrugSelling] Dealer spawned at index: " .. spawnIdx .. " | Model: " .. tostring(model) .. " | Entity: " .. ped .. "^7")
        return ped
    else
        print("^1[DrugSelling] FAILED to spawn dealer at index: " .. spawnIdx .. " | Model: " .. tostring(model) .. "^7")
    end
end

function SpawnRandomDealers()
    print("^3[DrugSelling] Global cleanup and spawning random dealers...^7")
    
    -- Global Cleanup: Find any ped with the state bag and delete it to prevent ghosts after restarts
    local allPeds = GetAllPeds()
    local deletedCount = 0
    for _, ped in ipairs(allPeds) do
        if Entity(ped).state.isDrugDealer then
            DeleteEntity(ped)
            deletedCount = deletedCount + 1
        end
    end
    if deletedCount > 0 then
        print("^3[DrugSelling] Cleaned up " .. deletedCount .. " old dealer peds.^7")
    end

    DealerPeds = {}
    UsedSpawnIndices = {}
    DealerStolenItems = {}
    LootedPeds = {}

    local amount = math.random(Config.MinDealers, Config.MaxDealers)
    local totalPossible = #Config.PossibleDealerSpawns
    local availableIndices = {}
    for i = 1, totalPossible do table.insert(availableIndices, i) end

    -- Shuffle available indices for better distribution
    for i = #availableIndices, 2, -1 do
        local j = math.random(i)
        availableIndices[i], availableIndices[j] = availableIndices[j], availableIndices[i]
    end

    local spawnedCount = 0
    for i = 1, amount do
        local idx = availableIndices[i]
        if idx then
            local ped = SpawnDealer(Config.PossibleDealerSpawns[idx], idx)
            if ped then
                UsedSpawnIndices[idx] = true
                spawnedCount = spawnedCount + 1
            end
        end
    end
    print("^3[DrugSelling] Successfully spawned " .. spawnedCount .. " dealers at different locations.^7")
end

-- Initialize on Start
CreateThread(function()
    print("^3[DrugSelling] Resource starting, waiting for initialization...^7")
    Wait(2000)
    SpawnRandomDealers()
end)

QBCore.Commands.Add("spawndealers", "Manuelles Spawning der Dealer (God)", {}, false, function(source)
    CreateThread(function()
        SpawnRandomDealers()
    end)
    TriggerClientEvent("ox_lib:notify", source, {
        title = 'Admin',
        description = "Dealer-Spawning wurde manuell getriggert.",
        type = 'success'
    })
end, "god")

QBCore.Commands.Add("checkdealers", "Zeigt alle aktiven Dealer an (God)", {}, false, function(source)
    local activeDealers = {}
    for idx, data in pairs(DealerPeds) do
        if DoesEntityExist(data.ped) then
            local coords = GetEntityCoords(data.ped)
            table.insert(activeDealers, {
                coords = coords
            })
        end
    end
    TriggerClientEvent("qb-drugs:client:CheckDealers", source, activeDealers)
end, "god")

QBCore.Commands.Add("respawndealers", "Spawnt alle Dealer direkt neu (God)", {}, false, function(source)
    CreateThread(function()
        SpawnRandomDealers()
    end)
    TriggerClientEvent("ox_lib:notify", source, {
        title = 'Admin',
        description = "Alle Dealer wurden global neu gespawnt.",
        type = 'success'
    })
end, "god")

-- Respawn Logic for specific index
RegisterNetEvent("qb-drugs:server:DealerDiedOrFled", function(spawnIdx)
    if not spawnIdx or not DealerPeds[spawnIdx] then return end
    
    local data = DealerPeds[spawnIdx]
    -- We keep isDrugDealer = true even if dead, so the bodybag target stays active.
    -- It will be cleaned up by the global cleanup or when the bodybag is disposed.

    DealerPeds[spawnIdx] = nil
    UsedSpawnIndices[spawnIdx] = nil

    CreateThread(function()
        Wait(Config.DealerRespawnTime)
        local count = 0
        for _ in pairs(DealerPeds) do count = count + 1 end
        
        if count < Config.MaxDealers then
            SpawnDealer(Config.PossibleDealerSpawns[spawnIdx], spawnIdx)
            UsedSpawnIndices[spawnIdx] = true
        end
    end)
end)

RegisterNetEvent("qb-drugs:server:StartNegotiation", function(netId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    -- Check if player already reached negotiation limit with this dealer
    if FailedNegotiations[netId] and (FailedNegotiations[netId][src] or 0) >= 3 then
        TriggerClientEvent("ox_lib:notify", src, {
            title = 'Dealer',
            description = "Der Dealer will nicht mehr mit dir reden.",
            type = 'error'
        })
        return
    end

    local hour = os.date("*t").hour
    local isNight = (hour >= Config.NightStart or hour < Config.NightEnd)
    local currentRobberyChance = isNight and Config.NightRobberyChance or Config.RobberyChance

    -- Protection Check
    local isProtected = false
    if ProtectedPlayers[Player.PlayerData.citizenid] then
        if os.time() < ProtectedPlayers[Player.PlayerData.citizenid] then
            isProtected = true
        else
            ProtectedPlayers[Player.PlayerData.citizenid] = nil
        end
    end

    local totalAmount = 0
    local totalPrice = 0
    local drugList = {}

    for drug, data in pairs(Config.Drugs) do
        local count = exports.ox_inventory:Search(src, 'count', drug)
        if count > 0 then
            totalAmount = totalAmount + count
            local itemPrice = math.random(data.minPrice, data.maxPrice)
            if isNight then
                itemPrice = math.floor(itemPrice * Config.NightPriceMultiplier)
            end
            totalPrice = totalPrice + (itemPrice * count)
            table.insert(drugList, { drug = drug, count = count })
        end
    end

    if totalAmount > 0 then
        -- Police Alert on Interaction
        if math.random(1, 100) <= Config.PoliceAlertChance then
            local dealerPed = NetworkGetEntityFromNetworkId(netId)
            if DoesEntityExist(dealerPed) then
                local coords = GetEntityCoords(dealerPed)
                -- Randomize coords slightly for "approximate" location
                local radius = Config.AlertRadius / 2
                local randomizedCoords = vector3(
                    coords.x + (math.random() * radius * 2 - radius),
                    coords.y + (math.random() * radius * 2 - radius),
                    coords.z
                )
                TriggerEvent("qb-drugs:server:CallPolice", randomizedCoords)
            end
        end

        if not isProtected and math.random(1, 100) <= currentRobberyChance then
            TriggerClientEvent("qb-drugs:client:RobberyStarted", src, netId)
            return
        end

        PendingOffers[src] = {
            netId = netId,
            price = totalPrice,
            items = drugList
        }

        TriggerClientEvent("qb-drugs:client:ShowOffer", src, netId, totalPrice, totalAmount)
        return
    end

    TriggerClientEvent("ox_lib:notify", src, {
        title = 'Dealer',
        description = "Keine Drogen dabei",
        type = 'error'
    })
end)

RegisterNetEvent("qb-drugs:server:CompleteSale", function(netId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local offer = PendingOffers[src]
    if not offer or offer.netId ~= netId then return end

    local soldSomething = false
    for _, item in ipairs(offer.items) do
        local count = exports.ox_inventory:Search(src, 'count', item.drug)
        if count >= item.count then
            exports.ox_inventory:RemoveItem(src, item.drug, item.count)
            soldSomething = true
        else
            -- If player dropped items in between, adjust price? 
            -- For simplicity, let's just sell what's left or cancel.
            -- Let's stick to selling what was offered if still present.
            if count > 0 then
                exports.ox_inventory:RemoveItem(src, item.drug, count)
                soldSomething = true
            end
        end
    end

    if not soldSomething then 
        PendingOffers[src] = nil
        return 
    end

    exports.ox_inventory:AddItem(src, "money", offer.price)

    local phone = nil
    local foundNumbers = {}
    
    -- Check all phone items in the player's inventory
    local phoneItems = exports.ox_inventory:Search(src, 1, 'phone')
    if type(phoneItems) == 'table' then
        for _, item in pairs(phoneItems) do
            if item.metadata then
                -- 17mov usually stores it as 'phoneNumber' or 'number', lb-phone as 'lbPhoneNumber'
                local num = item.metadata.phoneNumber or item.metadata.number or item.metadata.phone_number or item.metadata.lbPhoneNumber
                if num then
                    table.insert(foundNumbers, tostring(num))
                end
            end
        end
    end

    if #foundNumbers > 0 then
        -- Join all numbers if they had multiple phones
        phone = table.concat(foundNumbers, ", ")
    else
        -- Use 17 Movement Phone Export directly
        pcall(function()
            phone = exports["17mov_Phone"]:GetNumberFromPlayer(src)
        end)
        
        -- Fallback: Try lb-phone Export
        if not phone then
            pcall(function()
                phone = exports["lb-phone"]:GetEquippedPhoneNumber(src)
            end)
        end

        -- Fallback 2: QBCore default
        if not phone then
            phone = Player.PlayerData.charinfo.phone
        end
        phone = tostring(phone)
    end

    ActiveDealers[netId] = {
        citizenid = Player.PlayerData.citizenid,
        phone = phone
    }

    PendingOffers[src] = nil

    TriggerClientEvent("ox_lib:notify", src, {
        title = 'Dealer',
        description = "Verkauf abgeschlossen",
        type = 'success'
    })

    -- Reset failures on successful sale
    if FailedNegotiations[netId] then
        FailedNegotiations[netId][src] = nil
    end
end)

RegisterNetEvent("qb-drugs:server:LootDealer", function(netId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    if Player.PlayerData.job and Player.PlayerData.job.name == Config.PoliceJob then
        TriggerClientEvent("ox_lib:notify", src, {
            title = 'Dealer',
            description = "Als Polizist darfst du keine Dealer durchsuchen.",
            type = 'error'
        })
        return
    end

    if LootedPeds[netId] then
        TriggerClientEvent("ox_lib:notify", src, {
            title = 'Dealer',
            description = "Dieser Dealer wurde bereits durchsucht.",
            type = 'error'
        })
        return
    end

    local stolen = DealerStolenItems[netId]
    local foundAny = false

    -- 1. Handle Stolen Items
    if stolen then
        if math.random(1, 100) <= Config.LootChance then
            if stolen.money > 0 then
                local amount = math.floor(stolen.money * Config.LootReturnPercentage)
                if amount > 0 then
                    exports.ox_inventory:AddItem(src, 'money', amount)
                    foundAny = true
                end
            end

            for _, data in ipairs(stolen.items) do
                local amount = math.floor(data.amount * Config.LootReturnPercentage)
                if amount > 0 then
                    exports.ox_inventory:AddItem(src, data.item, amount)
                    foundAny = true
                end
            end
        end
        DealerStolenItems[netId] = nil
    end

    -- 2. Handle Extra Loot
    if math.random(1, 100) <= Config.ExtraLootChance then
        for _, loot in ipairs(Config.ExtraLoot) do
            if math.random(1, 100) <= loot.chance then
                local amount = math.random(loot.min, loot.max)
                if amount > 0 then
                    exports.ox_inventory:AddItem(src, loot.item, amount)
                    foundAny = true
                end
            end
        end
    end

    LootedPeds[netId] = true

    if foundAny then
        TriggerClientEvent("ox_lib:notify", src, {
            title = 'Dealer',
            description = "Du hast den Dealer durchsucht und etwas Brauchbares gefunden!",
            type = 'success'
        })
    else
        TriggerClientEvent("ox_lib:notify", src, {
            title = 'Dealer',
            description = "Du hast nichts Brauchbares gefunden.",
            type = 'inform'
        })
    end
end)

RegisterNetEvent("qb-drugs:server:ProcessRobbery", function(dealerNetId)
    local src = source
    local cash = exports.ox_inventory:Search(src, 'count', 'money')
    local stolen = { items = {}, money = 0 }
    
    if cash > 0 then
        local amount = math.floor(cash / 2)
        exports.ox_inventory:RemoveItem(src, 'money', amount)
        stolen.money = amount
    end

    for drug, _ in pairs(Config.Drugs) do
        local count = exports.ox_inventory:Search(src, 'count', drug)
        if count > 0 then
            exports.ox_inventory:RemoveItem(src, drug, count)
            table.insert(stolen.items, { item = drug, amount = count })
        end
    end

    if dealerNetId then
        DealerStolenItems[dealerNetId] = stolen
    end

    TriggerClientEvent("ox_lib:notify", src, {
        title = 'Überfall',
        description = "Du wurdest ausgeraubt! Die Hälfte deines Geldes und alle Drogen sind weg!",
        type = 'error',
        duration = 10000
    })
end)

RegisterNetEvent("qb-drugs:server:CallPolice", function(coords)
    local alertId = os.time() .. math.random(111, 999)
    ActiveAlerts[alertId] = {
        coords = coords,
        time = os.time()
    }
    
    TriggerClientEvent("qb-drugs:client:PoliceAlert", -1, coords, alertId)
    
    -- Cleanup alert after 5 minutes on server
    CreateThread(function()
        Wait(300000)
        ActiveAlerts[alertId] = nil
    end)
end)

RegisterNetEvent("qb-drugs:server:RequestAlerts", function()
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or Player.PlayerData.job.name ~= Config.PoliceJob then return end
    
    local currentTime = os.time()
    for alertId, data in pairs(ActiveAlerts) do
        local timePassed = currentTime - data.time
        if timePassed < 300 then
            local remainingTime = 300000 - (timePassed * 1000)
            TriggerClientEvent("qb-drugs:client:PoliceAlert", src, data.coords, alertId, remainingTime)
        end
    end
end)

/*RegisterNetEvent("qb-drugs:server:SendDispatch", function(coords)
    exports["lb-tablet"]:AddDispatch({
        priority = 'high',
        code = '10-31',
        title = "Schüsse auf Person / Dealer tot",
        description = "Ein mutmaßlicher Drogendealer wurde erschossen!",
        location = {
            label = "Drogen-Spot",
            coords = { x = coords.x, y = coords.y }
        },
        time = 60,
        job = 'police',
        blip = {
            sprite = 310,
            color = 1,
            size = 1.0,
            label = "Dealer tot"
        }
    })
end)*/

RegisterNetEvent("qb-drugs:server:ClearDealerData", function(netId)
    ActiveDealers[netId] = nil
end)

RegisterNetEvent("qb-drugs:server:InterrogationSuccess", function(netId)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local dealer = ActiveDealers[netId]

    if not dealer then
        TriggerClientEvent("ox_lib:notify", src, {
            title = 'Interrogation',
            description = "Dieser Dealer scheint keine aktuellen Informationen zu haben.",
            type = 'error'
        })
        return
    end

    local phone = dealer.phone
    local roll = math.random(1,3)

    if roll == 1 then
        TriggerClientEvent("ox_lib:notify", src, {
            title = 'Interrogation',
            description = "Dealer schweigt.",
            type = 'error'
        })
    elseif roll == 2 then
        local phoneStr = tostring(phone)
        local len = #phoneStr
        local indices = {}
        for i = 1, len do table.insert(indices, i) end
        
        -- Shuffle indices
        for i = len, 2, -1 do
            local j = math.random(i)
            indices[i], indices[j] = indices[j], indices[i]
        end
        
        local visible = {}
        local count = math.min(5, len)
        for i = 1, count do
            visible[indices[i]] = true
        end
        
        local partial = ""
        for i = 1, len do
            if visible[i] then
                partial = partial .. string.sub(phoneStr, i, i)
            else
                partial = partial .. "*"
            end
        end

        TriggerClientEvent("ox_lib:notify", src, {
            title = 'Interrogation',
            description = "Teilweise Nummer: "..partial,
            type = 'inform',
            duration = 20000
        })
    else
        TriggerClientEvent("ox_lib:notify", src, {
            title = 'Interrogation',
            description = "Komplette Nummer: "..phone,
            type = 'success',
            duration = 20000
        })
    end
end)

RegisterNetEvent("qb-drugs:server:DeclineOffer", function(netId)
    local src = source
    if not FailedNegotiations[netId] then FailedNegotiations[netId] = {} end
    FailedNegotiations[netId][src] = (FailedNegotiations[netId][src] or 0) + 1

    if FailedNegotiations[netId][src] >= 3 then
        local ped = NetworkGetEntityFromNetworkId(netId)
        if DoesEntityExist(ped) then
            local dealerIdx = Entity(ped).state.dealerIdx
            if dealerIdx then
                TriggerClientEvent("ox_lib:notify", src, {
                    title = 'Dealer',
                    description = "Der Dealer hat keine Lust mehr auf deine Verhandlungen und verschwindet!",
                    type = 'error'
                })
                -- Make him flee on client side
                TriggerClientEvent("qb-drugs:client:DealerFlee", -1, netId)
                -- Process removal on server
                TriggerEvent("qb-drugs:server:DealerDiedOrFled", dealerIdx)
            end
        end
        FailedNegotiations[netId][src] = nil
    else
        TriggerClientEvent("ox_lib:notify", src, {
            title = 'Dealer',
            description = ("Der Dealer ist unzufrieden. (%s/3 Versuche)"):format(FailedNegotiations[netId][src]),
            type = 'inform'
        })
    end
    
    PendingOffers[src] = nil
end)

-- PHONE TRACKING SYSTEM
local function GetPlayerByPhone(number)
    local targetSource = exports["17mov_Phone"]:GetPlayerSrcFromActiveNumber(number)
    if targetSource and targetSource > 0 then
        return QBCore.Functions.GetPlayer(targetSource)
    end
    
    -- Fallback: Loop primary check (for safety)
    local players = QBCore.Functions.GetQBPlayers()
    for _, v in pairs(players) do
        if v.PlayerData.charinfo.phone == number then
            return v
        end
    end
    
    return nil
end

QBCore.Functions.CreateCallback('qb-drugs:server:GetTrackingData', function(source, cb)
    local activeTracksCount = 0
    for _ in pairs(ActiveTrackings) do activeTracksCount = activeTracksCount + 1 end

    local pendingCount = 0
    local pendingPermits = {}
    local permits = {}
    local activities = {}

    for id, p in pairs(TrackingPermits) do
        if p.status == 'pending' then
            pendingCount = pendingCount + 1
            table.insert(pendingPermits, p)
        end
        
        table.insert(permits, {
            number = p.number,
            expiry = p.expiry and os.date("%H:%M", p.expiry) or '---',
            status = p.status,
            statusLabel = (p.status == 'approved' and 'Genehmigt' or (p.status == 'denied' and 'Abgelehnt' or 'Ausstehend'))
        })

        table.insert(activities, {
            number = p.number,
            time = os.date("%H:%M", p.createdAt),
            status = p.status,
            statusLabel = (p.status == 'approved' and 'Genehmigt' or (p.status == 'denied' and 'Abgelehnt' or 'Ausstehend'))
        })
    end

    cb({
        activeTracksCount = activeTracksCount,
        pendingCount = pendingCount,
        activities = activities,
        permits = permits,
        pendingPermits = pendingPermits
    })
end)

RegisterNetEvent('qb-drugs:server:SubmitTrackingRequest', function(number, reason)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or Player.PlayerData.job.name ~= Config.PoliceJob or Player.PlayerData.job.grade.level < 4 then return end

    local id = tostring(os.time() .. math.random(100, 999))
    TrackingPermits[id] = {
        id = id,
        number = number,
        requester = Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname,
        reason = reason,
        status = 'pending',
        createdAt = os.time()
    }

    TriggerClientEvent('qb-drugs:client:RefreshTrackingUI', -1)
    TriggerClientEvent('ox_lib:notify', src, { title = 'System', description = "Beschlussantrag eingereicht.", type = 'success' })
end)

RegisterNetEvent('qb-drugs:server:ApproveTrackingRequest', function(id)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or Player.PlayerData.job.name ~= Config.PoliceJob or Player.PlayerData.job.grade.level < 8 then return end

    if TrackingPermits[id] then
        TrackingPermits[id].status = 'approved'
        TrackingPermits[id].expiry = os.time() + 3600 -- 1 Hour
        TriggerClientEvent('qb-drugs:client:RefreshTrackingUI', -1)
        TriggerClientEvent('ox_lib:notify', src, { title = 'System', description = "Beschluss genehmigt.", type = 'success' })
    end
end)

RegisterNetEvent('qb-drugs:server:DenyTrackingRequest', function(id)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or Player.PlayerData.job.name ~= Config.PoliceJob or Player.PlayerData.job.grade.level < 8 then return end

    if TrackingPermits[id] then
        TrackingPermits[id].status = 'denied'
        TriggerClientEvent('qb-drugs:client:RefreshTrackingUI', -1)
        TriggerClientEvent('ox_lib:notify', src, { title = 'System', description = "Beschluss abgelehnt.", type = 'error' })
    end
end)

RegisterNetEvent('qb-drugs:server:RevokeTrackingPermit', function(number)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or Player.PlayerData.job.name ~= Config.PoliceJob or Player.PlayerData.job.grade.level < 8 then return end

    local revoked = false
    -- Revoke approved permits for this number
    for id, p in pairs(TrackingPermits) do
        if p.number == number and p.status == 'approved' then
            TrackingPermits[id].status = 'revoked'
            TrackingPermits[id].expiry = 0
            revoked = true
        end
    end

    if revoked then
        -- Stop active tracking if it exists
        if ActiveTrackings[number] then
            ActiveTrackings[number] = nil
            TriggerClientEvent('qb-drugs:client:StopTrackingBlip', -1, number)
        end
        TriggerClientEvent('qb-drugs:client:RefreshTrackingUI', -1)
        TriggerClientEvent('ox_lib:notify', src, { title = 'System', description = "Beschluss wurde widerrufen.", type = 'error' })
    end
end)

RegisterNetEvent('qb-drugs:server:StartPhoneTracking', function(number)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player or Player.PlayerData.job.name ~= Config.PoliceJob or Player.PlayerData.job.grade.level < 4 then return end

    -- Check for approved permit
    local hasPermit = false
    for _, p in pairs(TrackingPermits) do
        if p.number == number and p.status == 'approved' and p.expiry > os.time() then
            hasPermit = true
            break
        end
    end

    if not hasPermit then
        TriggerClientEvent('ox_lib:notify', src, { title = 'System', description = "Kein gültiger Beschluss für diese Nummer.", type = 'error' })
        return
    end

    -- Check if number is active/player is online
    local targetSource = exports["17mov_Phone"]:GetPlayerSrcFromActiveNumber(number)
    if not targetSource or targetSource <= 0 then
        TriggerClientEvent('ox_lib:notify', src, { title = 'System', description = "Die angegebene Nummer ist nicht korrekt/aktiv", type = 'error' })
        return
    end

    ActiveTrackings[number] = {
        number = number,
        startTime = os.time()
    }

    TriggerClientEvent('ox_lib:notify', src, { title = 'System', description = "Live-Tracking gestartet.", type = 'success' })
    TriggerClientEvent('qb-drugs:client:RefreshTrackingUI', -1)
end)

-- TRACKING LOOP (30 Seconds)
CreateThread(function()
    while true do
        Wait(30000) -- 30 Seconds
        local currentTime = os.time()
        
        for number, data in pairs(ActiveTrackings) do
            -- Find target player
            local target = GetPlayerByPhone(number)
            if target then
                local ped = GetPlayerPed(target.PlayerData.source)
                if DoesEntityExist(ped) then
                    local coords = GetEntityCoords(ped)
                    -- Broadcast to all police
                    TriggerClientEvent('qb-drugs:client:UpdateTrackingBlip', -1, number, coords)
                end
            else
                -- Target offline or number invalid, maybe stop tracking?
                -- ActiveTrackings[number] = nil
            end
        end

        -- Periodic Cleanup of expired permits
        for id, p in pairs(TrackingPermits) do
            if p.expiry and currentTime > p.expiry then
                TrackingPermits[id] = nil
                if ActiveTrackings[p.number] then
                    ActiveTrackings[p.number] = nil
                    TriggerClientEvent('qb-drugs:client:StopTrackingBlip', -1, p.number)
                end
            end
        end
    end
end)

RegisterNetEvent("qb-drugs:server:PayProtection", function(netId)
    local src = source
    if not Config.EnableProtection then return end
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    if Player.Functions.RemoveMoney('cash', Config.ProtectionCost) then
        local expiry = os.time() + (Config.ProtectionDuration * 60)
        ProtectedPlayers[Player.PlayerData.citizenid] = expiry
        
        TriggerClientEvent("ox_lib:notify", src, {
            title = 'Dealer',
            description = "Du hast Schutzgeld gezahlt. Du bist für die nächsten 2 Stunden sicher.",
            type = 'success'
        })
    else
        TriggerClientEvent("ox_lib:notify", src, {
            title = 'Dealer',
            description = "Du hast nicht genug Bargeld dabei!",
            type = 'error'
        })
    end
end)
