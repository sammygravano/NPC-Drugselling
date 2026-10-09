Config = {}

Config.PoliceJob = "police"
Config.MinInterrogationRank = 4 -- Minimum rank needed to get phone numbers from dealers
Config.InterrogationSkillCheck = {'easy', 'easy', 'medium'} -- ox_lib skillcheck difficulties

-- Dealer Spawn
Config.MinDealers = 3
Config.MaxDealers = 5
Config.DealerRespawnTime = 300000

Config.PossibleDealerSpawns = {
    vector4(232.17, 112.89, 93.88, 161.57),
    vector4(99.07, 175.37, 104.60, 39.69),
    vector4(150.58, 322.63, 112.33, 107.72),
    vector4(1099.28, -345.92, 67.18, 303.31),
    vector4(1223.55, -482.08, 66.38, 252.28),
    vector4(1082.51, -787.40, 58.35, 181.42),
    vector4(1136.06, -1361.96, 34.57, 357.17),
    vector4(1121.34, -2247.16, 30.16, 269.29),
    vector4(-99.55, -2232.29, 7.80, 266.46)
}

Config.DealerModels = {
    `g_m_y_mexgoon_02`,
    `g_m_y_mexgoon_03`,
    `g_m_y_polslo_01`,
    `g_m_y_salvagoon_01`,
    `g_m_y_lost_01`,
    `g_m_y_ballasout_01`,
    `g_m_y_famca_01`,
    `g_m_importexport_0`,
    `g_m_m_chicold_01`,
    `g_m_y_korean_02`,
    `g_m_y_strpunk_02`,
    `csb_paige`,
    `g_f_y_vagos_01`,
    `g_f_y_ballas_01`,
    `g_f_y_lost_01`,
    `g_f_y_families_01`,
    `mp_f_weed_01`,
    `s_f_y_migrant_01`
}

-- Verkauf
Config.Drugs = {
    ["weed_brick"] = {label = "Weed", minPrice = 100, maxPrice = 200},
    ["coke_baggy"] = {label = "Koksbeutel", minPrice = 300, maxPrice = 500},
}

-- Aggro System
Config.NightStart = 22
Config.NightEnd = 6

Config.NightPriceMultiplier = 1.5 -- 50% more money at night
Config.NightRobberyChance = 30    -- 30% chance at night to be robbed (default 15%)

Config.DayAggroChance = 10
Config.NightAggroChance = 40
 -- Precentage chance that the dealer will attack if only 1 cop is nearby
Config.DayPoliceAloneChance = 20
Config.NightPoliceAloneChance = 70

Config.EnableBackup = false -- Set to false to disable backup NPCs for dealers
Config.BackupChance = 40   -- Chance for backup to spawn (if enabled)
-- Checks for nearby cops when interacting with dealer
Config.PoliceCheckRadius = 40.0
Config.NPCWeapons = {
    "WEAPON_PISTOL",
    "WEAPON_MICROSMG",
    "WEAPON_COMBATPISTOL",
    "WEAPON_DBSHOTGUN",
    "WEAPON_ASSAULTRIFLE",
    "WEAPON_COMPACTRIFLE"
}

-- Police Alert
Config.PoliceAlertChance = 70 -- 70% chance to alert police on sale
Config.AlertRadius = 200.0

-- Robbery System
Config.RobberyChance = 15 -- 15% chance
Config.EnableProtection = true -- Set to false to disable the protection money system
Config.ProtectionCost = 5000 -- How much it costs to pay protection money
Config.ProtectionDuration = 120 -- Duration in minutes (2 hours = 120)
Config.MinAssociates = 1
Config.MaxAssociates = 2
Config.RobberyWait = 5000 -- How long the NPC waits before running away after stealing
Config.LootChance = 60 -- 70% chance to get items back if you kill the dealer
Config.LootReturnPercentage = 0.2 -- 80% of items/money returned (some might be "lost" or "used")

-- Extra Loot (Items the dealer already had)
Config.ExtraLootChance = 40 -- 40% chance to find additional items
Config.ExtraLoot = {
    { item = "money", min = 50, max = 150, chance = 30 },
    { item = "weed_brick", min = 1, max = 2, chance = 5 },
    { item = "coke_baggy", min = 1, max = 1, chance = 3 },
    { item = "blueprint_minismg", min = 1, max = 1, chance = 5 },
}

-- Bodybag System
Config.BodybagJobs = { "police", "ambulance" }
Config.BodybagModel = `xm_prop_body_bag`
Config.DisposalLocation = vector3(278.27, -1345.15, 31.93) -- Example: Central Medical Center or Morgue
Config.DisposalRadius = 5.0
