-- petdata.lua  (ChainFinder for Ashita v4)
--
-- Pet ability (Ready move) skillchain properties and the Ready moves of each pet.
--
-- Sources:
--   * Ability properties: Ivaar's Ashita "Skillchains" skills.lua, table skills[13] (pet abilities).
--     Properties are in priority order, exactly as in that file.
--   * Pet -> Ready moves: FFXIclopedia "Ready" page. THIS LIST IS INCOMPLETE: it only covers the
--     21 pets that page lists. If your pet is missing, add it to M.pets below (see the format).
--
-- Pets covered: every CatsEyeXI jug pet (normal AND high quality, 28 incl. Turbid Toloi) plus the high-level
-- named pets from FFXIclopedia (Dapper Mac, Lucky Lulush, ...), which CatsEyeXI may not have yet.
-- With "direct" menu reading the order below no longer matters: the highlighted move is matched by name.
--
-- Moves that have no skillchain property (Intimidate, Sheep Song, ...) are listed on purpose: the
-- Ready menu counts them, so they must be here for the cursor position to line up.
--
-- The IN-GAME ORDER of the Ready menu is not documented anywhere I could verify. The moves are
-- kept in the order listed below; if the cursor lands on the wrong move, use
--     /sc ready order alpha     or     /sc ready order id
-- and check the move name shown in the window against the menu.

local M = {}

-- { id, "Name", "Property1", "Property2", ... }
local rows = {
    {513,"Poison Nails","Transfixion"}, {521,"Regal Scratch","Scission"}, {528,"Moonlit Charge","Compression"},
    {529,"Crescent Fang","Transfixion"}, {534,"Eclipse Bite","Gravitation","Scission"}, {544,"Punch","Liquefaction"},
    {546,"Burning Strike","Impaction"}, {547,"Double Punch","Compression"}, {550,"Flaming Crush","Fusion","Reverberation"},
    {560,"Rock Throw","Scission"}, {562,"Rock Buster","Reverberation"}, {563,"Megalith Throw","Induration"},
    {566,"Mountain Buster","Gravitation","Induration"}, {570,"Crag Throw","Gravitation","Scission"},
    {576,"Barracuda Dive","Reverberation"}, {578,"Tail Whip","Detonation"}, {582,"Spinning Dive","Distortion","Detonation"},
    {592,"Claw","Detonation"}, {598,"Predator Claws","Fragmentation","Scission"}, {608,"Axe Kick","Induration"},
    {612,"Double Slap","Scission"}, {614,"Rush","Distortion","Scission"}, {624,"Shock Strike","Impaction"},
    {630,"Chaotic Strike","Fragmentation","Transfixion"}, {634,"Volt Strike","Fragmentation","Scission"},
    {656,"Camisado","Compression"}, {667,"Blindside","Gravitation","Transfixion"}, {672,"Foot Kick","Reverberation"},
    {674,"Whirl Claws","Impaction"}, {675,"Head Butt","Detonation"}, {677,"Wild Oats","Transfixion"},
    {678,"Leaf Dagger","Scission"}, {681,"Razor Fang","Impaction"}, {682,"Claw Cyclone","Scission"},
    {683,"Tail Blow","Impaction"}, {685,"Blockhead","Reverberation"}, {686,"Brain Crush","Liquefaction"},
    {689,"Lamb Chop","Impaction"}, {691,"Sheep Charge","Reverberation"}, {695,"Big Scissors","Scission"},
    {698,"Needleshot","Transfixion"}, {699,"??? Needles","Darkness","Fragmentation"}, {700,"Frogkick","Compression"},
    {707,"Power Attack","Reverberation"}, {709,"Rhino Attack","Detonation"}, {717,"Mandibular Bite","Detonation"},
    {723,"Nimble Snap","Impaction"}, {724,"Cyclotail","Impaction"}, {726,"Double Claw","Liquefaction"},
    {727,"Grapple","Reverberation"}, {728,"Spinning Top","Impaction"}, {732,"Suction","Compression"},
    {736,"Sudden Lunge","Impaction"}, {737,"Spiral Spin","Scission"}, {743,"Scythe Tail","Liquefaction"},
    {744,"Ripper Fang","Induration"}, {745,"Chomp Rush","Darkness","Gravitation"}, {749,"Back Heel","Reverberation"},
    {753,"Tortoise Stomp","Liquefaction"}, {756,"Wing Slap","Gravitation","Liquefaction"}, {757,"Beak Lunge","Scission"},
    {759,"Recoil Dive","Transfixion"}, {761,"Sensilla Blades","Scission"}, {762,"Tegmina Buffet","Distortion","Detonation"},
    {764,"Swooping Frenzy","Fusion","Reverberation"}, {765,"Sweeping Gouge","Induration"},
    {767,"Pentapeck","Light","Distortion"}, {768,"Tickling Tendrils","Impaction"}, {772,"Somersault","Compression"},
    {776,"Pecking Flurry","Transfixion"}, {777,"Sickle Slash","Transfixion"}, {780,"Regal Gash","Distortion","Detonation"},
    -- Puppetmaster automaton weapon skills (ids are made up - they only keep the 'id' ordering stable).
    -- Properties: Gamer Escape / FFXIclopedia "Automaton Weapon Skills" (two sources that agree except Arcuballista / Daze,
    -- where Gamer Escape also lists Transfixion; I used the FFXIclopedia single property). Not verified in game.
    {3001,"Slapstick","Reverberation","Impaction"}, {3002,"Knockout","Scission","Detonation"},
    {3003,"Magic Mortar","Liquefaction","Fusion"}, {3004,"Chimera Ripper","Detonation","Induration"},
    {3005,"String Clipper","Scission"}, {3006,"Cannibal Blade","Compression","Reverberation"},
    {3007,"Bone Crusher","Fragmentation"}, {3008,"String Shredder","Distortion","Scission"},
    {3009,"Arcuballista","Liquefaction"}, {3010,"Daze","Impaction"}, {3011,"Armor Piercer","Gravitation"},
    {3012,"Armor Shatterer","Fusion","Impaction"},
    {961,"Welt","Scission"}, {964,"Roundhouse","Detonation"}, {970,"Hysteric Assault","Fragmentation","Transfixion"},
}

-- lower-case letters and digits only, so "Frog Kick" == "Frogkick" and "Nursery Nazuna" == "NurseryNazuna"
local function norm(s)
    return (tostring(s or ''):lower():gsub('[^%w]', ''))
end
M.norm = norm

M.by_norm = {}
for _, r in ipairs(rows) do
    local props = {}
    for i = 3, #r do props[#props + 1] = r[i] end
    local k = norm(r[2])
    if not M.by_norm[k] then M.by_norm[k] = { id = r[1], name = r[2], props = props } end
end

-- pet name -> Ready moves.  Add your own pets here:  { 'Pet Name', { 'Move 1', 'Move 2', ... } }
local BERTHA_MOVES = { 'Sensilla Blades', 'Tegmina Buffet' }
local pets = {
    { 'Turbid Toloi',      { 'Intimidate', 'Recoil Dive', 'Water Wall' } },
    { 'Lucky Lulush',      { 'Foot Kick', 'Whirl Claws', 'Snow Cloud', 'Wild Carrot' } },
    { 'Dipper Yuly',       { 'Spiral Spin', 'Noisome Powder', 'Sudden Lunge' } },
    { 'Flowerpot Merle',   { 'Head Butt', 'Leaf Dagger', 'Wild Oats', 'Scream' } },
    { 'Nursery Nazuna',    { 'Lamb Chop', 'Sheep Charge', 'Sheep Song', 'Rage' } },
    { 'Lullaby Melodia',   { 'Lamb Chop', 'Rage', 'Sheep Song', 'Sheep Charge' } },
    -- Dirty Sanchez shares Bouncing Bertha's moves (BERTHA_MOVES, defined above the list)
    { 'Bouncing Bertha',   BERTHA_MOVES },
    { 'Dirty Sanchez',     BERTHA_MOVES },

    -- ---- CatsEyeXI jug pets (list from the BG-Wiki CatsEyeXI Systems/Jobs page; moves from BG-Wiki "Jug Pets") ----
    { 'Sheep Familiar',    { 'Lamb Chop', 'Rage', 'Sheep Charge', 'Sheep Song' } },
    { 'Hare Familiar',     { 'Foot Kick', 'Dust Cloud', 'Whirl Claws', 'Wild Carrot' } },
    { 'Keeneared Steffi',  { 'Foot Kick', 'Dust Cloud', 'Whirl Claws', 'Wild Carrot' } },
    { 'Crab Familiar',     { 'Bubble Shower', 'Bubble Curtain', 'Big Scissors', 'Scissor Guard', 'Metallic Body' } },
    { 'Courier Carrie',    { 'Bubble Shower', 'Bubble Curtain', 'Big Scissors', 'Scissor Guard', 'Metallic Body' } },
    { 'Homunculus',        { 'Head Butt', 'Dream Flower', 'Wild Oats', 'Leaf Dagger', 'Scream' } },
    { 'Flowerpot Bill',    { 'Head Butt', 'Dream Flower', 'Wild Oats', 'Leaf Dagger', 'Scream' } },
    { 'Flowerpot Ben',     { 'Head Butt', 'Dream Flower', 'Wild Oats', 'Leaf Dagger', 'Scream' } },
    { 'Flytrap Familiar',  { 'Soporific', 'Gloeosuccus', 'Palsy Pollen' } },
    { 'Voracious Audrey',  { 'Soporific', 'Gloeosuccus', 'Palsy Pollen' } },
    { 'Tiger Familiar',    { 'Roar', 'Razor Fang', 'Claw Cyclone', 'Crossthrash', 'Predatory Glare' } },
    { 'Saber Siravarde',   { 'Roar', 'Razor Fang', 'Claw Cyclone', 'Crossthrash', 'Predatory Glare' } },
    { 'Mayfly Familiar',   { 'Cursed Sphere', 'Venom', 'Somersault' } },
    { 'Shellbuster Orob',  { 'Cursed Sphere', 'Venom', 'Somersault' } },
    { 'Lizard Familiar',   { 'Tail Blow', 'Fireball', 'Blockhead', 'Brain Crush', 'Infrasonics', 'Secretion' } },
    { 'Coldblood Como',    { 'Tail Blow', 'Fireball', 'Blockhead', 'Brain Crush', 'Infrasonics', 'Secretion' } },
    { 'Eft Familiar',      { 'Nimble Snap', 'Cyclotail', 'Geist Wall', 'Numbing Noise', 'Toxic Spit' } },
    { 'Ambusher Allie',    { 'Nimble Snap', 'Cyclotail', 'Geist Wall', 'Numbing Noise', 'Toxic Spit' } },
    { 'Funguar Familiar',  { 'Frogkick', 'Spore', 'Queasyshroom', 'Numbshroom', 'Shakeshroom', 'Silence Gas', 'Dark Spore' } },
    { 'Antlion Familiar',  { 'Mandibular Bite', 'Sandblast', 'Sandpit', 'Venom Spray' } },
    { 'Chopsuey Chucky',   { 'Mandibular Bite', 'Sandblast', 'Sandpit', 'Venom Spray' } },
    { 'Beetle Familiar',   { 'Power Attack', 'High-Frequency Field', 'Rhino Attack', 'Rhino Guard', 'Spoil' } },
    { 'Panzer Galahad',    { 'Power Attack', 'High-Frequency Field', 'Rhino Attack', 'Rhino Guard', 'Spoil' } },
    { 'Mite Familiar',     { 'Double Claw', 'Grapple', 'Spinning Top', 'Filamented Hold' } },
    { 'Lifedrinker Lars',  { 'Double Claw', 'Grapple', 'Spinning Top', 'Filamented Hold' } },
    { 'Amigo Sabotender',  { 'Needleshot', '??? Needles' } },
    { 'Dapper Mac',        { 'Wing Slap', 'Beak Lunge' } },
    { 'Discreet Louise',   { 'Frogkick', 'Queasyshroom', 'Silence Gas', 'Numbshroom', 'Spore', 'Dark Spore', 'Shakeshroom' } },
    { 'Fatso Fargann',     { 'Suction', 'Drainkiss', 'Acid Mist', 'TP Drainkiss' } },
    { 'Presto Julio',      { 'Soporific', 'Gloeosuccus', 'Palsy Pollen' } },
    { 'Audacious Anna',    { 'Tail Blow', 'Fireball', 'Blockhead', 'Infrasonics', 'Brain Crush', 'Secretion' } },
    { 'Mailbuster Cetas',  { 'Cursed Sphere', 'Venom' } },
    { 'Faithful Falcorr',  { 'Back Heel', 'Jettatura', 'Choke Breath', 'Fantod' } },
    { 'Swift Sieghard',    { 'Scythe Tail', 'Ripper Fang', 'Chomp Rush' } },
    { 'Bugeyed Broncha',   { 'Geist Wall', 'Numbing Noise', 'Nimble Snap', 'Cyclotail', 'Toxic Spit' } },
    { 'Bloodclaw Shasra',  { 'Chaotic Eye', 'Blaster', 'Charged Whisker' } },
    { 'Gorefang Hobs',     { 'Roar', 'Razor Fang', 'Claw Cyclone' } },
    { 'Gooey Gerard',      { 'Purulent Ooze', 'Corrosive Ooze' } },
    { 'Crude Raphie',      { 'Tortoise Stomp', 'Harden Shell', 'Aqua Breath' } },
    { 'Droopy Dortwin',    { 'Dust Cloud' } },
    { 'Scissorleg Xerin',  { 'Sensilla Blades', 'Tegmina Buffet' } },
    { 'Attentive Ibuki',   { 'Molting Plumage', 'Swooping Frenzy', 'Pentapeck' } },
    { 'Caring Kiyomaro',   { 'Sweeping Gouge', 'Zealous Snort' } },
}

M.pets = {}
for _, p in ipairs(pets) do
    M.pets[norm(p[1])] = { name = p[1], moves = p[2] }
end

-- Puppetmaster automaton: the skills depend on the FRAME (the head does not change them). The automaton's own name is
-- whatever the player typed, so ChainFinder cannot tell the frame from the name - pick it with the Frame buttons in
-- the Pet window or /sc frame <name>.
M.frames = {
    { key = 'harlequin',  name = 'Harlequin',  moves = { 'Slapstick', 'Knockout', 'Magic Mortar' } },
    { key = 'valoredge',  name = 'Valoredge',  moves = { 'Chimera Ripper', 'String Clipper', 'Cannibal Blade', 'Bone Crusher', 'String Shredder' } },
    { key = 'sharpshot',  name = 'Sharpshot',  moves = { 'Arcuballista', 'Daze', 'Armor Piercer', 'Armor Shatterer' } },
    { key = 'stormwaker', name = 'Stormwaker', moves = { 'Slapstick', 'Knockout', 'Magic Mortar' } },
}
M.frame_by_key = {}
for _, f in ipairs(M.frames) do
    M.frame_by_key[f.key] = f
    M.pets[norm('Automaton ' .. f.name)] = { name = 'Automaton (' .. f.name .. ')', moves = f.moves, auto = true }
end
function M.frame_pet(key)
    local f = M.frame_by_key[key] or M.frame_by_key.harlequin
    return 'Automaton ' .. f.name
end

-- jug (ammo slot item) -> pet it summons. Names are matched word by word and tolerate the game's
-- abbreviations ("S. Herbal Broth" = "Savory Herbal Broth"). Source: BG-Wiki "Jug Pets".
local jugs = {
    { 'Alchemist Water', 'Homunculus' },
    { 'Carrot Broth', 'Hare Familiar' },
    { 'F. Carrot Broth', 'Keeneared Steffi' },
    { 'Fish Broth', 'Crab Familiar' },
    { 'Fish Oil Broth', 'Courier Carrie' },
    { 'Herbal Broth', 'Sheep Familiar' },
    { 'S. Herbal Broth', 'Lullaby Melodia' },
    { 'Grasshopper Broth', 'Flytrap Familiar' },
    { 'Noisy Grasshopper Broth', 'Voracious Audrey' },
    { 'Humus', 'Flowerpot Bill' },
    { 'Rich Humus', 'Flowerpot Ben' },
    { 'Meat Broth', 'Tiger Familiar' },
    { 'Warm Meat Broth', 'Saber Siravarde' },
    { 'Bug Broth', 'Mayfly Familiar' },
    { 'Qdv. Bug Broth', 'Shellbuster Orob' },
    { 'Carrion Broth', 'Lizard Familiar' },
    { 'Cold Carrion Broth', 'Coldblood Como' },
    { 'Mole Broth', 'Eft Familiar' },
    { 'L. Mole Broth', 'Ambusher Allie' },
    { 'Seedbed Soil', 'Funguar Familiar' },
    { 'Fun Dip', 'Dirty Sanchez' },
    { 'Bubbly Broth', 'Bouncing Bertha' },
    { 'Antica Broth', 'Antlion Familiar' },
    { 'Fragrant Antica Broth', 'Chopsuey Chucky' },
    { 'Tree Sap', 'Beetle Familiar' },
    { 'Scarlet Sap', 'Panzer Galahad' },
    { 'Blood Broth', 'Mite Familiar' },
    { 'Clear Blood Broth', 'Lifedrinker Lars' },
    { 'Auroral Broth', 'Turbid Toloi' },
    { 'Sun Water', 'Amigo Sabotender' },
    { 'Briny Broth', 'Dapper Mac' },
    { 'D. Herbal Broth', 'Nursery Nazuna' },
    { 'L. Carrot Broth', 'Lucky Lulush' },
    { 'Vermihumus', 'Flowerpot Merle' },
    { 'Wool Grease', 'Dipper Yuly' },
    { 'Deepbed Soil', 'Discreet Louise' },
    { 'C. Plasma Broth', 'Fatso Fargann' },
    { 'C. Grass. Broth', 'Presto Julio' },
    { 'Bub. Carrion Broth', 'Audacious Anna' },
    { 'Gob. Bug Broth', 'Mailbuster Cetas' },
    { 'Lucky Broth', 'Faithful Falcorr' },
    { 'Mlw. Bird Broth', 'Swift Sieghard' },
    { 'Rzr. Brain Broth', 'Bloodclaw Shasra' },
    { 'Svg. Mole Broth', 'Bugeyed Broncha' },
    { 'Bur. Carrion Broth', 'Gorefang Hobs' },
    { 'Cl. Wheat Broth', 'Gooey Gerard' },
    { 'Shadowy Broth', 'Crude Raphie' },
    { 'Swirling Broth', 'Droopy Dortwin' },
    { 'Spicy Broth', 'Scissorleg Xerin' },
    { 'Salubrious Broth', 'Attentive Ibuki' },
    { 'Fizzy Broth', 'Caring Kiyomaro' },
}

local function words(s)
    local t = {}
    for w in tostring(s or ''):lower():gsub('[^%w%. ]', ''):gmatch('%S+') do t[#t + 1] = w end
    return t
end

-- one word from the table vs one word of the item name; either side may be an abbreviation ("qdv." / "quadav")
local function word_match(a, b)
    if a == b then return true end
    if a:sub(-1) == '.' and b:sub(1, #a - 1) == a:sub(1, -2) then return true end
    if b:sub(-1) == '.' and a:sub(1, #b - 1) == b:sub(1, -2) then return true end
    return false
end

-- pet name (as written in M.pets) for the jug item name, or nil
function M.jug_pet(item_name)
    local iw = words(item_name)
    if #iw == 0 then return nil end
    for _, j in ipairs(jugs) do
        local kw = words(j[1])
        if #kw == #iw then
            local ok = true
            for i = 1, #kw do
                if not word_match(kw[i], iw[i]) then ok = false break end
            end
            if ok then return j[2] end
        end
    end
    return nil
end

return M
