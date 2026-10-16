-- wsdata.lua  (ChainFinder for Ashita v4)
--
-- DATA VERIFICATION (last full recheck)
-- Sources compared against each other:
--   1. Windower "Resources" weapon_skills.lua   (ids, names, weapon types)
--   2. Ivaar's Skillchains skills.lua + sc_info (properties, chain table)
--   3. FFXIclopedia "Category:Skillchains"      (A/B/C attributes for every skill + chain table)
--   4. BG-Wiki skill / category / Blue Mage pages (tie-breaks, Prime skills, blue spells)
--
-- Results: the chain table matches sources 2 and 3 exactly (15 level-1, 8 level-2, level-3
-- Light/Darkness, level-4 doubles; BG-Wiki's "19 ways" count also matches). Weapon skills agree
-- across all sources except the fixes made on recheck:
--   * Hot Shot was mislabeled (Liquefaction/Transfixion, not Reverberation)
--   * Fell Cleave gained a third property; its order is Impaction/Detonation/Scission
--   * Tornado Kick, Herculean Slash: order is Induration/Impaction/Detonation (BG-Wiki + FFXIclopedia;
--     Ivaar's file has Detonation first)
--   * Shoulder Tackle, Blade: Chi, Blade: Jin: property order corrected
--   * Uriel Blade: BG-Wiki lists Light/Fragmentation/Scission (other sources list only the first two;
--     Scission is the lowest priority, so it rarely matters)
--   * Blue magic: Quadrastrike (Liquefaction/Scission), Amorphic Spikes (Gravitation/Transfixion),
--     Barbed Crescent (Distortion/Liquefaction) corrected to BG-Wiki's current list
-- The 14 Prime weapon skills were each confirmed against BG-Wiki/FFXIclopedia (properties + weapon type).
-- Sanguine Blade has no skillchain property (confirmed); Dragon Blow = Distortion, Fast Blade II = Fusion.
--
-- Property ORDER matters: it is the priority used when matching a skill against the chain in progress.
-- To add or correct a skill, edit a row:   { id, "Name", "Property1", "Property2", ... }
-- Not modelled: Aeonic aftermath bonus properties and Radiance / Umbra.
-- Known gaps: Sweeping Gouge (a physical blue spell) has no listed property in any source I found.

local M = {}

-- skill id -> rows.  1 H2H, 2 Dagger, 3 Sword, 4 GreatSword, 5 Axe, 6 GreatAxe,
-- 7 Scythe, 8 Polearm, 9 Katana, 10 GreatKatana, 11 Club, 12 Staff,
-- 25 Archery, 26 Marksmanship
local rows = {
[1] = {
    {1,"Combo","Impaction"}, {2,"Shoulder Tackle","Reverberation","Impaction"},
    {3,"One Inch Punch","Compression"}, {4,"Backhand Blow","Detonation"},
    {5,"Raging Fists","Impaction"}, {6,"Spinning Attack","Liquefaction","Impaction"},
    {7,"Howling Fist","Transfixion","Impaction"}, {8,"Dragon Kick","Fragmentation"},
    {9,"Asuran Fists","Gravitation","Liquefaction"}, {10,"Final Heaven","Light","Fusion"},
    {11,"Ascetic's Fury","Fusion","Transfixion"}, {12,"Stringing Pummel","Gravitation","Liquefaction"},
    {13,"Tornado Kick","Induration","Impaction","Detonation"}, {14,"Victory Smite","Light","Fragmentation"},
    {15,"Shijin Spiral","Fusion","Reverberation"}, {228,"Final Paradise","Light"},
    {230,"Dragon Blow","Distortion"}, {231,"Maru Kala","Detonation","Compression","Distortion"},
},
[2] = {
    {16,"Wasp Sting","Scission"}, {17,"Viper Bite","Scission"}, {18,"Shadowstitch","Reverberation"},
    {19,"Gust Slash","Detonation"}, {20,"Cyclone","Detonation","Impaction"},
    {23,"Dancing Edge","Scission","Detonation"}, {24,"Shark Bite","Fragmentation"},
    {25,"Evisceration","Gravitation","Transfixion"}, {26,"Mercy Stroke","Darkness","Gravitation"},
    {27,"Mandalic Stab","Fusion","Compression"}, {28,"Mordant Rime","Fragmentation","Distortion"},
    {29,"Pyrrhic Kleos","Distortion","Scission"}, {30,"Aeolian Edge","Scission","Detonation","Impaction"},
    {31,"Rudra's Storm","Darkness","Distortion"}, {224,"Exenterator","Fragmentation","Scission"},
    {232,"Ruthless Stroke","Liquefaction","Impaction","Fragmentation"},
},
[3] = {
    {32,"Fast Blade","Scission"}, {33,"Burning Blade","Liquefaction"},
    {34,"Red Lotus Blade","Liquefaction","Detonation"}, {35,"Flat Blade","Impaction"},
    {36,"Shining Blade","Scission"}, {37,"Seraph Blade","Scission"},
    {38,"Circle Blade","Reverberation","Impaction"}, {40,"Vorpal Blade","Scission","Impaction"},
    {41,"Swift Blade","Gravitation"}, {42,"Savage Blade","Fragmentation","Scission"},
    {43,"Knights of Round","Light","Fusion"}, {44,"Death Blossom","Fragmentation","Distortion"},
    {45,"Atonement","Fusion","Reverberation"}, {46,"Expiacion","Distortion","Scission"},
    {225,"Chant du Cygne","Light","Distortion"}, {226,"Requiescat","Gravitation","Scission"},
    {227,"Knights of Rotund","Light"}, {229,"Fast Blade II","Fusion"},
    {233,"Imperator","Detonation","Compression","Distortion"}, {238,"Uriel Blade","Light","Fragmentation","Scission"},
    {239,"Glory Slash","Light","Fusion"},
},
[4] = {
    {48,"Hard Slash","Scission"}, {49,"Power Slash","Transfixion"}, {50,"Frostbite","Induration"},
    {51,"Freezebite","Induration","Detonation"}, {52,"Shockwave","Reverberation"},
    {53,"Crescent Moon","Scission"}, {54,"Sickle Moon","Scission","Impaction"},
    {55,"Spinning Slash","Fragmentation"}, {56,"Ground Strike","Fragmentation","Distortion"},
    {57,"Scourge","Light","Fusion"}, {58,"Herculean Slash","Induration","Impaction","Detonation"},
    {59,"Torcleaver","Light","Distortion"}, {60,"Resolution","Fragmentation","Scission"},
    {61,"Dimidiation","Light","Fragmentation"}, {62,"Fimbulvetr","Detonation","Compression","Distortion"},
},
[5] = {
    {64,"Raging Axe","Detonation","Impaction"}, {65,"Smash Axe","Induration","Reverberation"},
    {66,"Gale Axe","Detonation"}, {67,"Avalanche Axe","Scission","Impaction"},
    {68,"Spinning Axe","Liquefaction","Scission","Impaction"}, {69,"Rampage","Scission"},
    {70,"Calamity","Scission","Impaction"}, {71,"Mistral Axe","Fusion"},
    {72,"Decimation","Fusion","Reverberation"}, {73,"Onslaught","Darkness","Gravitation"},
    {74,"Primal Rend","Gravitation","Reverberation"}, {75,"Bora Axe","Scission","Detonation"},
    {76,"Cloudsplitter","Darkness","Fragmentation"}, {77,"Ruinator","Distortion","Detonation"},
    {78,"Blitz","Liquefaction","Impaction","Fragmentation"},
},
[6] = {
    {80,"Shield Break","Impaction"}, {81,"Iron Tempest","Scission"},
    {82,"Sturmwind","Reverberation","Scission"}, {83,"Armor Break","Impaction"},
    {84,"Keen Edge","Compression"}, {85,"Weapon Break","Impaction"},
    {86,"Raging Rush","Induration","Reverberation"}, {87,"Full Break","Distortion"},
    {88,"Steel Cyclone","Distortion","Detonation"}, {89,"Metatron Torment","Light","Fusion"},
    {90,"King's Justice","Fragmentation","Scission"}, {91,"Fell Cleave","Impaction","Detonation","Scission"},
    {92,"Ukko's Fury","Light","Fragmentation"}, {93,"Upheaval","Fusion","Compression"},
    {94,"Disaster","Transfixion","Scission","Gravitation"},
},
[7] = {
    {96,"Slice","Scission"}, {97,"Dark Harvest","Reverberation"},
    {98,"Shadow of Death","Induration","Reverberation"}, {99,"Nightmare Scythe","Compression","Scission"},
    {100,"Spinning Scythe","Reverberation","Scission"}, {101,"Vorpal Scythe","Transfixion","Scission"},
    {102,"Guillotine","Induration"}, {103,"Cross Reaper","Distortion"},
    {104,"Spiral Hell","Distortion","Scission"}, {105,"Catastrophe","Darkness","Gravitation"},
    {106,"Insurgency","Fusion","Compression"}, {107,"Infernal Scythe","Compression","Reverberation"},
    {108,"Quietus","Darkness","Distortion"}, {109,"Entropy","Gravitation","Reverberation"},
    {110,"Origin","Induration","Reverberation","Fusion"},
},
[8] = {
    {112,"Double Thrust","Transfixion"}, {113,"Thunder Thrust","Transfixion","Impaction"},
    {114,"Raiden Thrust","Transfixion","Impaction"}, {115,"Leg Sweep","Impaction"},
    {116,"Penta Thrust","Compression"}, {117,"Vorpal Thrust","Reverberation","Transfixion"},
    {118,"Skewer","Transfixion","Impaction"}, {119,"Wheeling Thrust","Fusion"},
    {120,"Impulse Drive","Gravitation","Induration"}, {121,"Geirskogul","Light","Distortion"},
    {122,"Drakesbane","Fusion","Transfixion"}, {123,"Sonic Thrust","Transfixion","Scission"},
    {124,"Camlann's Torment","Light","Fragmentation"}, {125,"Stardiver","Gravitation","Transfixion"},
    {126,"Diarmuid","Transfixion","Scission","Gravitation"},
},
[9] = {
    {128,"Blade: Rin","Transfixion"}, {129,"Blade: Retsu","Scission"}, {130,"Blade: Teki","Reverberation"},
    {131,"Blade: To","Induration","Detonation"}, {132,"Blade: Chi","Transfixion","Impaction"},
    {133,"Blade: Ei","Compression"}, {134,"Blade: Jin","Detonation","Impaction"},
    {135,"Blade: Ten","Gravitation"}, {136,"Blade: Ku","Gravitation","Transfixion"},
    {137,"Blade: Metsu","Darkness","Fragmentation"}, {138,"Blade: Kamu","Fragmentation","Compression"},
    {139,"Blade: Yu","Reverberation","Scission"}, {140,"Blade: Hi","Darkness","Gravitation"},
    {141,"Blade: Shun","Fusion","Impaction"}, {142,"Zesho Meppo","Induration","Reverberation","Fusion"},
},
[10] = {
    {144,"Tachi: Enpi","Transfixion","Scission"}, {145,"Tachi: Hobaku","Induration"},
    {146,"Tachi: Goten","Transfixion","Impaction"}, {147,"Tachi: Kagero","Liquefaction"},
    {148,"Tachi: Jinpu","Scission","Detonation"}, {149,"Tachi: Koki","Reverberation","Impaction"},
    {150,"Tachi: Yukikaze","Induration","Detonation"}, {151,"Tachi: Gekko","Distortion","Reverberation"},
    {152,"Tachi: Kasha","Fusion","Compression"}, {153,"Tachi: Kaiten","Light","Fragmentation"},
    {154,"Tachi: Rana","Gravitation","Induration"}, {155,"Tachi: Ageha","Compression","Scission"},
    {156,"Tachi: Fudo","Light","Distortion"}, {157,"Tachi: Shoha","Fragmentation","Compression"},
    {158,"Tachi: Suikawari","Fusion"}, {159,"Tachi: Mumei","Detonation","Compression","Distortion"},
},
[11] = {
    {160,"Shining Strike","Impaction"}, {161,"Seraph Strike","Impaction"}, {162,"Brainshaker","Reverberation"},
    {165,"Skullbreaker","Induration","Reverberation"}, {166,"True Strike","Detonation","Impaction"},
    {167,"Judgment","Impaction"}, {168,"Hexa Strike","Fusion"},
    {169,"Black Halo","Fragmentation","Compression"}, {170,"Randgrith","Light","Fragmentation"},
    {172,"Flash Nova","Induration","Reverberation"}, {174,"Realmrazer","Fusion","Impaction"},
    {175,"Exudation","Darkness","Fragmentation"}, {234,"Dagda","Transfixion","Scission","Gravitation"},
},
[12] = {
    {176,"Heavy Swing","Impaction"}, {177,"Rock Crusher","Impaction"},
    {178,"Earth Crusher","Detonation","Impaction"}, {179,"Starburst","Compression","Reverberation"},
    {180,"Sunburst","Compression","Reverberation"}, {181,"Shell Crusher","Detonation"},
    {182,"Full Swing","Liquefaction","Impaction"}, {184,"Retribution","Gravitation","Reverberation"},
    {185,"Gate of Tartarus","Darkness","Distortion"}, {186,"Vidohunir","Fragmentation","Distortion"},
    {187,"Garland of Bliss","Fusion","Reverberation"}, {188,"Omniscience","Gravitation","Transfixion"},
    {189,"Cataclysm","Compression","Reverberation"}, {191,"Shattersoul","Gravitation","Induration"},
    {235,"Oshala","Induration","Reverberation","Fusion"},
},
[25] = {
    {192,"Flaming Arrow","Liquefaction","Transfixion"}, {193,"Piercing Arrow","Reverberation","Transfixion"},
    {194,"Dulling Arrow","Liquefaction","Transfixion"}, {196,"Sidewinder","Reverberation","Transfixion","Detonation"},
    {197,"Blast Arrow","Induration","Transfixion"}, {198,"Arching Arrow","Fusion"},
    {199,"Empyreal Arrow","Fusion","Transfixion"}, {200,"Namas Arrow","Light","Distortion"},
    {201,"Refulgent Arrow","Reverberation","Transfixion"}, {202,"Jishnu's Radiance","Light","Fusion"},
    {203,"Apex Arrow","Fragmentation","Transfixion"}, {204,"Sarv","Transfixion","Scission","Gravitation"},
},
[26] = {
    {208,"Hot Shot","Liquefaction","Transfixion"}, {209,"Split Shot","Reverberation","Transfixion"},
    {210,"Sniper Shot","Liquefaction","Transfixion"}, {212,"Slug Shot","Reverberation","Transfixion","Detonation"},
    {213,"Blast Shot","Induration","Transfixion"}, {214,"Heavy Shot","Fusion"},
    {215,"Detonator","Fusion","Transfixion"}, {216,"Coronach","Darkness","Fragmentation"},
    {217,"Trueflight","Fragmentation","Scission"}, {218,"Leaden Salute","Gravitation","Transfixion"},
    {219,"Numbing Shot","Induration","Detonation","Impaction"}, {220,"Wildfire","Darkness","Gravitation"},
    {221,"Last Stand","Fusion","Reverberation"}, {222,"Terminus","Induration","Reverberation","Fusion"},
},
}

-- Expand rows into { id=, name=, props={...} }
M.ws = {}
for skill, list in pairs(rows) do
    local out = {}
    for _, r in ipairs(list) do
        local props = {}
        for i = 3, #r do props[#props + 1] = r[i] end
        out[#out + 1] = { id = r[1], name = r[2], props = props, skill = skill }
    end
    M.ws[skill] = out
end

-- chain[first][second] = { level_of_result, result_name }
-- (from Ivaar's Skillchains sc_info)
M.chain = {
    Light         = { Light = {4,'Light'} },
    Darkness      = { Darkness = {4,'Darkness'} },
    Gravitation   = { Distortion = {3,'Darkness'}, Fragmentation = {2,'Fragmentation'} },
    Fragmentation = { Fusion = {3,'Light'}, Distortion = {2,'Distortion'} },
    Distortion    = { Gravitation = {3,'Darkness'}, Fusion = {2,'Fusion'} },
    Fusion        = { Fragmentation = {3,'Light'}, Gravitation = {2,'Gravitation'} },
    Compression   = { Transfixion = {1,'Transfixion'}, Detonation = {1,'Detonation'} },
    Liquefaction  = { Impaction = {2,'Fusion'}, Scission = {1,'Scission'} },
    Induration    = { Reverberation = {2,'Fragmentation'}, Compression = {1,'Compression'}, Impaction = {1,'Impaction'} },
    Reverberation = { Induration = {1,'Induration'}, Impaction = {1,'Impaction'} },
    Transfixion   = { Scission = {2,'Distortion'}, Reverberation = {1,'Reverberation'}, Compression = {1,'Compression'} },
    Scission      = { Liquefaction = {1,'Liquefaction'}, Reverberation = {1,'Reverberation'}, Detonation = {1,'Detonation'} },
    Detonation    = { Compression = {2,'Gravitation'}, Scission = {1,'Scission'} },
    Impaction     = { Liquefaction = {1,'Liquefaction'}, Detonation = {1,'Detonation'} },
}

-- Given the properties currently on the target ("old", in priority order) and the
-- next weapon skill's properties ("new"), returns level, result - or nil if no chain.
function M.check(old, new)
    for k = 1, #old do
        local combo = M.chain[old[k]]
        if combo then
            for i = 1, #new do
                local r = combo[new[i]]
                if r then return r[1], r[2] end
            end
        end
    end
    return nil
end

-- Elements each skillchain can be magic-burst with (Ivaar's Skillchains sc_info)
M.elements = {
    Light         = { 'Fire', 'Wind', 'Lightning', 'Light' },
    Darkness      = { 'Earth', 'Ice', 'Water', 'Dark' },
    Gravitation   = { 'Earth', 'Dark' },
    Fragmentation = { 'Wind', 'Lightning' },
    Distortion    = { 'Ice', 'Water' },
    Fusion        = { 'Fire', 'Light' },
    Compression   = { 'Dark' },
    Liquefaction  = { 'Fire' },
    Induration    = { 'Ice' },
    Reverberation = { 'Water' },
    Transfixion   = { 'Light' },
    Scission      = { 'Earth' },
    Detonation    = { 'Wind' },
    Impaction     = { 'Lightning' },
}

----------------------------------------------------------------------
-- Blue Magic
-- PHYSICAL spells (usable in a skillchain with Chain Affinity): id, name, properties.
-- Source: Ivaar's Skillchains skills.lua (spell ids). Sweeping Gouge is a physical
-- blue spell in the game but is not in that data, so it is not listed here.
-- Spells marked in blu_ul need Unbridled Learning.
----------------------------------------------------------------------
M.blu_physical = {
    {519,"Screwdriver","Transfixion","Scission"}, {527,"Smite of Rage","Detonation"},
    {529,"Bludgeon","Liquefaction"}, {539,"Terror Touch","Compression","Reverberation"},
    {540,"Spinal Cleave","Scission","Detonation"}, {543,"Mandibular Bite","Induration"},
    {545,"Sickle Slash","Compression"}, {551,"Power Attack","Reverberation"},
    {554,"Death Scissors","Compression","Reverberation"}, {560,"Frenetic Rip","Induration"},
    {564,"Body Slam","Impaction"}, {567,"Helldive","Transfixion"}, {569,"Jet Stream","Impaction"},
    {577,"Foot Kick","Detonation"}, {585,"Ram Charge","Fragmentation"}, {587,"Claw Cyclone","Scission"},
    {589,"Dimensional Death","Transfixion","Impaction"}, {594,"Uppercut","Liquefaction","Impaction"},
    {596,"Pinecone Bomb","Liquefaction"}, {597,"Sprout Smack","Reverberation"},
    {599,"Queasyshroom","Compression"}, {603,"Wild Oats","Transfixion"},
    {611,"Disseverment","Distortion"}, {617,"Vertical Cleave","Gravitation"},
    {620,"Battle Dance","Impaction"}, {622,"Grand Slam","Induration"}, {623,"Head Butt","Impaction"},
    {628,"Frypan","Impaction"}, {631,"Hydro Shot","Reverberation"}, {638,"Feather Storm","Transfixion"},
    {640,"Tail Slap","Reverberation"}, {641,"Hysteric Barrage","Detonation"}, {643,"Cannonball","Fusion"},
    {650,"Seedspray","Induration","Detonation"}, {652,"Spiral Spin","Transfixion"},
    {653,"Asuran Claws","Liquefaction","Impaction"}, {654,"Sub-zero Smash","Fragmentation"},
    {665,"Final Sting","Fusion"}, {666,"Goblin Rush","Fusion","Impaction"},
    {667,"Vanity Dive","Transfixion","Scission"}, {669,"Whirl of Rage","Scission","Detonation"},
    {670,"Benthic Typhoon","Gravitation","Transfixion"}, {673,"Quadratic Continuum","Distortion","Scission"},
    {677,"Empty Thrash","Compression","Scission"}, {682,"Delta Thrust","Liquefaction","Detonation"},
    {688,"Heavy Strike","Fragmentation","Transfixion"}, {692,"Sudden Lunge","Detonation"},
    {693,"Quadrastrike","Liquefaction","Scission"}, {697,"Amorphic Spikes","Gravitation","Transfixion"},
    {699,"Barbed Crescent","Distortion","Liquefaction"}, {704,"Paralyzing Triad","Gravitation"},
    {706,"Glutinous Dart","Fragmentation"}, {709,"Thrashing Assault","Fusion"},
    {714,"Sinker Drill","Gravitation","Reverberation"}, {723,"Saurian Slide","Fragmentation","Distortion"},
    {740,"Tourbillion","Light","Fragmentation"}, {742,"Bilgestorm","Darkness","Gravitation"},
    {743,"Bloodrake","Darkness","Distortion"},
}
M.blu_ul = { ["Tourbillion"] = true, ["Bilgestorm"] = true, ["Bloodrake"] = true }

-- MAGICAL spells that can magic burst with Burst Affinity, by element.
-- Source: FFXIclopedia blue magic list (spell element). I left out spells that are
-- pure buffs/heals (they cannot burst), e.g. Cocoon, Magic Fruit, Erratic Flutter.
-- If you find one that should be added or removed, edit the lists below.
-- (U) spells (see blu_ul_magic) need Unbridled Learning.
M.blu_magic = {
    Fire = { "Blastbomb", "Bomb Toss", "Sound Blast", "Self-Destruct", "Firespit", "Lowing", "Heat Breath",
             "Blazing Bound", "Thermal Pulse", "Gates of Hades", "Searing Tempest" },
    Ice = { "Ice Break", "Cold Wave", "Infrasonics", "Frost Breath", "Spectral Floe", "Polar Roar" },
    Wind = { "Chaotic Eye", "Mysterious Light", "Stinking Gas", "Frightful Roar", "Hecatomb Wave",
             "Flying Hip Press", "Feather Tickle", "Voracious Trunk", "Leafstorm", "Auroral Drape",
             "Reaving Wind", "Wind Breath", "Tempestuous Upheaval", "Subduction", "Silent Storm",
             "Droning Whirlwind", "Tearing Gust" },
    Earth = { "Sandspin", "Magnetite Cloud", "Filamented Hold", "Bad Breath", "Cimicine Discharge",
              "Embalming Earth", "Entomb" },
    Water = { "Cursed Sphere", "Poison Breath", "Venom Shell", "Awful Eye", "Maelstrom", "Corrosive Ooze",
              "Regurgitation", "Acrid Stream", "Demoralizing Roar", "Water Bomb", "Vapor Spray",
              "Rending Deluge", "Foul Waters", "Nectarous Deluge", "Scouring Spate", "Cesspool" },
    Lightning = { "Blitzstrahl", "Mind Blast", "Temporal Shift", "Charged Whisker", "Thunder Breath",
                  "Anvil Lightning", "Thunderbolt", "Crashing Thunder" },
    Light = { "Sheep Song", "Blank Gaze", "Radiant Breath", "Light of Penance", "1000 Needles", "Yawn",
              "Actinic Burst", "Magic Hammer", "Winds of Promyvion", "Retinal Glare", "Diffusion Ray",
              "Rail Cannon", "Blinding Fulgor", "Uproot" },
    Dark = { "Blood Drain", "Soporific", "Death Ray", "Digest", "MP Drainkiss", "Geist Wall", "Blood Saber",
             "Jettatura", "Eyes On Me", "Sandspray", "Enervation", "Osmosis", "Dream Flower",
             "Everyone's Grudge", "Mortal Ray", "Dark Orb", "Absolute Terror", "Atramentous Libations",
             "Tenebral Crush", "Palling Salvo", "Blistering Roar", "Cruel Joke" },
}
M.blu_ul_magic = {
    ["Gates of Hades"] = true, ["Polar Roar"] = true, ["Droning Whirlwind"] = true, ["Tearing Gust"] = true,
    ["Cesspool"] = true, ["Thunderbolt"] = true, ["Crashing Thunder"] = true, ["Uproot"] = true,
    ["Absolute Terror"] = true, ["Blistering Roar"] = true, ["Cruel Joke"] = true,
}

-- Colors (r,g,b,a) for result names
M.colors = {
    Light         = { 1.00, 1.00, 0.70, 1 },
    Darkness      = { 0.75, 0.55, 1.00, 1 },
    Gravitation   = { 0.70, 0.50, 0.30, 1 },
    Fragmentation = { 0.98, 0.61, 0.97, 1 },
    Distortion    = { 0.20, 0.60, 1.00, 1 },
    Fusion        = { 1.00, 0.40, 0.40, 1 },
    Compression   = { 0.60, 0.45, 0.85, 1 },
    Liquefaction  = { 1.00, 0.30, 0.20, 1 },
    Induration    = { 0.40, 1.00, 1.00, 1 },
    Reverberation = { 0.35, 0.45, 1.00, 1 },
    Transfixion   = { 0.95, 0.95, 0.95, 1 },
    Scission      = { 0.85, 0.55, 0.20, 1 },
    Detonation    = { 0.40, 1.00, 0.40, 1 },
    Impaction     = { 1.00, 0.40, 1.00, 1 },
}

return M
