addon.name    = 'chainfinder'
addon.author  = 'you'
addon.version = '2.0.0'
addon.desc    = 'ChainFinder: skillchains for your skill under the menu cursor, Party/Find weapon chains, and Blue Mage chains/bursts.'
addon.link    = ''

require('common')
local chat   = require('chat')
local imgui  = require('imgui')
local ffi    = require('ffi')
local wsdata = require('wsdata')
local petdata = require('petdata')
local theme   = require('theme')
require('aurora')(theme)            -- Aurora skin (delete this line for the classic gold look)

----------------------------------------------------------------------
-- Tunables
----------------------------------------------------------------------
local MAX_STEPS   = 5
local MAX_TYPES   = 5         -- weapon types selectable in the Find and Party windows
local MAX_RESULTS = 500
local MAX_NODES   = 3000000
local NODE_SLICE  = 5000
local MAX_NAMES   = 3
local SCAN_BYTES  = 0x100     -- bytes scanned per menu object during setup/calibrate

----------------------------------------------------------------------
-- Weapon types
----------------------------------------------------------------------
local skill_alias = {
    h2h = 1, handtohand = 1, hth = 1,
    dagger = 2, dag = 2,
    sword = 3, sw = 3,
    greatsword = 4, gs = 4,
    axe = 5,
    greataxe = 6, ga = 6,
    scythe = 7, scy = 7,
    polearm = 8, pole = 8,
    katana = 9, kat = 9,
    greatkatana = 10, gk = 10,
    club = 11,
    staff = 12, stave = 12,
    archery = 25, bow = 25,
    marksmanship = 26, mm = 26, gun = 26,
}

local skill_names = {
    [1] = 'H2H', [2] = 'Dagger', [3] = 'Sword', [4] = 'GreatSword', [5] = 'Axe',
    [6] = 'GreatAxe', [7] = 'Scythe', [8] = 'Polearm', [9] = 'Katana',
    [10] = 'GreatKatana', [11] = 'Club', [12] = 'Staff',
    [25] = 'Archery', [26] = 'Marksmanship',
}

local type_order = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 25, 26 }
local type_short = {
    [1] = 'H2H', [2] = 'Dagger', [3] = 'Sword', [4] = 'GS', [5] = 'Axe', [6] = 'GA',
    [7] = 'Scythe', [8] = 'Polearm', [9] = 'Katana', [10] = 'GK', [11] = 'Club',
    [12] = 'Staff', [25] = 'Archery', [26] = 'MM',
}

local COL_HEAD = theme.C.gold
local COL_ME   = theme.C.amber or theme.C.gold
local COL_TXT  = theme.C.text
local COL_DIM  = theme.C.muted
local COL_WARN = theme.C.warn

local function say(msg)
    print(chat.header(addon.name):append(chat.message(msg)))
end

----------------------------------------------------------------------
-- Level lists: an empty list means "any level"; otherwise the final skillchain
-- must be one of the listed levels (several can be selected).
----------------------------------------------------------------------
local function lv_set(arr)
    if not arr or #arr == 0 then return nil end
    local s = {}
    for _, v in ipairs(arr) do s[v] = true end
    return s
end

local function lv_toggle(arr, v)
    for i, x in ipairs(arr) do
        if x == v then table.remove(arr, i) return end
    end
    arr[#arr + 1] = v
    table.sort(arr)
end

local function lv_has(arr, v)
    for _, x in ipairs(arr) do
        if x == v then return true end
    end
    return false
end

local function lv_label(arr)
    if #arr == 0 then return 'any' end
    return table.concat(arr, ',')
end

local function clean_levels(t)
    local out = {}
    if type(t) == 'table' then
        for _, v in ipairs(t) do
            if type(v) == 'number' and v >= 1 and v <= 4 and v == math.floor(v) and not lv_has(out, v) then
                out[#out + 1] = v
            end
        end
        table.sort(out)
    end
    return out
end

----------------------------------------------------------------------
-- Settings (saved to config/addons/chainfinder/chainfinder.cfg)
----------------------------------------------------------------------
local cfg = {
    -- weapon skill menu profile (flat for older config files)
    menu = '', cur_obj = '', cur_off = -1, cur_base = 0, cnt_obj = '', cnt_off = -1,
    -- pet command > Ready sub menu profile
    ready = { menu = '', cur_obj = '', cur_off = -1, cur_base = 0, cnt_obj = '', cnt_off = -1, order = 'listed' },
    pet   = '',
    frame = 'harlequin',          -- Puppetmaster automaton frame (the game does not tell us)
    direct = true,     -- read the highlighted ability straight from the game (like XIUI); no /sc setup needed
    nm_obj = '', nm_off = -1, nm_ptr = false,     -- where the game keeps the highlighted entry's text (/sc scan)
    fp = {}, cap_bad = {}, cap_good = {},     -- fingerprint that tells the weapon skill list from the Abilities menu
    find  = { types = {}, levels = {}, steps = 2, all = true, blu = false, pet = false, auto = false, petsel = '' },
    party = { types = {}, levels = {}, steps = 2, show_all = false, pos = 'any' },
    self  = { levels = {}, steps = 2, show_all = false, blu = false, pet = false, burst = false, petws = false, wsfirst = false, auto = false },
    scale = 100,                 -- window scale in percent (25-150)
    mini  = { self = false, find = false, party = false, blu = false },   -- chain-creation controls minimized
    blu   = { levels = {}, steps = 2 },
}

local function ser(v)
    local t = type(v)
    if t == 'number' or t == 'boolean' then return tostring(v) end
    if t == 'string' then return ('%q'):format(v) end
    if t == 'table' then
        local parts, n = {}, #v
        for i = 1, n do parts[#parts + 1] = ser(v[i]) end
        for k, val in pairs(v) do
            if type(k) == 'string' then
                parts[#parts + 1] = ('[%q] = %s'):format(k, ser(val))
            end
        end
        return '{ ' .. table.concat(parts, ', ') .. ' }'
    end
    return 'nil'
end

local function cfg_dir()
    return ('%sconfig\\addons\\%s\\'):format(AshitaCore:GetInstallPath(), addon.name)
end

local function save_cfg()
    pcall(function()
        ashita.fs.create_dir(cfg_dir())
        local f = io.open(cfg_dir() .. 'chainfinder.cfg', 'w')
        if f then
            f:write('return ' .. ser(cfg) .. '\n')
            f:close()
        end
    end)
end

local function load_steps(v, default)
    if type(v) == 'number' and v >= 2 and v <= MAX_STEPS and v == math.floor(v) then return v end
    return default
end

local function load_cfg()
    pcall(function()
        local chunk = loadfile(cfg_dir() .. 'chainfinder.cfg')
        if not chunk then return end
        local t = chunk()
        if type(t) ~= 'table' then return end
        if type(t.menu) == 'string' then cfg.menu = t.menu end
        if type(t.cur_obj) == 'string' then cfg.cur_obj = t.cur_obj end
        if type(t.cur_off) == 'number' then cfg.cur_off = t.cur_off end
        if type(t.cur_base) == 'number' then cfg.cur_base = t.cur_base end
        if type(t.cnt_obj) == 'string' then cfg.cnt_obj = t.cnt_obj end
        if type(t.cnt_off) == 'number' then cfg.cnt_off = t.cnt_off end
        if type(t.pet) == 'string' then cfg.pet = t.pet end
        if type(t.frame) == 'string' and petdata.frame_by_key[t.frame] then cfg.frame = t.frame end
        if type(t.direct) == 'boolean' then cfg.direct = t.direct end
        if type(t.nm_obj) == 'string' then cfg.nm_obj = t.nm_obj end
        if type(t.nm_off) == 'number' then cfg.nm_off = t.nm_off end
        if type(t.nm_ptr) == 'boolean' then cfg.nm_ptr = t.nm_ptr end
        if type(t.fp) == 'table' then
            for _, e in ipairs(t.fp) do
                if type(e) == 'string' and e:match('^%a+:%d+:%d+$') then cfg.fp[#cfg.fp + 1] = e end
            end
        end
        for _, nm in ipairs({ 'cap_bad', 'cap_good' }) do
            if type(t[nm]) == 'table' then
                for k, val in pairs(t[nm]) do
                    if type(k) == 'string' and type(val) == 'number' then cfg[nm][k] = val end
                end
            end
        end
        if type(t.ready) == 'table' then
            local r = t.ready
            for _, k in ipairs({ 'menu', 'cur_obj', 'cnt_obj' }) do
                if type(r[k]) == 'string' then cfg.ready[k] = r[k] end
            end
            for _, k in ipairs({ 'cur_off', 'cur_base', 'cnt_off' }) do
                if type(r[k]) == 'number' then cfg.ready[k] = r[k] end
            end
            if r.order == 'listed' or r.order == 'alpha' or r.order == 'id' then cfg.ready.order = r.order end
        end

        -- older configs stored the Find window settings under "party"
        local fsrc = (type(t.find) == 'table') and t.find or t.party
        if type(fsrc) == 'table' then
            local p = fsrc
            if type(p.types) == 'table' then
                cfg.find.types = {}
                for _, id in ipairs(p.types) do
                    if skill_names[id] and #cfg.find.types < MAX_TYPES then
                        cfg.find.types[#cfg.find.types + 1] = id
                    end
                end
            end
            cfg.find.levels = clean_levels(p.levels)
            if #cfg.find.levels == 0 and type(p.level) == 'number' and p.level > 0 then
                cfg.find.levels = clean_levels({ p.level })      -- older config format
            end
            cfg.find.steps = load_steps(p.steps, 2)
            if type(p.all) == 'boolean' then cfg.find.all = p.all end
            if type(p.blu) == 'boolean' then cfg.find.blu = p.blu end
            if type(p.pet) == 'boolean' then cfg.find.pet = p.pet end
            if type(p.auto) == 'boolean' then cfg.find.auto = p.auto end
            if type(p.petsel) == 'string' then cfg.find.petsel = p.petsel end
        end
        if type(t.find) == 'table' and type(t.party) == 'table' then
            local p = t.party
            if type(p.types) == 'table' then
                cfg.party.types = {}
                for _, id in ipairs(p.types) do
                    if skill_names[id] and #cfg.party.types < MAX_TYPES then
                        cfg.party.types[#cfg.party.types + 1] = id
                    end
                end
            end
            cfg.party.levels = clean_levels(p.levels)
            cfg.party.steps = load_steps(p.steps, 2)
            if type(p.show_all) == 'boolean' then cfg.party.show_all = p.show_all end
            if p.pos == 'first' or p.pos == 'last' or p.pos == 'any' then cfg.party.pos = p.pos end
        end
        if type(t.self) == 'table' then
            cfg.self.levels = clean_levels(t.self.levels)
            cfg.self.steps = load_steps(t.self.steps, 2)
            if type(t.self.show_all) == 'boolean' then cfg.self.show_all = t.self.show_all end
            if type(t.self.blu) == 'boolean' then cfg.self.blu = t.self.blu end
            if type(t.self.pet) == 'boolean' then cfg.self.pet = t.self.pet end
            if type(t.self.auto) == 'boolean' then cfg.self.auto = t.self.auto end
            if type(t.self.burst) == 'boolean' then cfg.self.burst = t.self.burst end
            if type(t.self.petws) == 'boolean' then cfg.self.petws = t.self.petws end
            if type(t.self.wsfirst) == 'boolean' then cfg.self.wsfirst = t.self.wsfirst end
        end
        if type(t.scale) == 'number' then cfg.scale = math.max(25, math.min(150, math.floor(t.scale + 0.5))) end
        if type(t.mini) == 'table' then
            for _, k in ipairs({ 'self', 'find', 'party', 'blu' }) do
                if type(t.mini[k]) == 'boolean' then cfg.mini[k] = t.mini[k] end
            end
        end
        if type(t.blu) == 'table' then
            cfg.blu.levels = clean_levels(t.blu.levels)
            cfg.blu.steps = load_steps(t.blu.steps, 2)
        end
    end)
end

----------------------------------------------------------------------
-- Menu / cursor access (menu-name signature as used by other Ashita v4 addons)
----------------------------------------------------------------------
local pGameMenu = 0

local function get_menu()
    if pGameMenu == nil or pGameMenu == 0 then return '', 0, 0 end
    local p = ashita.memory.read_uint32(pGameMenu)
    if p == 0 then return '', 0, 0 end
    local v = ashita.memory.read_uint32(p)
    if v == 0 then return '', 0, 0 end
    local h = ashita.memory.read_uint32(v + 4)
    if h == 0 then return '', v, 0 end
    local name = ashita.memory.read_string(h + 0x46, 16) or ''
    name = name:gsub('%z', ''):gsub('%s+$', '')
    return name, v, h
end

-- EXACT match (ignoring case/extra spaces): a substring match also fired in the Abilities
-- menu, whose name can contain the weapon skill menu's name.
local function norm_menu(n)
    n = (n or ''):lower():gsub('%s+', ' ')
    n = n:gsub('^%s+', ''):gsub('%s+$', '')
    return n
end

local function menu_matches(name, menu)
    menu = menu or cfg.menu
    if menu == '' or name == '' then return false end
    return norm_menu(name) == norm_menu(menu)
end

-- Some menus share a name with lists that must NOT trigger the windows (Abilities, Job Abilities...).
-- /sc setup also looks for a list-size byte next to the cursor value; if found, the menu only counts
-- when that byte equals the number of entries we expect (weapon skills learned / pet Ready moves).
local function profile_gate(P, v, h, expect)
    if P.cnt_off < 0 or not expect or expect <= 0 or v == 0 or h == 0 then return true end
    local addr = (P.cnt_obj == 'header') and h or v
    local ok, val = pcall(ashita.memory.read_uint8, addr + P.cnt_off)
    if not ok then return true end
    return val == expect
end

-- Fingerprint gate (from /sc exclude + /sc include): 32-bit values that are constant in the weapon skill
-- list, constant in the Abilities menu, and different between them. Each entry is "menu|header:offset:value".
local function fp_gate(v, h)
    local n = #cfg.fp
    if n == 0 or v == 0 or h == 0 then return true end
    local hits = 0
    for _, e in ipairs(cfg.fp) do
        local obj, off, val = e:match('^(%a+):(%d+):(%d+)$')
        local addr = (obj == 'header') and h or v
        local ok, got = pcall(ashita.memory.read_uint32, addr + tonumber(off))
        if ok and got == tonumber(val) then hits = hits + 1 end
    end
    return hits >= math.max(1, math.floor(n * 0.7))
end

-- Text gate (from /sc scan): the game keeps the highlighted entry's text somewhere in the menu objects.
-- When that spot is known, the weapon skill list only counts if the text is a known weapon skill name.
local known_names = nil
local function known_name_set()
    if known_names then return known_names end
    known_names = {}
    for _, list in pairs(wsdata.ws) do
        for _, w in ipairs(list) do known_names[petdata.norm(w.name)] = true end
    end
    return known_names
end

local function read_text(base, off, ptr)
    local ok, str = pcall(function()
        local addr = base + off
        if ptr then
            addr = ashita.memory.read_uint32(addr)
            if addr < 0x10000 or addr > 0x7FFFFFFF then return '' end
        end
        return ashita.memory.read_string(addr, 40) or ''
    end)
    if not ok then return '' end
    return (str:match('^[^%z]*') or '')
end

local function text_gate(v, h)
    if cfg.nm_off < 0 or v == 0 or h == 0 then return true end
    local base = (cfg.nm_obj == 'header') and h or v
    return known_name_set()[petdata.norm(read_text(base, cfg.nm_off, cfg.nm_ptr))] == true
end

-- Direct selection reader. Method taken from XIUI (tirem/XIUI v1.8.4, modules/castcost/data.lua):
-- the game's own ability list box is found by signature; +0x40 = entry count, +0x30 = cursor, and the
-- game's GetItem function turns the cursor into the real ability id. No cursor offsets to learn.
local sel = { ok = false, obj_ptr = 0, getitem = 0 }
pcall(function()
    ffi.cdef[[ typedef int32_t (__thiscall* ChainFinder_GetItem_f)(uint32_t, int32_t); ]]
end)

local function sel_init_spell()
    sel.mptr = ashita.memory.find('FFXiMain.dll', 0, '81EC80000000568B35????????578BCE8B7E3057', 0x09, 0)
    sel.spellfn = ashita.memory.find('FFXiMain.dll', 0, '8B44240485C07C??3B41447D??8B49208D04C185C075??83C8FFC204008B108B', 0, 1)
    if sel.spellfn == nil or sel.spellfn == 0 then sel.spellfn = sel.getitem end      -- same function in some clients
    sel.spell_ok = (sel.mptr ~= nil and sel.mptr ~= 0 and sel.spellfn ~= nil and sel.spellfn ~= 0)
end

local function sel_init()
    sel.obj_ptr = ashita.memory.find('FFXiMain.dll', 0, '81EC80000000568B35????????8BCE8B463050E8', 0x09, 0)
    sel.getitem = ashita.memory.find('FFXiMain.dll', 0, '8B44240485C07C??3B41447D??8B49208D04C185C075??83C8FFC204008B108B', 0, 0)
    sel.ok = (sel.obj_ptr ~= nil and sel.obj_ptr ~= 0 and sel.getitem ~= nil and sel.getitem ~= 0)
    sel_init_spell()
end

-- id of the highlighted entry of the game's ability list, or nil
local function list_read(ptr, fnptr)
    if not ptr or ptr == 0 or not fnptr or fnptr == 0 then return nil end
    local ok, id = pcall(function()
        local p = ashita.memory.read_uint32(ptr)
        if p == 0 then return nil end
        local obj = ashita.memory.read_uint32(p)
        if obj == 0 then return nil end
        if ashita.memory.read_int32(obj + 0x40) <= 0 then return nil end
        local idx = ashita.memory.read_int32(obj + 0x30)
        local fn = ffi.cast('ChainFinder_GetItem_f', fnptr)
        return fn(obj, idx)
    end)
    if not ok or id == nil or id < 0 then return nil end
    return id
end

local function sel_read() return sel.ok and list_read(sel.obj_ptr, sel.getitem) or nil end
local function sel_read_spell() return sel.spell_ok and list_read(sel.mptr, sel.spellfn) or nil end

-- name and skill id of a spell (Blue Magic = 43)
local function spell_info(id)
    local ok, n, sk = pcall(function()
        local sp = AshitaCore:GetResourceManager():GetSpellById(id)
        if not sp then return '', 0 end
        return sp.Name[1] or '', sp.Skill or 0
    end)
    if not ok then return '', 0 end
    return n, sk
end

local BLU_JOB = 16
local function player_is_blu()
    local ok, r = pcall(function()
        local p = AshitaCore:GetMemoryManager():GetPlayer()
        return p:GetMainJob() == BLU_JOB or p:GetSubJob() == BLU_JOB
    end)
    return ok and r == true
end

local function ability_name(id)
    local ok, n = pcall(function()
        local a = AshitaCore:GetResourceManager():GetAbilityById(id)
        return a and a.Name[1] or ''
    end)
    return ok and n or ''
end

local function read_hover(P, list, v, h)
    if P.cur_off < 0 or v == 0 or h == 0 then return nil, nil, nil end
    local addr = (P.cur_obj == 'header') and h or v
    local ok, raw = pcall(ashita.memory.read_uint8, addr + P.cur_off)
    if not ok then return nil, nil, nil end
    local idx = raw - P.cur_base + 1
    return list[idx], idx, raw
end

----------------------------------------------------------------------
-- Player data (used by the Self window only)
----------------------------------------------------------------------
-- Ready moves of the current pet (Pet Commands > Ready)
local ready = { pet = nil, label = '(no pet)', known = false, moves = {}, classes = {}, by_key = {}, sig = '' }

local ws_by_id = {}
for _, list in pairs(wsdata.ws) do
    for _, w in ipairs(list) do ws_by_id[w.id] = w end
end

local mine = { classes = {}, sig = '', label = '(none)', count = 0, main = {}, learned = {}, types = {},
                skill = nil, verified = true }
local warned_has = false

local function equipped_skill(slot)
    local inv = AshitaCore:GetMemoryManager():GetInventory()
    local eq = inv:GetEquippedItem(slot)
    if eq == nil or eq.Index == 0 then return 0 end
    local container = bit.rshift(bit.band(eq.Index, 0xFF00), 8)
    local index     = bit.band(eq.Index, 0x00FF)
    local item = inv:GetContainerItem(container, index)
    if item == nil or item.Id == 0 or item.Id == 65535 then return 0 end
    local r = AshitaCore:GetResourceManager():GetItemById(item.Id)
    if r == nil then return 0 end
    return r.Skill or 0
end

local function has_ws(id)
    local ok, r = pcall(function()
        return AshitaCore:GetMemoryManager():GetPlayer():HasWeaponSkill(id)
    end)
    if ok then return r end
    return nil
end

-- Weapon skill ids come in blocks per weapon type; the weapon skill MENU lists the skills you
-- have learned in id order, and that includes skills with NO skillchain property (Spirits
-- Within, Sanguine Blade, ...). Those must be counted or the cursor lands on the wrong skill.
local WS_BLOCK = {
    [1] = { 1, 15 },    [2] = { 16, 31 },   [3] = { 32, 47 },   [4] = { 48, 63 },
    [5] = { 64, 79 },   [6] = { 80, 95 },   [7] = { 96, 111 },  [8] = { 112, 127 },
    [9] = { 128, 143 }, [10] = { 144, 159 }, [11] = { 160, 175 }, [12] = { 176, 191 },
    [25] = { 192, 207 }, [26] = { 208, 223 },
}

local function ws_name(id)
    local ok, n = pcall(function()
        local a = AshitaCore:GetResourceManager():GetAbilityById(id)
        return a and a.Name and a.Name[1]
    end)
    if ok and type(n) == 'string' and n ~= '' then return n end
    return ('Skill #%d'):format(id)
end

-- Every weapon skill you have learned for this weapon type, in id (menu) order.
-- Returns the list and whether the learned check was possible.
local function learned_list(skill)
    local blk = WS_BLOCK[skill]
    local ids = {}
    if blk then
        for id = blk[1], blk[2] do ids[#ids + 1] = id end
    end
    for _, w in ipairs(wsdata.ws[skill] or {}) do          -- extras such as ids 224+
        if not blk or w.id > blk[2] then ids[#ids + 1] = w.id end
    end
    table.sort(ids)

    local out, verified = {}, true
    for _, id in ipairs(ids) do
        local h = has_ws(id)
        local w = ws_by_id[id]
        if h == nil then
            verified = false
            if w then out[#out + 1] = w end                  -- cannot verify: known skills only
        elseif h then
            out[#out + 1] = w or { id = id, name = ws_name(id), props = {}, skill = skill }
        end
    end
    return out, verified
end

-- learned    = learned skills that HAVE chain properties (main hand + ranged)
-- menu       = main-hand weapon skill menu, in order, including skills with no property
local function my_skill_list()
    local learned, menu, labels, types = {}, {}, {}, {}
    local verified = true

    local msk = equipped_skill(0)
    if msk == 0 then msk = 1 end              -- bare hands = hand-to-hand
    if wsdata.ws[msk] then
        local list, ok = learned_list(msk)
        verified = verified and ok
        menu = list
        for _, w in ipairs(list) do
            if #w.props > 0 then learned[#learned + 1] = w end
        end
        labels[#labels + 1] = skill_names[msk] or tostring(msk)
        types[#types + 1] = msk
    end

    local rsk = equipped_skill(2)             -- 2 = ranged slot
    if rsk == 25 or rsk == 26 then
        local list, ok = learned_list(rsk)
        verified = verified and ok
        for _, w in ipairs(list) do
            if #w.props > 0 then learned[#learned + 1] = w end
        end
        labels[#labels + 1] = skill_names[rsk]
        types[#types + 1] = rsk
    end

    if not verified and not warned_has then
        warned_has = true
        say('Could not check which weapon skills you have learned; showing known skills for your weapon type.')
    end
    return learned, table.concat(labels, ' + '), menu, msk, verified, types
end

----------------------------------------------------------------------
-- Classes: skills with identical property lists chain identically, so they are
-- grouped. A step is shown as "Rampage/Vorpal Blade/Calamity (+4)".
-- by_type = true keeps different weapon types apart (needed for "use every type").
----------------------------------------------------------------------
local function make_classes(list, is_mine, by_type)
    local by, out = {}, {}
    for _, w in ipairs(list) do
        local key = table.concat(w.props, '|')
        if by_type then key = tostring(w.skill) .. '#' .. key end
        local c = by[key]
        if not c then
            c = { props = w.props, names = {}, mine = is_mine, skill = by_type and w.skill or nil }
            by[key] = c
            out[#out + 1] = c
        end
        c.names[#c.names + 1] = w.name
    end
    for _, c in ipairs(out) do table.sort(c.names) end
    return out
end

local function build_pool(skill_ids, by_type)
    local list = {}
    for _, id in ipairs(skill_ids) do
        for _, w in ipairs(wsdata.ws[id] or {}) do list[#list + 1] = w end
    end
    return make_classes(list, false, by_type)
end

-- physical blue magic as hoverable entries (Chain Affinity): key 'b:<spell id>'
local blu_by_id, blu_by_key, blu_all = {}, {}, {}
for _, r in ipairs(wsdata.blu_physical) do
    local props = {}
    for i = 3, #r do props[#props + 1] = r[i] end
    local name = r[2]
    if wsdata.blu_ul[name] then name = name .. ' (U)' end
    local e = { id = r[1], name = name, props = props, key = 'b:' .. r[1] }
    blu_by_id[r[1]] = e
    blu_by_key[e.key] = e
    blu_all[#blu_all + 1] = e
end

local function build_blu_pool()
    local list = {}
    for _, r in ipairs(wsdata.blu_physical) do
        local props = {}
        for i = 3, #r do props[#props + 1] = r[i] end
        local name = r[2]
        if wsdata.blu_ul[name] then name = name .. ' (U)' end
        list[#list + 1] = { id = r[1], name = name, props = props }
    end
    local out = make_classes(list, false, false)
    for _, c in ipairs(out) do c.extra = true; c.blu = true end
    return out
end

----------------------------------------------------------------------
-- Chain search (coroutine, sliced per frame)
--
-- g = { steps, levels (set or nil = any), pool, pos?, cover?, tag? }
-- mine_classes (optional): when given, exactly one step is one of these (Self window);
-- when nil every step comes from g.pool (Party and BLU windows).
-- g.cover (optional): list of weapon type ids that must each appear at least once.
----------------------------------------------------------------------
local function positions(pos, n)
    if pos == 'first' then return { 1 } end
    if pos == 'last' then return { n } end
    local t = {}
    for i = 1, n do t[i] = i end
    return t
end

local function run_search(g, e, mine_classes)
    local N, target, pool = g.steps, g.levels, g.pool
    local cover = g.cover
    local ncover = cover and #cover or 0
    local cover_set = {}
    if cover then
        for _, id in ipairs(cover) do cover_set[id] = true end
    end
    local used, ncovered = {}, 0
    local nodes, stop = 0, false
    local memo = {}
    local seq, rs, ls = {}, {}, {}

    local function accept(lv) return target == nil or target[lv] == true end

    local function use(c, d)
        if ncover == 0 or not c.skill or not cover_set[c.skill] then return end
        local before = used[c.skill] or 0
        used[c.skill] = before + d
        if before == 0 and d > 0 then
            ncovered = ncovered + 1
        elseif before + d == 0 and d < 0 then
            ncovered = ncovered - 1
        end
    end

    -- can a chain in state (name, lv) be continued exactly k more steps and end on an accepted level?
    local function reach(name, lv, k)
        if k == 0 then return accept(lv) end
        if lv == 4 then return false end
        local key = name .. lv .. ':' .. k
        local m = memo[key]
        if m ~= nil then return m end
        local ok = false
        for pass = 1, 2 do
            local list = (pass == 1) and pool or mine_classes
            if list then
                for _, c in ipairs(list) do
                    local l, r = wsdata.check({ name }, c.props)
                    if r and reach(r, l, k - 1) then ok = true break end
                end
            end
            if ok then break end
        end
        memo[key] = ok
        return ok
    end

    local function tick()
        nodes = nodes + 1
        if nodes % NODE_SLICE == 0 then
            e.nodes = nodes
            coroutine.yield()
        end
        if nodes >= MAX_NODES then e.capped = true stop = true end
    end

    -- A chain of L steps. Every skill is listed on its own line (no "A/B/C" grouping), so a step that
    -- several skills share is expanded into one line per skill.
    local seen = {}
    local function record(L)
        if g.need_extra or g.need_weap then
            -- toggles: only chains that actually use a BLU spell / pet move (extra) or a weapon skill (weap)
            local flag = g.need_weap and 'weap' or 'extra'
            local has = false
            for i = 1, L do
                if seq[i][flag] then has = true break end
            end
            if not has then return end
        end
        local counts, ix = {}, {}
        for i = 1, L do counts[i] = #seq[i].names; ix[i] = 1 end
        while true do
            if #e.results >= MAX_RESULTS then e.capped = true stop = true return end
            local segs, key = {}, {}
            for i = 1, L do
                local nm = seq[i].names[ix[i]]
                if i > 1 then segs[#segs + 1] = { text = ' > ', col = COL_TXT } end
                segs[#segs + 1] = { text = nm, col = (seq[i].mine or (g.hover and nm == g.hover)) and COL_ME or COL_TXT, blu = seq[i].blu and nm or nil }
                key[i] = nm
                if i > 1 then
                    local rname = (ls[i] == 4) and (rs[i] .. ' (Lv4)') or rs[i]
                    segs[#segs + 1] = { text = ' = ', col = COL_TXT }
                    segs[#segs + 1] = { text = rname, col = wsdata.colors[rs[i]] or COL_TXT }
                    key[i] = nm .. '=' .. rs[i]
                end
            end
            if g.tag then
                local el = wsdata.elements[rs[L]]
                if el then segs[#segs + 1] = { text = '   burst: ' .. table.concat(el, '/'), col = COL_DIM } end
            end
            local k = table.concat(key, '>')
            if not seen[k] then
                seen[k] = true
                e.results[#e.results + 1] = { segs = segs, key = k, res = rs[L], n = L }
            end
            local j = L
            while j >= 1 do
                ix[j] = ix[j] + 1
                if ix[j] <= counts[j] then break end
                ix[j] = 1
                j = j - 1
            end
            if j < 1 then break end
        end
    end

    -- Only chains of exactly N steps are listed.
    local p = 0
    local function dfs(step, active)
        local list = (mine_classes and step == p) and mine_classes or pool
        for _, c in ipairs(list) do
            if stop then return end
            tick()
            local lv, res = wsdata.check(active, c.props)
            if res then
                seq[step] = c
                use(c, 1)
                if ncover == 0 or (ncover - ncovered) <= (N - step) then
                    rs[step], ls[step] = res, lv
                    if step == N then
                        if accept(lv) and (ncover == 0 or ncovered == ncover) then record(N) end
                    elseif lv ~= 4 and reach(res, lv, N - step) then
                        dfs(step + 1, { res })
                    end
                end
                use(c, -1)
            end
        end
    end

    local plist = mine_classes and positions(g.pos or 'any', N) or { 0 }
    for _, pp in ipairs(plist) do
        if stop then break end
        p = pp
        local first = (mine_classes and p == 1) and mine_classes or pool
        for _, c in ipairs(first) do
            if stop then break end
            seq[1] = c
            use(c, 1)
            if ncover == 0 or (ncover - ncovered) <= (N - 1) then dfs(2, c.props) end
            use(c, -1)
        end
    end
end

----------------------------------------------------------------------
-- Search contexts: Self, Party and BLU each have their own cached results.
----------------------------------------------------------------------
local ctx_self  = { kind = 'self',  cache = {}, pool = {} }
local ctx_rself = { kind = 'rself', cache = {}, pool = {} }   -- Ready moves chaining with each other
local ctx_bweap = { kind = 'bweap', cache = {}, pool = {} }   -- hovered blue spell + your weapon's skills (no extras)
local ctx_pweap = { kind = 'pweap', cache = {}, pool = {} }   -- hovered Ready move + other Ready moves + your weapon skills
local ctx_rweap = { kind = 'rweap', cache = {}, pool = {} }   -- hovered Ready move + your equipped weapon's skills
local ctx_find = { kind = 'find', cache = {}, pool = {} }
local ctx_party = { kind = 'party', cache = {}, pool = {} }
local ctx_blu   = { kind = 'blu',   cache = {}, pool = {} }

-- Find: pet chosen from the drop-down (cfg.find.petsel = petdata key), '' = the pet that is out / jug in ammo
local pet_pick_cache = {}
local function pick_pool(key)
    local c = pet_pick_cache[key]
    if c then return c end
    local pet = petdata.pets[key]
    local list = {}
    for _, mname in ipairs(pet and pet.moves or {}) do
        local a = petdata.by_norm[petdata.norm(mname)]
        if a and #a.props > 0 then list[#list + 1] = { name = a.name, props = a.props } end
    end
    c = make_classes(list, false, false)
    for _, cl in ipairs(c) do cl.extra = true end
    pet_pick_cache[key] = c
    return c
end

-- base pool + the optional BLU spell / pet move classes toggled in the Self and Find windows
local function with_extras(base, o, petpool)
    if not (o.blu or o.pet or o.auto) then return base end
    local t = {}
    for _, c in ipairs(base) do t[#t + 1] = c end
    if o.auto then for _, c in ipairs(pick_pool(petdata.norm(petdata.frame_pet(cfg.frame)))) do t[#t + 1] = c end end
    if o.blu then for _, c in ipairs(ctx_blu.pool) do t[#t + 1] = c end end
    if o.pet then for _, c in ipairs(petpool or ctx_rself.pool) do t[#t + 1] = c end end
    return t
end

local function params(ctx)
    if ctx.kind == 'bweap' then
        -- exactly one step is the spell; the rest are weapon skills. "WS First" pins the spell to the LAST step,
        -- so the chain starts with a weapon skill and ends with the spell.
        return { steps = cfg.self.steps, levels = lv_set(cfg.self.levels), pos = cfg.self.wsfirst and 'last' or 'any', pool = ctx.pool }
    end
    if ctx.kind == 'rself' then
        return { steps = cfg.self.steps, levels = lv_set(cfg.self.levels), pos = 'any', pool = ctx.pool }
    elseif ctx.kind == 'pweap' then
        local t = {}
        for _, c in ipairs(ctx_rself.pool) do t[#t + 1] = c end
        for _, c in ipairs(ctx_self.pool) do
            t[#t + 1] = { props = c.props, names = c.names, mine = false, skill = c.skill, weap = true }
        end
        return { steps = cfg.self.steps, levels = lv_set(cfg.self.levels), pos = 'any', pool = t, need_weap = true }
    elseif ctx.kind == 'self' or ctx.kind == 'rweap' then
        return { steps = cfg.self.steps, levels = lv_set(cfg.self.levels), pos = 'any', pool = with_extras(ctx.pool, cfg.self), need_extra = (cfg.self.blu or cfg.self.pet or cfg.self.auto) }
    elseif ctx.kind == 'party' then
        return { steps = cfg.party.steps, levels = lv_set(cfg.party.levels), pos = cfg.party.pos, pool = ctx.pool }
    elseif ctx.kind == 'blu' then
        return { steps = cfg.blu.steps, levels = lv_set(cfg.blu.levels), pool = ctx.pool, tag = true }
    end
    local g = { steps = cfg.find.steps, levels = lv_set(cfg.find.levels), pool = with_extras(ctx.pool, cfg.find, (cfg.find.petsel ~= '') and pick_pool(cfg.find.petsel) or nil), need_extra = (cfg.find.blu or cfg.find.pet or cfg.find.auto) }
    local nt = #cfg.find.types
    if cfg.find.all and nt >= 1 and nt <= cfg.find.steps then g.cover = cfg.find.types end
    return g
end

local function get_entry(ctx, key)
    local e = ctx.cache[key]
    if e then return e end
    e = { results = {}, capped = false, nodes = 0, status = 'running' }
    if ctx.kind == 'rweap' or ctx.kind == 'bweap' then ctx.pool = ctx_self.pool end

    local mc = nil
    local g = params(ctx)
    local skip = (#g.pool == 0)
    if ctx.kind == 'self' or ctx.kind == 'party' or ctx.kind == 'rself' or ctx.kind == 'pweap' or ctx.kind == 'rweap' or ctx.kind == 'bweap' then
        if key == 'all' then
            mc = mine.classes
        elseif key == 'rall' then
            mc = ready.classes
        elseif type(key) == 'number' and ws_by_id[key] then
            mc = make_classes({ ws_by_id[key] }, true, false)
        elseif type(key) == 'string' and ready.by_key[key] then
            mc = make_classes({ ready.by_key[key] }, true, false)
        elseif key == 'ball' then
            mc = make_classes(blu_all, true, false)
        elseif type(key) == 'string' and blu_by_key[key] then
            mc = make_classes({ blu_by_key[key] }, true, false)
        else
            mc = {}
        end
        if #mc == 0 then skip = true end
        g.hover = (#mc == 1 and mc[1].mine) and mc[1].names[1] or nil
    end

    if skip then
        e.status = 'done'
    else
        e.co = coroutine.create(function() run_search(g, e, mc) end)
    end
    ctx.cache[key] = e
    return e
end

local function step_entry(e)
    if e.status ~= 'running' then return end
    local ok, err = coroutine.resume(e.co)
    if not ok then
        e.status = 'error'
        e.err = tostring(err)
        return
    end
    if coroutine.status(e.co) == 'dead' then
        table.sort(e.results, function(a, b)
            if a.n ~= b.n then return a.n < b.n end
            return a.key < b.key
        end)
        e.status = 'done'
    end
end

-- "my" side of a search: learned skills only, unless Show all WS is on
local function rebuild_mine_classes()
    local list = {}
    if cfg.self.show_all then
        for _, sk in ipairs(mine.types) do
            for _, w in ipairs(wsdata.ws[sk] or {}) do list[#list + 1] = w end
        end
    else
        list = mine.learned
    end
    mine.classes = make_classes(list, true, false)
    mine.count = #list
end

-- the other steps of a self chain: also learned skills only, unless Show all WS is on
local function rebuild_self_pool()
    ctx_self.cache = {}; ctx_rweap.cache = {}; ctx_bweap.cache = {}; ctx_pweap.cache = {}
    if not mine.skill then ctx_self.pool = {} return end
    if cfg.self.show_all or not mine.verified then
        ctx_self.pool = build_pool({ mine.skill }, false)
    else
        local list = {}
        for _, w in ipairs(mine.main) do
            if #w.props > 0 then list[#list + 1] = w end
        end
        ctx_self.pool = make_classes(list, false, false)
    end
end

local function self_show_all_changed()
    rebuild_mine_classes()
    rebuild_self_pool()
    save_cfg()
end

local function rebuild_find_pool()
    ctx_find.cache = {}
    ctx_find.pool = build_pool(cfg.find.types, true)
end

local function self_changed()
    ctx_self.cache = {}; ctx_rweap.cache = {}; ctx_bweap.cache = {}
    ctx_rself.cache = {}; ctx_pweap.cache = {}
    save_cfg()
end

local function find_changed()
    rebuild_find_pool()
    save_cfg()
end

-- Party pool = ONLY the weapon types toggled in the Party window. Exactly one step of each chain
-- is the skill under the cursor (mine); every other step comes from this pool. My own weapon's
-- skills are in the pool only if my weapon type is toggled on (then: my learned skills, or all
-- of them with Show all WS). So axe selected + H2H toggled gives axe/H2H chains, never axe > axe.
local function rebuild_party_pool()
    ctx_party.cache = {}
    local list, seen = {}, {}
    local function add(w)
        if #w.props > 0 and not seen[w.id] then
            seen[w.id] = true
            list[#list + 1] = w
        end
    end
    for _, id in ipairs(cfg.party.types) do
        if id == mine.skill and not cfg.party.show_all and mine.verified then
            for _, w in ipairs(mine.main) do add(w) end
        else
            for _, w in ipairs(wsdata.ws[id] or {}) do add(w) end
        end
    end
    ctx_party.pool = make_classes(list, false, false)
end

local function party_changed()
    rebuild_party_pool()
    save_cfg()
end

local function blu_changed()
    ctx_blu.cache = {}
    save_cfg()
end

local function refresh_mine(force)
    local ok, learned, label, menu, msk, verified, types = pcall(my_skill_list)
    if not ok then return end
    local ids = {}
    for _, w in ipairs(menu) do ids[#ids + 1] = w.id end
    ids[#ids + 1] = '|'
    for _, w in ipairs(learned) do ids[#ids + 1] = w.id end
    local sig = table.concat(ids, ',') .. (verified and 'v' or 'u')
    if sig == mine.sig and msk == mine.skill and not force then return end
    mine.sig      = sig
    mine.skill    = msk
    mine.label    = label
    mine.main     = menu
    mine.learned  = learned
    mine.types    = types
    mine.verified = verified
    rebuild_mine_classes()
    rebuild_self_pool()
    rebuild_party_pool()
end

----------------------------------------------------------------------
-- Pet / Ready moves
----------------------------------------------------------------------
-- name of the item in the ammo slot (slot 3), or nil
local function ammo_item_name()
    local ok, nm = pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory()
        local eq = inv:GetEquippedItem(3)
        if eq == nil or eq.Index == 0 then return nil end
        local container = bit.rshift(bit.band(eq.Index, 0xFF00), 8)
        local index     = bit.band(eq.Index, 0x00FF)
        local item = inv:GetContainerItem(container, index)
        if item == nil or item.Id == 0 or item.Id == 65535 then return nil end
        local r = AshitaCore:GetResourceManager():GetItemById(item.Id)
        return r and r.Name[1] or nil
    end)
    if ok and type(nm) == 'string' and nm ~= '' then return nm end
    return nil
end

local PUP_JOB, BST_JOB = 18, 9
local function player_is_pup()
    local ok, r = pcall(function()
        local p = AshitaCore:GetMemoryManager():GetPlayer()
        local m, sj = p:GetMainJob(), p:GetSubJob()
        return m == PUP_JOB or (sj == PUP_JOB and m ~= BST_JOB)
    end)
    return ok and r == true
end

local function find_pet_entry(pname)
    local pk = petdata.norm(pname or '')
    if pk == '' then return nil end
    local pet = petdata.pets[pk]
    if pet then return pet end
    for k, v in pairs(petdata.pets) do                 -- tolerate extra text in the entity name
        if pk:find(k, 1, true) or k:find(pk, 1, true) then return v end
    end
    return nil
end

-- Which pet's Ready moves to use: a name set with /sc pet, else the pet that is out, else the pet the jug in
-- your ammo slot would summon. Returns name, source ('manual' | 'summoned' | 'jug'), jug item name
local function pet_name()
    if cfg.pet ~= '' then return cfg.pet, 'manual' end
    local ok, name = pcall(function()
        local mm = AshitaCore:GetMemoryManager()
        local ent = mm:GetEntity()
        local pidx = mm:GetParty():GetMemberTargetIndex(0)
        local petidx = ent:GetPetTargetIndex(pidx)
        if petidx == nil or petidx == 0 then return nil end
        return ent:GetName(petidx)
    end)
    local summoned = (ok and type(name) == 'string' and name ~= '') and name or nil
    if summoned and find_pet_entry(summoned) then return summoned, 'summoned' end
    -- A pet that is not a jug pet we know, while you are a Puppetmaster (main, or sub unless you are a BST main):
    -- that is the automaton, and its skills come from the frame you chose.
    if summoned and player_is_pup() then return petdata.frame_pet(cfg.frame), 'automaton' end
    local jug = ammo_item_name()
    local jp = jug and petdata.jug_pet(jug) or nil
    if jp then return jp, 'jug', jug end
    if summoned then return summoned, 'summoned' end
    return nil
end

local function refresh_ready(force)
    local pname, psrc, pjug = pet_name()
    local sig = (pname or '') .. '|' .. cfg.ready.order
    if sig == ready.sig and not force then return end
    ready.sig, ready.pet, ready.src, ready.jug = sig, pname, psrc, pjug
    ready.auto = (psrc == 'automaton') or (petdata.pets[petdata.norm(pname or '')] or {}).auto == true
    ready.moves, ready.by_key, ready.classes = {}, {}, {}
    ctx_rself.cache, ctx_party.cache, ctx_rweap.cache, ctx_self.cache, ctx_find.cache, ctx_bweap.cache = {}, {}, {}, {}, {}, {}
    ctx_rself.pool = {}
    ctx_pweap.cache = {}

    local pet = find_pet_entry(pname)
    ready.known = pet ~= nil
    ready.label = pet and pet.name or (pname or '(no pet)')
    if pet and pet.auto then ready.label = pet.name end
    if pet and psrc == 'jug' then ready.label = pet.name .. ' (from ' .. (pjug or 'jug') .. ')' end
    if not pet then return end

    local list = {}
    for i, mname in ipairs(pet.moves) do
        local a = petdata.by_norm[petdata.norm(mname)]
        list[#list + 1] = {
            name = a and a.name or mname, props = a and a.props or {}, id = a and a.id or 0,
            ord = i, key = 'r:' .. petdata.norm(mname), skill = 'pet',
        }
    end
    if cfg.ready.order == 'alpha' then
        table.sort(list, function(a, b) return a.name < b.name end)
    elseif cfg.ready.order == 'id' then
        table.sort(list, function(a, b)
            local ia, ib = (a.id > 0) and a.id or 1e9, (b.id > 0) and b.id or 1e9
            if ia ~= ib then return ia < ib end
            return a.ord < b.ord
        end)
    end

    local chain_list = {}
    for _, m in ipairs(list) do
        ready.by_key[m.key] = m
        if #m.props > 0 then chain_list[#chain_list + 1] = m end
    end
    ready.moves = list
    ready.classes = make_classes(chain_list, true, false)
    ctx_rself.pool = make_classes(chain_list, false, false)
    for _, c in ipairs(ctx_rself.pool) do c.extra = true end
end

----------------------------------------------------------------------
-- Find type selection
----------------------------------------------------------------------
local find_msg = { text = '', t_end = 0 }

local function find_has(id)
    for _, t in ipairs(cfg.find.types) do
        if t == id then return true end
    end
    return false
end

local function find_toggle(id)
    for i, t in ipairs(cfg.find.types) do
        if t == id then
            table.remove(cfg.find.types, i)
            find_changed()
            return true
        end
    end
    if #cfg.find.types >= MAX_TYPES then
        find_msg = { text = ('Max %d weapon types - deselect one first.'):format(MAX_TYPES),
                      t_end = os.clock() + 3 }
        return false
    end
    cfg.find.types[#cfg.find.types + 1] = id
    table.sort(cfg.find.types)
    find_changed()
    return true
end

local party_msg = { text = '', t_end = 0 }

local function party_has(id)
    for _, t in ipairs(cfg.party.types) do
        if t == id then return true end
    end
    return false
end

local function party_toggle(id)
    for i, t in ipairs(cfg.party.types) do
        if t == id then
            table.remove(cfg.party.types, i)
            party_changed()
            return
        end
    end
    if #cfg.party.types >= MAX_TYPES then
        party_msg = { text = ('Max %d weapon types - deselect one first.'):format(MAX_TYPES),
                      t_end = os.clock() + 3 }
        return
    end
    cfg.party.types[#cfg.party.types + 1] = id
    table.sort(cfg.party.types)
    party_changed()
end

----------------------------------------------------------------------
-- Blue Mage magic-burst table: one row per skillchain (name + level)
----------------------------------------------------------------------
local burst_rows = {}

local function build_burst_rows()
    burst_rows = {}
    local seen = {}
    for _, combos in pairs(wsdata.chain) do
        for _, r in pairs(combos) do
            local lv, name = r[1], r[2]
            local key = name .. lv
            if not seen[key] and wsdata.elements[name] then
                seen[key] = true
                burst_rows[#burst_rows + 1] = { name = name, lv = lv, elems = wsdata.elements[name] }
            end
        end
    end
    table.sort(burst_rows, function(a, b)
        if a.lv ~= b.lv then return a.lv < b.lv end
        return a.name < b.name
    end)
end

local function burst_spell_text(element)
    local names = {}
    for _, n in ipairs(wsdata.blu_magic[element] or {}) do
        names[#names + 1] = wsdata.blu_ul_magic[n] and (n .. ' (U)') or n
    end
    return ('%s: %s'):format(element, table.concat(names, ', '))
end

----------------------------------------------------------------------
-- Drawing helpers
----------------------------------------------------------------------
local function btn(label, id, selected)
    return theme.toggle(label, id, selected)
end

local function button_row(title, opts, current, idp, on_pick)
    imgui.TextColored(COL_DIM, title)
    for i, o in ipairs(opts) do
        imgui.SameLine()
        if btn(o.text, idp .. i, current == o.value) then on_pick(o.value) end
    end
end

-- multi-select level row: "Any" clears, 1-4 toggle
local function level_row(levels, idp, on_change)
    imgui.TextColored(COL_DIM, 'Level:')
    imgui.SameLine()
    if btn('Any', idp .. 'A', #levels == 0) then
        for i = #levels, 1, -1 do table.remove(levels, i) end
        on_change()
    end
    for lv = 1, 4 do
        imgui.SameLine()
        if btn(tostring(lv), idp .. lv, lv_has(levels, lv)) then
            lv_toggle(levels, lv)
            on_change()
        end
    end
end

local frame_opts = {}
for _, f in ipairs(petdata.frames) do frame_opts[#frame_opts + 1] = { text = f.name, value = f.key } end

local function set_frame(v)
    cfg.frame = v
    save_cfg()
    refresh_ready(true)
    self_changed()
    find_changed()
end

local steps_opts = {
    { text = '2', value = 2 }, { text = '3', value = 3 }, { text = '4', value = 4 }, { text = '5', value = 5 },
}
local mix_opts = {
    { text = 'Use every selected type', value = true }, { text = 'Any combination', value = false },
}

-- Burst lines: "BURST WIND" in the element's colour, then the blue spells that can burst it.
--   unlearned = grey, learned = green, learned AND in your equipped blue magic set = gold + bold
local ELEMENT_COL = {
    Fire = { 1.00, 0.45, 0.35, 1 }, Ice = { 0.60, 0.88, 1.00, 1 }, Wind = { 0.50, 0.95, 0.60, 1 },
    Earth = { 0.85, 0.70, 0.40, 1 }, Lightning = { 0.85, 0.60, 1.00, 1 }, Water = { 0.40, 0.65, 1.00, 1 },
    Light = { 1.00, 0.97, 0.75, 1 }, Dark = { 0.70, 0.55, 0.90, 1 },
}
local COL_LEARNED = theme.C.green
local COL_SET     = theme.C.amber or theme.C.gold

local blu_name_id = nil          -- spell name (lower) -> spell id, built once from the game's spell list
local function blu_ids()
    if blu_name_id then return blu_name_id end
    blu_name_id = {}
    for id = 512, 1023 do
        local nm, sk = spell_info(id)
        if sk == 43 and nm ~= '' then blu_name_id[nm:lower()] = id end
    end
    return blu_name_id
end

-- element of each burst-capable blue spell, and which chain results that element can burst
local blu_magic_el = {}
for el, list in pairs(wsdata.blu_magic) do
    for _, n in ipairs(list) do blu_magic_el[n:lower()] = el end
end
local CHAIN_LEVEL = {
    Transfixion = 1, Compression = 1, Liquefaction = 1, Scission = 1, Reverberation = 1, Detonation = 1,
    Induration = 1, Impaction = 1, Gravitation = 2, Distortion = 2, Fusion = 2, Fragmentation = 2,
    Light = 3, Darkness = 3,
}
local function bursts_off(el)
    local out = {}
    for prop, els in pairs(wsdata.elements) do
        for _, e in ipairs(els) do
            if e == el then out[#out + 1] = prop break end
        end
    end
    table.sort(out, function(a, b)
        if (CHAIN_LEVEL[a] or 9) ~= (CHAIN_LEVEL[b] or 9) then return (CHAIN_LEVEL[a] or 9) < (CHAIN_LEVEL[b] or 9) end
        return a < b
    end)
    return out
end

local function draw_magic_spell_info(sp)
    local el = blu_magic_el[(sp.name or ''):lower():gsub(' %(U%)$', '')]
    if not el then
        imgui.TextColored(COL_WARN, sp.name .. ' is neither a physical spell nor a known magic burst blue spell.')
        return
    end
    imgui.TextColored(COL_DIM, sp.name .. ' cannot be part of a skillchain (not physical), but it can magic burst.')
    imgui.TextColored(ELEMENT_COL[el] or COL_DIM, 'ELEMENT  ' .. el:upper())
    imgui.TextColored(COL_DIM, 'Bursts off these skillchains:')
    local last
    for _, prop in ipairs(bursts_off(el)) do
        local lv = CHAIN_LEVEL[prop]
        if lv ~= last then
            last = lv
            imgui.TextColored(COL_DIM, ('  Level %d'):format(lv or 0))
        end
        imgui.TextColored(wsdata.colors[prop] or COL_TXT, '      ' .. prop:upper())
    end
end

local burst_items = {}           -- element -> { {name, id, label}, ... }
local burst_state = { t = -10 }  -- id -> 'set' | 'learned' (refreshed every 1.5 s)
local blu_set = { seen = false, ids = {} }     -- equipped blue magic set, from packet 0x044

local function refresh_burst_state(now)
    if now - burst_state.t < 1.5 then return end
    burst_state.t = now
    local player = nil
    pcall(function() player = AshitaCore:GetMemoryManager():GetPlayer() end)
    for el, items in pairs(burst_items) do
        for _, it in ipairs(items) do
            local st = nil
            if it.id and player then
                local ok, has = pcall(function() return player:HasSpell(it.id) end)
                if ok and has then st = blu_set.ids[it.id] and 'set' or 'learned' end
            end
            burst_state[it.name] = st
        end
    end
end

local function burst_list(el)
    if burst_items[el] then return burst_items[el] end
    local ids, items = blu_ids(), {}
    for _, n in ipairs(wsdata.blu_magic[el] or {}) do
        items[#items + 1] = { name = n, id = ids[n:lower()], label = wsdata.blu_ul_magic[n] and (n .. ' (U)') or n }
    end
    burst_items[el] = items
    return items
end

local function draw_burst_lines(res, now, learned_only)
    for _, el in ipairs(wsdata.elements[res] or {}) do
        local items = burst_list(el)
        imgui.TextColored(ELEMENT_COL[el] or COL_DIM, '      BURST ' .. el:upper())
        refresh_burst_state(now)
        if learned_only then
            -- only spells you have learned (equipped ones are learned too)
            local keep = {}
            for _, it in ipairs(items) do
                if burst_state[it.name] then keep[#keep + 1] = it end
            end
            items = keep
        end
        local indent, avail = 36, imgui.GetWindowWidth() - 30
        local x = indent
        for i, it in ipairs(items) do
            local txt = it.label .. (i < #items and ', ' or '')
            local w = theme.text_w(txt)
            local st = burst_state[it.name]
            local col = (st == 'set' and COL_SET) or (st == 'learned' and COL_LEARNED) or COL_DIM
            if i > 1 and x + w <= avail then
                imgui.SameLine(0, 0)
            else
                imgui.SetCursorPosX(indent)
                x = indent
            end
            if st == 'set' then
                -- fake bold: the same text twice, one pixel apart
                local cx, cy = imgui.GetCursorPos()
                imgui.TextColored(col, txt)
                imgui.SetCursorPos({ cx + 1, cy })
                imgui.TextColored(col, txt)
            else
                imgui.TextColored(col, txt)
            end
            x = x + w
        end
        if #items == 0 then imgui.TextColored(COL_DIM, learned_only and '      (none learned)' or '      (no blue magic for this element)') end
    end
end

-- one result line; blue spells in it use the same colours as the burst lists:
-- not learned = grey, learned = green, learned + in your equipped set = gold + bold
local line_state = { t = -10 }
local function blu_state(name)
    local now = os.clock()
    if now - line_state.t > 1.5 then line_state = { t = now } end
    local base = (name:gsub(' %(U%)$', ''))
    local st = line_state[base]
    if st ~= nil then return st end
    st = false
    local id = blu_ids()[base:lower()]
    if id then
        local ok, has = pcall(function() return AshitaCore:GetMemoryManager():GetPlayer():HasSpell(id) end)
        if ok and has then st = blu_set.ids[id] and 'set' or 'learned' end
    end
    line_state[base] = st
    return st
end

local function draw_line(r)
    for i, s in ipairs(r.segs) do
        if i > 1 then imgui.SameLine(0, 0) end
        if s.blu then
            local st = blu_state(s.blu)
            local col = (st == 'set' and COL_SET) or (st == 'learned' and COL_LEARNED) or COL_DIM
            if st == 'set' then
                local cx, cy = imgui.GetCursorPos()
                imgui.TextColored(col, s.text)
                imgui.SetCursorPos({ cx + 1, cy })
                imgui.TextColored(col, s.text)
            else
                imgui.TextColored(col, s.text)
            end
        else
            imgui.TextColored(s.col, s.text)
        end
    end
end

local function draw_results(ctx, key, idp, empty_msg, height, burst)
    local e = get_entry(ctx, key)
    step_entry(e)

    if e.status == 'error' then
        imgui.TextColored(COL_WARN, 'Error: ' .. tostring(e.err))
    elseif empty_msg then
        imgui.TextColored(COL_DIM, empty_msg)
    elseif e.status == 'running' then
        imgui.TextColored(COL_DIM, ('searching... (%d found)'):format(#e.results))
    elseif e.capped then
        imgui.TextColored(COL_DIM, ('showing first %d results (more exist)'):format(#e.results))
    elseif #e.results == 0 then
        imgui.TextColored(COL_DIM, '(no skillchains found)')
    else
        imgui.TextColored(COL_DIM, ('%d skillchain(s)'):format(#e.results))
    end

    if #e.results > 0 and not empty_msg then
        imgui.BeginChild('cf_list_' .. idp, { 0, height or 0 }, true)
        theme.child_scale()
        for _, r in ipairs(e.results) do
            draw_line(r)
            if burst and r.res then draw_burst_lines(r.res, os.clock()) end
        end
        imgui.EndChild()
    end
end

local function draw_skill_header(hovered, menu_open, idx, wmode)
    local isready = (wmode == 'ready')
    local P = isready and cfg.ready or cfg
    local total = isready and #ready.moves or #mine.main
    if hovered then
        imgui.TextColored(COL_ME, hovered.name)
        imgui.SameLine()
        if #hovered.props == 0 then
            imgui.TextColored(COL_WARN, '  [no skillchain property]')
        else
            imgui.TextColored(COL_DIM, '  [' .. table.concat(hovered.props, '/') .. ']')
        end
        if wmode ~= 'blu' then
            imgui.SameLine()
            imgui.TextColored(COL_DIM, ('  (%d of %d)'):format(idx or 0, total))
        end
    elseif menu_open and P.cur_off < 0 then
        imgui.TextColored(COL_WARN, ('Cursor not set up - showing everything (type /sc setup%s)'):format(isready and ' ready' or ''))
    elseif menu_open then
        imgui.TextColored(COL_WARN, 'Cursor unreadable - showing everything')
    elseif isready then
        imgui.TextColored(COL_HEAD, ('Pinned: %s Ready moves (%d)'):format(ready.label, #ready.moves))
    else
        imgui.TextColored(COL_HEAD, ('Pinned: %s (%d weapon skills)'):format(mine.label, mine.count))
    end
end

----------------------------------------------------------------------
-- Menu-driven state
----------------------------------------------------------------------
local pinned    = { pet = false, self = false, party = false, find = false, blu = false, settings = false }
local self_auto  = true     -- Self opens by itself in the menus; closing it turns this off until /sc self
local warned_same = false
local open_flag = { self = { true }, party = { true }, find = { true }, blu = { true }, settings = { true } }
local was_hit   = false
local debug_on  = false
local last_name = nil
local last_check = 0
local last_pet_check = 0
local hover     = { id = nil, raw = nil, idx = nil }

local learn, calib, setup, cap = nil, nil, nil, nil
local scanreq = nil        -- /sc scan: { t, deep }

local function list_join(t, sep) return table.concat(t, sep) end

local function sample_into(stats, v, h)
    for _, o in ipairs({ { 'menu', v }, { 'header', h } }) do
        if o[2] ~= 0 then
            for off = 0, SCAN_BYTES - 1 do
                local val = ashita.memory.read_uint8(o[2] + off)
                local key = o[1] .. ':' .. off
                local st = stats[key]
                if not st then
                    stats[key] = { obj = o[1], off = off, last = val, min = val, max = val,
                                   changes = 0, pm1 = 0, n = 1 }
                else
                    st.n = st.n + 1
                    if val ~= st.last then
                        st.changes = st.changes + 1
                        if math.abs(val - st.last) == 1 then st.pm1 = st.pm1 + 1 end
                        st.last = val
                    end
                    if val < st.min then st.min = val end
                    if val > st.max then st.max = val end
                end
            end
        end
    end
end

local function cursor_candidates(stats, limit)
    local cands = {}
    for _, st in pairs(stats) do
        if st.pm1 >= 3 and st.changes <= st.pm1 + 1 and st.changes < st.n * 0.15
           and st.max > st.min and (st.max - st.min) <= limit then
            cands[#cands + 1] = st
        end
    end
    table.sort(cands, function(a, b) return a.pm1 > b.pm1 end)
    return cands
end

-- P = the menu profile being calibrated (cfg for weapon skills, cfg.ready for Ready)
local function finish_calib(stats, P, count, kind)
    local cands = cursor_candidates(stats, count + 1)
    if #cands == 0 then
        say(('No cursor value found for the %s menu. Keep it open, start on the FIRST entry, move down to the'):format(kind == 'ready' and 'Ready' or 'weapon skill'))
        say(('last one and back up a few times, then run /sc setup%s again.'):format(kind == 'ready' and ' ready' or ''))
        return
    end
    local best = cands[1]
    P.cur_obj, P.cur_off, P.cur_base = best.obj, best.off, best.min
    say(('Cursor found: %s+0x%X, first entry = %d (%d candidates).'):format(best.obj, best.off, best.min, #cands))
    for i = 2, math.min(#cands, 3) do
        say(('   alt: %s+0x%X (moves seen: %d)'):format(cands[i].obj, cands[i].off, cands[i].pm1))
    end

    -- a list-size byte next to the cursor lets us tell this list apart from same-named menus
    local cnt
    for _, st in pairs(stats) do
        if st.changes == 0 and st.n >= 8 and st.min == count and st.obj == best.obj
           and st.off ~= best.off and math.abs(st.off - best.off) <= 0x20 then
            if not cnt or math.abs(st.off - best.off) < math.abs(cnt.off - best.off) then cnt = st end
        end
    end
    if cnt then
        P.cnt_obj, P.cnt_off = cnt.obj, cnt.off
        say(('List size field found: %s+0x%X = %d. The menu only counts when it matches.'):format(cnt.obj, cnt.off, count))
    else
        P.cnt_obj, P.cnt_off = '', -1
        say('No list-size field found, so this menu is recognised by its name only.')
    end
    save_cfg()
end

-- 32-bit snapshot of both menu objects, small values only (counts/flags/ids, not memory addresses)
local function snap_dwords(v, h)
    local t = {}
    for _, o in ipairs({ { 'menu', v }, { 'header', h } }) do
        if o[2] ~= 0 then
            for off = 0, SCAN_BYTES - 4, 4 do
                local ok, val = pcall(ashita.memory.read_uint32, o[2] + off)
                if ok then t[o[1] .. ':' .. off] = val end
            end
        end
    end
    return t
end

local function capture_sample(c, v, h)
    c.n = c.n + 1
    for k, val in pairs(snap_dwords(v, h)) do
        if c.vals[k] == nil then c.vals[k] = val
        elseif c.vals[k] ~= val then c.varied[k] = true end
    end
end

local function compute_fp()
    local fp = {}
    for k, g in pairs(cfg.cap_good) do
        local b = cfg.cap_bad[k]
        if b ~= nil and b ~= g then fp[#fp + 1] = ('%s:%d'):format(k, g) end
    end
    table.sort(fp)
    while #fp > 32 do table.remove(fp) end
    cfg.fp = fp
end

local function finish_capture(c)
    local consts = {}
    local count = 0
    if c.n >= 5 then
        for k, val in pairs(c.vals) do
            if not c.varied[k] and val < 0x10000 then consts[k] = val; count = count + 1 end
        end
    end
    if count == 0 then
        say('capture: nothing was read - open the menu first, keep it open, then run the command again.')
        return
    end
    cfg[c.kind == 'bad' and 'cap_bad' or 'cap_good'] = consts
    compute_fp()
    save_cfg()
    local have_bad, have_good = next(cfg.cap_bad) ~= nil, next(cfg.cap_good) ~= nil
    say(('capture: saved the %s menu (%d values).'):format(c.kind == 'bad' and 'Abilities' or 'Weapon Skills', count))
    if not (have_bad and have_good) then
        say(('Now do the other one: %s.'):format(have_bad and '/sc include in the Weapon Skills list' or '/sc exclude in the Abilities menu'))
    elseif #cfg.fp == 0 then
        say('The two menus look identical to me, so I could not tell them apart. Try again with both menus fully open')
        say('and the cursor on the first entry, or send me /sc debug output.')
    else
        say(('Fingerprint ready (%d markers). The Self window now ignores the Abilities menu.'):format(#cfg.fp))
    end
end

local function finish_learn()
    local seen = learn.seen
    learn = nil
    if #seen == 0 then
        say('learn: no menus were seen. Open Abilities > Weapon Skills right after typing /sc learn.')
        return
    end
    cfg.menu = seen[#seen]
    save_cfg()
    say('learn: menus seen: ' .. list_join(seen, '  >  '))
    say(('learn: weapon skill menu set to "%s"'):format(cfg.menu))
end

----------------------------------------------------------------------
-- Windows
----------------------------------------------------------------------
-- Mini mode: the chain-creation controls (levels / steps / toggles) can be hidden; the summary stays on one line.
local function lv_text(levels)
    if #levels == 0 then return 'Any' end
    local t = {}
    for i, v in ipairs(levels) do t[i] = tostring(v) end
    table.sort(t)
    return table.concat(t, ',')
end

-- Mini mode: the header's "-" button hides the chain-creation controls, shrinks the window to a compact size and
-- the same corner button ("+") brings it all back at its old size.
local MINI_SIZE = { self = { 440, 250 }, find = { 440, 260 }, party = { 440, 250 }, blu = { 440, 260 } }
local FULL_SIZE = { self = { 560, 320 }, find = { 600, 460 }, party = { 620, 420 }, blu = { 640, 560 } }
local mini_full, mini_req, mini_seen, cur_size = {}, {}, {}, {}

local function win_size()
    local ok, a, b = pcall(imgui.GetWindowSize)
    if not ok then return nil end
    if type(a) == 'table' then return { a.x or a[1], a.y or a[2] } end
    if type(a) == 'number' and type(b) == 'number' then return { a, b } end
    return nil
end

-- call BEFORE theme.begin: applies a pending compact / restore size (and compacts a window saved as minimized)
local function mini_apply(wk)
    if not mini_seen[wk] then
        mini_seen[wk] = true
        if cfg.mini[wk] then mini_req[wk] = { MINI_SIZE[wk][1], MINI_SIZE[wk][2] } end
    end
    local r = mini_req[wk]
    if r then
        mini_req[wk] = nil
        imgui.SetNextWindowSize({ r[1], r[2] }, ImGuiCond_Always)
    end
end

-- call right after theme.begin (before theme.header)
local function mini_measure(wk) cur_size[wk] = win_size() end

local function mini_click(wk)
    local m = not cfg.mini[wk]
    cfg.mini[wk] = m
    if m then
        mini_full[wk] = cur_size[wk] or { FULL_SIZE[wk][1], FULL_SIZE[wk][2] }
        mini_req[wk] = { MINI_SIZE[wk][1], MINI_SIZE[wk][2] }
    else
        mini_req[wk] = mini_full[wk] or { FULL_SIZE[wk][1], FULL_SIZE[wk][2] }
    end
    save_cfg()
end

-- shows the controls summary while minimized; returns true when the controls should be drawn
local function mini_bar(wk, summary)
    if cfg.mini[wk] then
        if summary then imgui.TextColored(COL_DIM, summary) end
        return false
    end
    return true
end

-- mini mode: nothing but the chain list for the current selection
local function mini_list(ctx, key, idp, burst, msg, learned_only)
    local e = get_entry(ctx, key)
    step_entry(e)
    local list = e.results
    if learned_only then
        -- BLU: only chains whose blue spells you have learned (equipped ones count, they are learned too)
        list = {}
        for _, r in ipairs(e.results) do
            local ok = true
            for _, sg in ipairs(r.segs) do
                if sg.blu and not blu_state(sg.blu) then ok = false break end
            end
            if ok then list[#list + 1] = r end
        end
    end
    if msg then
        imgui.TextColored(COL_DIM, msg)
    elseif e.status == 'error' then
        imgui.TextColored(COL_WARN, 'Error: ' .. tostring(e.err))
    elseif #list == 0 then
        imgui.TextColored(COL_DIM, e.status == 'running' and 'searching...' or
            (learned_only and '(no skillchains with learned or equipped spells)' or '(no skillchains found)'))
    else
        imgui.BeginChild('cf_mini_' .. idp, { 0, 0 }, false)
        theme.child_scale()
        for _, r in ipairs(list) do
            draw_line(r)
            if (burst or learned_only) and r.res then draw_burst_lines(r.res, os.clock(), learned_only) end
        end
        imgui.EndChild()
    end
end

-- Font scale 25-150% at the bottom right of every ChainFinder window. Applied live while you drag; saved on release.
local scale_pending = nil
local function frame_h() return 28 end      -- fixed: the scale control never changes size

local function res_h()
    return -(frame_h() + 12)       -- leave room for the footer under the results list
end

local function scale_footer(idp)
    imgui.SetWindowFontScale(1.0)               -- the scale control itself is always drawn at 100%
    local fh = frame_h()
    local y = imgui.GetWindowHeight() - fh - 8
    if imgui.GetCursorPosY() < y then imgui.SetCursorPosY(y) end
    local sw = 130
    local total = theme.text_w('Scale') + sw + theme.btn_w('100%') + 3 * 8
    local x = imgui.GetWindowWidth() - total - 20
    if x > imgui.GetCursorPosX() then imgui.SetCursorPosX(x) end
    imgui.TextColored(COL_DIM, 'Scale')
    imgui.SameLine()
    imgui.SetNextItemWidth(sw)
    local v = { cfg.scale }
    if imgui.SliderInt('##cf_scale' .. idp, v, 25, 150, '%d%%') then
        -- live: the text rescales every frame while you drag
        cfg.scale = math.max(25, math.min(150, v[1]))
        theme.set_scale(cfg.scale / 100)
        scale_pending = true
    end
    if scale_pending and not imgui.IsItemActive() then
        scale_pending = nil
        save_cfg()                       -- written once, when you let go
    end
    imgui.SameLine()
    if theme.ghost('100%##cf_s100' .. idp) then
        scale_pending = nil
        cfg.scale = 100
        theme.set_scale(1.0)
        save_cfg()
    end
    imgui.SetWindowFontScale(theme.ui_scale)
end

local function draw_self_window(hovered, menu_open, key, idx, wmode)
    local isready = (wmode == 'ready')
    local isblu = (wmode == 'blu')
    imgui.SetNextWindowPos({ 100, 300 }, ImGuiCond_FirstUseEver)
    imgui.SetNextWindowSize({ 560, 320 }, ImGuiCond_FirstUseEver)
    open_flag.self[1] = true
    mini_apply('self')
    if theme.begin(isblu and 'ChainFinder - Blue Chains' or (isready and 'ChainFinder - Pet Chains' or 'ChainFinder - Self'), open_flag.self) then
        mini_measure('self')
        if cfg.mini.self then
            if theme.mini_corner() then mini_click('self') end
            mini_list(isblu and ctx_bweap or (isready and (cfg.self.petws and ctx_pweap or ctx_rself) or ctx_self), key, 'self', isblu and cfg.self.burst,
                (hovered and #hovered.props == 0) and (hovered.name .. ' has no skillchain property.') or nil, isblu)
        else
        local mh
        if isblu then
            mh = theme.header(open_flag.self, 'BLUE', 'CHAINS', 'Chain Affinity spell + your weapon skills', cfg.mini.self)
        else
            mh = theme.header(open_flag.self, isready and 'PET' or 'SELF', 'CHAINS', isready and (ready.label .. (ready.auto and ' skills' or ' Ready moves')) or 'Your weapon skills', cfg.mini.self)
        end
        if mh then mini_click('self') end
        draw_skill_header(hovered, menu_open, idx, wmode)
        local sum = ('Level: %s   Steps: %d'):format(lv_text(cfg.self.levels), cfg.self.steps)
        if isblu and cfg.self.wsfirst then sum = sum .. '   WS First' end
        if cfg.self.show_all then sum = sum .. '   all WS' end
        if mini_bar('self', sum) then
        if isblu then
            imgui.TextColored(COL_DIM, ('Chains made with the spell under the cursor (Chain Affinity) and %s %s skills%s.'):format(
                cfg.self.show_all and 'all' or 'your learned', skill_names[mine.skill or 0] or 'weapon',
                cfg.self.wsfirst and ' - weapon skill first, spell last' or ''))
        elseif isready then
            if cfg.self.petws then
                imgui.TextColored(COL_DIM, ('Chains between the Ready move under the cursor (%s), other Ready moves and %s %s skills (at least one weapon skill).'):format(
                    ready.label, cfg.self.show_all and 'all' or 'your learned', skill_names[mine.skill or 0] or 'weapon'))
            else
                imgui.TextColored(COL_DIM, ('Chains between the Ready move under the cursor and other %s Ready moves.'):format(ready.label))
            end
            if ready.auto then
                button_row('Frame:', frame_opts, cfg.frame, 'sFr', set_frame)
                imgui.TextColored(COL_DIM, "Automaton skills depend on the frame, and the game doesn't tell me yours - pick it above.")
            end
            if not ready.known then
                imgui.TextColored(COL_WARN, "Pet isn't in petdata.lua - add it there, or name it with /sc pet <name>.")
            end
        else
            local scope = cfg.self.show_all and 'all' or 'your learned'
            imgui.TextColored(COL_DIM, ('Chains between %s %s skills.'):format(
                scope, skill_names[mine.skill or 0] or 'weapon'))
            if not mine.verified and not cfg.self.show_all then
                imgui.TextColored(COL_WARN, "Couldn't read your learned skills - listing every known skill.")
            end
        end

        level_row(cfg.self.levels, 'sL', self_changed)
        button_row('Steps:', steps_opts, cfg.self.steps, 'sS', function(v)
            cfg.self.steps = v
            self_changed()
        end)
        if isready then
            if btn('Weapon skills' .. (cfg.self.petws and '  [on]' or ''), 'sPws', cfg.self.petws) then
                cfg.self.petws = not cfg.self.petws
                self_changed()
            end
            if cfg.self.petws then
                imgui.SameLine()
                if btn('Show all WS' .. (cfg.self.show_all and '  [on]' or ''), 'sAll', cfg.self.show_all) then
                    cfg.self.show_all = not cfg.self.show_all
                    self_show_all_changed()
                end
            end
        elseif btn('Show all WS' .. (cfg.self.show_all and '  [on]' or ''), 'sAll', cfg.self.show_all) then
            cfg.self.show_all = not cfg.self.show_all
            self_show_all_changed()
        end

        -- extra step sources: lets you see whether spells / your pet can chain with your weapon skills
        if isblu then
            imgui.SameLine()
            if btn('WS First' .. (cfg.self.wsfirst and '  [on]' or ''), 'sWsf', cfg.self.wsfirst) then
                cfg.self.wsfirst = not cfg.self.wsfirst
                self_changed()
            end
            imgui.SameLine()
            if btn('BURST' .. (cfg.self.burst and '  [on]' or ''), 'sBurst', cfg.self.burst) then
                cfg.self.burst = not cfg.self.burst
                save_cfg()
            end
            if cfg.self.burst then
                imgui.TextColored(COL_DIM, 'Burst spells:')
                imgui.SameLine()
                imgui.TextColored(COL_DIM, 'not learned')
                imgui.SameLine()
                imgui.TextColored(COL_LEARNED, 'learned')
                imgui.SameLine()
                imgui.TextColored(COL_SET, 'learned + set')
                if not blu_set.seen then
                    imgui.TextColored(COL_WARN, 'Equipped set not seen yet - zone or change a spell to update it.')
                end
            end
        elseif not isready then
            imgui.TextColored(COL_DIM, 'Also use:')
            imgui.SameLine()
            if btn('BLU spells' .. (cfg.self.blu and '  [on]' or ''), 'sBlu', cfg.self.blu) then
                cfg.self.blu = not cfg.self.blu
                self_changed()
            end
            imgui.SameLine()
            if btn('Pet moves' .. (cfg.self.pet and '  [on]' or ''), 'sPet', cfg.self.pet) then
                cfg.self.pet = not cfg.self.pet
                self_changed()
            end
            imgui.SameLine()
            if btn('Automaton' .. (cfg.self.auto and '  [on]' or ''), 'sAuto', cfg.self.auto) then
                cfg.self.auto = not cfg.self.auto
                self_changed()
            end
            if cfg.self.auto then
                button_row('Frame:', frame_opts, cfg.frame, 'sAF', set_frame)
            end
            if cfg.self.pet and #ctx_rself.pool == 0 then
                imgui.TextColored(COL_WARN, 'No pet moves known - call your pet out (or /sc pet <name>).')
            end
        end

        end   -- controls (mini mode)

        imgui.Separator()
        local msg = nil
        if hovered and #hovered.props == 0 then
            msg = isblu and (hovered.name .. ' is not a physical spell, so Chain Affinity cannot make it a skillchain step.')
                or (hovered.name .. ' has no skillchain property, so it cannot open or close a chain.')
        elseif isready and #ready.classes == 0 then
            msg = 'No Ready moves with skillchain properties for ' .. ready.label .. '. (/sc ready shows what I know.)'
        elseif #mine.classes == 0 and not isready then
            msg = 'No usable weapon skills for your equipped weapon.'
        end
        if isblu and hovered and #hovered.props == 0 then
            draw_magic_spell_info(hovered)
        else
            draw_results(isblu and ctx_bweap or (isready and (cfg.self.petws and ctx_pweap or ctx_rself) or ctx_self), key, 'self', msg, res_h(), isblu and cfg.self.burst)
        end
        scale_footer('s')
        end   -- not mini
    end
    theme.finish()
    if not open_flag.self[1] then
        pinned.self = false
        pinned.pet = false
        self_auto = false          -- stays closed until /sc self
    end
end

local function draw_find_window()
    imgui.SetNextWindowPos({ 680, 300 }, ImGuiCond_FirstUseEver)
    imgui.SetNextWindowSize({ 600, 460 }, ImGuiCond_FirstUseEver)
    open_flag.find[1] = true
    mini_apply('find')
    if theme.begin('ChainFinder - Find', open_flag.find) then
        mini_measure('find')
        if cfg.mini.find then
            if theme.mini_corner() then mini_click('find') end
            mini_list(ctx_find, 'x', 'find')
        else
        if theme.header(open_flag.find, 'FIND', 'CHAINS', 'Chains between the weapon types you pick', cfg.mini.find) then mini_click('find') end
        local nt = #cfg.find.types
        local fsum = ('Types: %d   Level: %s   Steps: %d'):format(nt, lv_text(cfg.find.levels), cfg.find.steps)
        if mini_bar('find', fsum) then
        imgui.TextColored(COL_DIM, ('Weapon types (%d/%d) - chains use only the selected types:'):format(nt, MAX_TYPES))
        for i, id in ipairs(type_order) do
            if (i - 1) % 5 ~= 0 then imgui.SameLine() end
            if btn(type_short[id], 't' .. id, find_has(id)) then find_toggle(id) end
        end
        if os.clock() < find_msg.t_end then
            imgui.TextColored(COL_WARN, find_msg.text)
        end
        imgui.TextColored(COL_DIM, 'Also use:')
        imgui.SameLine()
        if btn('BLU spells' .. (cfg.find.blu and '  [on]' or ''), 'fBlu', cfg.find.blu) then
            cfg.find.blu = not cfg.find.blu
            find_changed()
        end
        imgui.SameLine()
        if btn('Pet moves' .. (cfg.find.pet and '  [on]' or ''), 'fPet', cfg.find.pet) then
            cfg.find.pet = not cfg.find.pet
            find_changed()
        end
        imgui.SameLine()
        if btn('Automaton' .. (cfg.find.auto and '  [on]' or ''), 'fAuto', cfg.find.auto) then
            cfg.find.auto = not cfg.find.auto
            find_changed()
        end
        if cfg.find.auto then
            button_row('Frame:', frame_opts, cfg.frame, 'fAF', set_frame)
        end
        -- pet drop-down: any pet in petdata, or Auto (the pet that is out / the jug in your ammo slot)
        imgui.TextColored(COL_DIM, 'Pet:')
        imgui.SameLine()
        local selp = (cfg.find.petsel ~= '') and petdata.pets[cfg.find.petsel] or nil
        local preview = selp and selp.name or ('Auto (' .. (ready.label or '(no pet)') .. ')')
        imgui.SetNextItemWidth(260)
        if imgui.BeginCombo('##fpetsel', preview) then
            theme.child_scale()
            if imgui.Selectable('Auto (summoned pet / jug in ammo slot)', cfg.find.petsel == '') then
                cfg.find.petsel = ''
                find_changed()
            end
            local keys = {}
            for k in pairs(petdata.pets) do keys[#keys + 1] = k end
            table.sort(keys, function(a, b) return petdata.pets[a].name < petdata.pets[b].name end)
            for _, k in ipairs(keys) do
                if imgui.Selectable(petdata.pets[k].name .. '##fp' .. k, cfg.find.petsel == k) then
                    cfg.find.petsel = k
                    cfg.find.pet = true            -- choosing a pet means you want its moves used
                    find_changed()
                end
            end
            imgui.EndCombo()
        end
        if cfg.find.pet and cfg.find.petsel == '' and #ctx_rself.pool == 0 then
            imgui.TextColored(COL_WARN, 'No pet moves known - call your pet out, equip its jug, or pick a pet above.')
        end

        level_row(cfg.find.levels, 'pL', find_changed)
        button_row('Steps:', steps_opts, cfg.find.steps, 'pS', function(v)
            cfg.find.steps = v
            find_changed()
        end)
        button_row('Mix:', mix_opts, cfg.find.all, 'pA', function(v)
            cfg.find.all = v
            find_changed()
        end)
        if cfg.find.all and nt > cfg.find.steps then
            imgui.TextColored(COL_DIM, '(more types than steps: showing any combination)')
        end
        end   -- controls (mini mode)

        imgui.Separator()
        local msg = nil
        if nt == 0 and not (cfg.find.blu or cfg.find.pet or cfg.find.auto) then msg = 'Pick at least one weapon type above (or turn on BLU spells / Pet moves / Automaton).' end
        draw_results(ctx_find, 'x', 'find', msg, res_h())
        scale_footer('f')
        end   -- not mini
    end
    theme.finish()
    if not open_flag.find[1] then
        pinned.find = false            -- closed: stays closed until /sc find
    end
end

local pos_opts = {
    { text = 'Any', value = 'any' }, { text = 'First (mine opens)', value = 'first' },
    { text = 'Last (mine closes)', value = 'last' },
}

local function draw_party_window(hovered, menu_open, key, idx, wmode)
    local isready = (wmode == 'ready')
    local isblu = (wmode == 'blu')
    imgui.SetNextWindowPos({ 100, 300 }, ImGuiCond_FirstUseEver)
    imgui.SetNextWindowSize({ 620, 420 }, ImGuiCond_FirstUseEver)
    open_flag.party[1] = true
    mini_apply('party')
    if theme.begin('ChainFinder - Party', open_flag.party) then
        mini_measure('party')
        if cfg.mini.party then
            if theme.mini_corner() then mini_click('party') end
            mini_list(ctx_party, key, 'party')
        else
        if theme.header(open_flag.party, 'PARTY', 'CHAINS', 'Your skill under the cursor + other weapons', cfg.mini.party) then mini_click('party') end
        draw_skill_header(hovered, menu_open, idx, wmode)
        local psum = ('Weapons: %d   Level: %s   Steps: %d'):format(#cfg.party.types, lv_text(cfg.party.levels), cfg.party.steps)
        if mini_bar('party', psum) then
        imgui.TextColored(COL_DIM, ('Chains between the %s under the cursor (%s) and the weapons below (%d/%d):'):format(
            isblu and 'blue magic spell' or (isready and 'Ready move' or 'skill'),
            isblu and 'Chain Affinity' or (isready and ready.label or ('your ' .. (skill_names[mine.skill or 0] or 'weapon'))),
            #cfg.party.types, MAX_TYPES))
        for i, id in ipairs(type_order) do
            if (i - 1) % 5 ~= 0 then imgui.SameLine() end
            if btn(type_short[id], 'qt' .. id, party_has(id)) then party_toggle(id) end
        end
        if os.clock() < party_msg.t_end then
            imgui.TextColored(COL_WARN, party_msg.text)
        end
        if not isready and not mine.verified and not cfg.party.show_all then
            imgui.TextColored(COL_WARN, "Couldn't read your learned skills - listing every known skill.")
        end
        imgui.TextColored(COL_DIM, 'Own-weapon chains (e.g. axe > axe) only appear if your own weapon is toggled on.')

        level_row(cfg.party.levels, 'qL', party_changed)
        button_row('Steps:', steps_opts, cfg.party.steps, 'qS', function(v)
            cfg.party.steps = v
            party_changed()
        end)
        button_row('Cursor skill:', pos_opts, cfg.party.pos, 'qP', function(v)
            cfg.party.pos = v
            party_changed()
        end)
        if btn('Show all WS' .. (cfg.party.show_all and '  [on]' or ''), 'qAll', cfg.party.show_all) then
            cfg.party.show_all = not cfg.party.show_all
            party_changed()
        end
        end   -- controls (mini mode)

        imgui.Separator()
        local msg = nil
        if hovered and #hovered.props == 0 then
            msg = hovered.name .. ' has no skillchain property, so it cannot open or close a chain.'
        elseif isready and #ready.classes == 0 then
            msg = 'No Ready moves with skillchain properties for ' .. ready.label .. '. (/sc ready shows what I know.)'
        elseif not isready and #mine.classes == 0 then
            msg = 'No usable weapon skills for your equipped weapon.'
        elseif #cfg.party.types == 0 then
            msg = 'Toggle at least one weapon above. (Your own chains are in the Self window.)'
        end
        draw_results(ctx_party, key, 'party', msg, res_h())
        scale_footer('p')
        end   -- not mini
    end
    theme.finish()
    if not open_flag.party[1] then pinned.party = false end   -- closed: Self resumes
end

local function draw_blu_window()
    imgui.SetNextWindowPos({ 300, 120 }, ImGuiCond_FirstUseEver)
    imgui.SetNextWindowSize({ 640, 560 }, ImGuiCond_FirstUseEver)
    open_flag.blu[1] = true
    mini_apply('blu')
    if theme.begin('ChainFinder - BLU chains', open_flag.blu) then
        mini_measure('blu')
        if cfg.mini.blu then
            if theme.mini_corner() then mini_click('blu') end
            mini_list(ctx_blu, 'x', 'blu', nil, nil, true)
        else
        if theme.header(open_flag.blu, 'BLU', 'CHAINS', 'Chain Affinity and Burst Affinity', cfg.mini.blu) then mini_click('blu') end
        imgui.TextColored(COL_HEAD, 'Chain Affinity: skillchains made only with physical blue magic')
        imgui.TextColored(COL_DIM, '(U) = needs Unbridled Learning. Grey text after a chain = elements it can be burst with.')

        if mini_bar('blu', ('Level: %s   Steps: %d'):format(lv_text(cfg.blu.levels), cfg.blu.steps)) then
        level_row(cfg.blu.levels, 'bL', blu_changed)
        button_row('Steps:', steps_opts, cfg.blu.steps, 'bS', function(v)
            cfg.blu.steps = v
            blu_changed()
        end)
        end   -- controls (mini mode)

        draw_results(ctx_blu, 'x', 'blu', nil, 210)

        imgui.Separator()
        imgui.TextColored(COL_HEAD, 'Burst Affinity: blue magic that can magic burst each skillchain')
        imgui.TextColored(COL_DIM, 'Use Burst Affinity, then cast a spell whose element matches the chain.')
        imgui.BeginChild('cf_burst', { 0, res_h() }, true)
        theme.child_scale()
        local want = lv_set(cfg.blu.levels)
        for i, row in ipairs(burst_rows) do
            if want == nil or want[row.lv] then
                local head = ('%s (Lv%d)  -  %s##br%d'):format(row.name, row.lv, table.concat(row.elems, '/'), i)
                if imgui.CollapsingHeader(head) then
                    for _, el in ipairs(row.elems) do
                        imgui.TextWrapped(burst_spell_text(el))
                    end
                end
            end
        end
        imgui.EndChild()
        scale_footer('b')
        end   -- not mini
    end
    theme.finish()
    if not open_flag.blu[1] then pinned.blu = false end
end


----------------------------------------------------------------------
-- Settings window (/sc settings): every one-off command as a button, plus live status
----------------------------------------------------------------------
local pet_buf = { '' }
local set_cache = { t = -10, names = {} }

local function run_cmd(c)
    AshitaCore:GetChatManager():QueueCommand(1, c)
end

local function cmd_button(label, command, tip, w)
    if theme.toggle(label, 'cmd' .. command, false, w and { w, 0 } or nil) then run_cmd(command) end
    if tip and imgui.IsItemHovered() then imgui.SetTooltip(tip .. '\n(' .. command .. ')') end
end

local function status_line(label, ok, text)
    imgui.TextColored(COL_DIM, label)
    imgui.SameLine()
    imgui.TextColored(ok and theme.C.green or COL_WARN, text)
end

local function draw_settings_window()
    imgui.SetNextWindowPos({ 420, 160 }, ImGuiCond_FirstUseEver)
    imgui.SetNextWindowSize({ 540, 620 }, ImGuiCond_FirstUseEver)
    open_flag.settings[1] = true
    if theme.begin('ChainFinder - Settings', open_flag.settings) then
        theme.header(open_flag.settings, 'CHAIN', 'FINDER', ('Settings   v%s'):format(addon.version))

        -- windows ---------------------------------------------------------------
        theme.caption('WINDOWS')
        if btn('Self', 'wSelf', pinned.self) then run_cmd('/sc self') end
        imgui.SameLine()
        if btn('Party', 'wParty', pinned.party) then run_cmd('/sc party') end
        imgui.SameLine()
        if btn('Find', 'wFind', pinned.find) then run_cmd('/sc find') end
        imgui.SameLine()
        if btn('BLU chains', 'wBlu', pinned.blu) then run_cmd('/sc blu') end
        if btn('Open Self / Blue chains by themselves in the menus' .. (self_auto and '  [on]' or '  [off]'), 'wAuto', self_auto) then
            self_auto = not self_auto
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Closing the Self window with X turns this off until you click it here or type /sc self.')
        end

        -- window options (the same toggles that live inside the windows) ----------------
        imgui.Spacing()
        theme.caption('WINDOW OPTIONS')
        if btn('Show all WS (Self / Blue chains)' .. (cfg.self.show_all and '  [on]' or ''), 'oAll', cfg.self.show_all) then
            cfg.self.show_all = not cfg.self.show_all
            self_show_all_changed()
        end
        if btn('Show all WS (Party)' .. (cfg.party.show_all and '  [on]' or ''), 'oPAll', cfg.party.show_all) then
            cfg.party.show_all = not cfg.party.show_all
            party_changed()
        end
        if btn('BURST lines in Blue chains' .. (cfg.self.burst and '  [on]' or ''), 'oBurst', cfg.self.burst) then
            cfg.self.burst = not cfg.self.burst
            save_cfg()
        end
        imgui.TextColored(COL_DIM, 'Self also uses:')
        imgui.SameLine()
        if btn('BLU spells' .. (cfg.self.blu and '  [on]' or ''), 'oSBlu', cfg.self.blu) then
            cfg.self.blu = not cfg.self.blu
            self_changed()
        end
        imgui.SameLine()
        if btn('Pet moves' .. (cfg.self.pet and '  [on]' or ''), 'oSPet', cfg.self.pet) then
            cfg.self.pet = not cfg.self.pet
            self_changed()
        end
        imgui.SameLine()
        if btn('Automaton' .. (cfg.self.auto and '  [on]' or ''), 'oSAuto', cfg.self.auto) then
            cfg.self.auto = not cfg.self.auto
            self_changed()
        end
        imgui.TextColored(COL_DIM, 'Find also uses:')
        imgui.SameLine()
        if btn('BLU spells' .. (cfg.find.blu and '  [on]' or ''), 'oFBlu', cfg.find.blu) then
            cfg.find.blu = not cfg.find.blu
            find_changed()
        end
        imgui.SameLine()
        if btn('Pet moves' .. (cfg.find.pet and '  [on]' or ''), 'oFPet', cfg.find.pet) then
            cfg.find.pet = not cfg.find.pet
            find_changed()
        end
        imgui.SameLine()
        if btn('Automaton' .. (cfg.find.auto and '  [on]' or ''), 'oFAuto', cfg.find.auto) then
            cfg.find.auto = not cfg.find.auto
            find_changed()
        end

        -- menu reading ----------------------------------------------------------
        imgui.Spacing()
        theme.caption('MENU READING')
        if btn('Read the highlighted skill straight from the game' .. (cfg.direct and '  [on]' or '  [off]'), 'sDirect', cfg.direct) then
            cfg.direct = not cfg.direct
            save_cfg()
        end
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Recommended. Off = the older cursor-offset method (needs the manual setup below).\n(/sc direct on|off)')
        end
        status_line('Ability list:', sel.ok, sel.ok and 'found' or 'NOT found (use manual setup)')
        status_line('Spell list:  ', sel.spell_ok, sel.spell_ok and 'found' or 'NOT found')
        imgui.TextColored(COL_DIM, ('Menu: "%s"'):format(last_name or ''))
        local aid, sid = sel_read(), sel_read_spell()
        imgui.TextColored(COL_DIM, ('Highlighted ability: %s    spell: %s'):format(
            aid and ('%d %s'):format(aid, ability_name(aid)) or '-',
            sid and ('%d %s'):format(sid, (spell_info(sid))) or '-'))

        if imgui.CollapsingHeader('Manual setup (only if direct reading fails)##cfman') then
            cmd_button('Setup weapon skills', '/sc setup', 'Learn the cursor for the weapon skill list: open Abilities, then Weapon Skills, move the cursor.')
            imgui.SameLine()
            cmd_button('Setup Ready', '/sc setup ready', 'Same for Pet Commands > Ready (pet out).')
            cmd_button('Exclude (Abilities menu)', '/sc exclude', 'Stand in the Abilities menu and click: teaches the addon what it looks like.')
            imgui.SameLine()
            cmd_button('Include (Weapon Skills)', '/sc include', 'Stand in the Weapon Skills list and click.')
            cmd_button('Scan', '/sc scan', 'Search the menu memory for the highlighted skill name.')
            imgui.SameLine()
            cmd_button('Scan deep', '/sc scan deep', 'Also follows pointers.')
            cmd_button('Clear fingerprint', '/sc fp clear', 'Forget exclude / include data.')
            imgui.SameLine()
            cmd_button('Clear text spot', '/sc scan clear', 'Forget the saved scan result.')
            cmd_button('Learn menu name', '/sc learn', 'Records menu names for 10 seconds while you open Abilities > Weapon Skills.')
        end

        -- pet -------------------------------------------------------------------
        imgui.Spacing()
        theme.caption('PET')
        status_line('Pet:', ready.known, ('%s%s'):format(ready.label, ready.known and '' or '   (not in petdata.lua)'))
        imgui.TextColored(COL_DIM, ('Source: %s    Ammo slot: %s'):format(
            ({ manual = 'set by hand', summoned = 'pet that is out', jug = 'jug in your ammo slot' })[ready.src or ''] or 'none',
            ammo_item_name() or '(empty)'))
        if imgui.SetNextItemWidth then imgui.SetNextItemWidth(220) end
        imgui.InputText('##cfpet', pet_buf, 64)
        imgui.SameLine()
        if theme.toggle('Set pet', 'petSet', false) and pet_buf[1] ~= '' then run_cmd('/sc pet ' .. pet_buf[1]) end
        imgui.SameLine()
        if theme.toggle('Auto', 'petAuto', cfg.pet == '') then run_cmd('/sc pet auto') end
        if imgui.IsItemHovered() then imgui.SetTooltip('Detect the pet by itself.\n(/sc pet auto)') end
        imgui.TextColored(COL_DIM, 'Ready menu order:')
        for _, o in ipairs({ 'listed', 'alpha', 'id' }) do
            imgui.SameLine()
            if btn(o, 'ord' .. o, cfg.ready.order == o) then run_cmd('/sc ready order ' .. o) end
        end
        cmd_button('List Ready moves', '/sc ready', 'Print the moves I know for this pet.')

        -- blue magic --------------------------------------------------------------
        imgui.Spacing()
        theme.caption('BLUE MAGIC')
        local now = os.clock()
        if now - set_cache.t > 1.5 then
            set_cache.t = now
            set_cache.names = {}
            for id in pairs(blu_set.ids) do set_cache.names[#set_cache.names + 1] = (spell_info(id)) end
            table.sort(set_cache.names)
        end
        if blu_set.seen then
            imgui.TextColored(COL_DIM, ('Equipped set (%d spells):'):format(#set_cache.names))
            imgui.PushTextWrapPos(imgui.GetWindowWidth() - 24)
            imgui.TextColored(COL_SET, table.concat(set_cache.names, ', '))
            imgui.PopTextWrapPos()
        else
            imgui.TextColored(COL_WARN, 'Equipped set not seen yet - zone, change job or change a spell.')
        end
        cmd_button('Print set to chat', '/sc bluset', 'Same list as above, in the chat log.')

        -- misc --------------------------------------------------------------------
        imgui.Spacing()
        theme.caption('OTHER')
        cmd_button('Refresh skill lists', '/sc refresh', 'Re-read your learned weapon skills and pet moves.')
        imgui.SameLine()
        cmd_button('Debug: menu names', '/sc debug', 'Toggle printing the menu name to chat each time it changes.')
        imgui.SameLine()
        cmd_button('Help', '/sc help', 'Print every command to chat.')
    end
    theme.finish()
    if not open_flag.settings[1] then pinned.settings = false end
end

----------------------------------------------------------------------
-- Main frame
----------------------------------------------------------------------
ashita.events.register('load', 'chainfinder_load', function()
    pGameMenu = ashita.memory.find('FFXiMain.dll', 0, '8B480C85C974??8B510885D274??3B05', 16, 0)
    sel_init()
    load_cfg()
    theme.ui_scale = cfg.scale / 100
    rebuild_find_pool()
    rebuild_party_pool()
    refresh_ready(true)
    ctx_blu.pool = build_blu_pool()
    build_burst_rows()
end)

-- Equipped blue magic set (BLU main job): packet 0x044, byte 0x04 = job (16 = BLU), 20 spell bytes from 0x08
-- (spell id - 512). Sent when you zone, change job or change your set. Unverified layout: /sc bluset shows the result.
ashita.events.register('packet_in', 'chainfinder_packet', function(e)
    if e.id ~= 0x44 then return end
    pcall(function()
        if e.data:byte(5) ~= 16 then return end
        local ids, n = {}, 0
        for i = 0, 19 do
            local b = e.data:byte(9 + i)
            if b and b > 0 then ids[b + 512] = true; n = n + 1 end
        end
        if n > 0 then
            blu_set.ids, blu_set.seen = ids, true
            burst_state.t = -10
        end
    end)
end)

ashita.events.register('d3d_present', 'chainfinder_present', function()
    local now = os.clock()

    local okm, name, v, h = pcall(get_menu)
    if not okm then name, v, h = '', 0, 0 end

    -- name matches (each profile has its own menu name); the size gate comes after the lists refresh
    local ws_hit = menu_matches(name, cfg.menu)
    local rd_hit = menu_matches(name, cfg.ready.menu)

    if debug_on and name ~= last_name then say(('menu: "%s"'):format(name)) end
    last_name = name

    if cap then
        if v ~= 0 and h ~= 0 then capture_sample(cap, v, h) end
        if now >= cap.t_end then
            local c = cap
            cap = nil
            finish_capture(c)
        end
    end

    if learn then
        if name ~= '' and name ~= learn.last then
            learn.seen[#learn.seen + 1] = name
            learn.last = name
        end
        if now >= learn.t_end then finish_learn() end
    end

    if calib then
        calib.frame = calib.frame + 1
        if menu_matches(name, calib.P.menu) and v ~= 0 and h ~= 0 and calib.frame % 2 == 0 then
            sample_into(calib.stats, v, h)
        end
        if now >= calib.t_end then
            local c = calib
            calib = nil
            finish_calib(c.stats, c.P, c.count, c.kind)
        end
    end

    if setup then
        setup.frame = setup.frame + 1
        if name ~= '' then
            if name ~= setup.last then
                setup.seen[#setup.seen + 1] = name
                setup.last = name
            end
            if v ~= 0 and h ~= 0 and setup.frame % 2 == 0 then
                setup.stats[name] = setup.stats[name] or {}
                sample_into(setup.stats[name], v, h)
            end
        end
        if now >= setup.t_end then
            local sd = setup
            setup = nil
            if #sd.seen == 0 then
                say(('setup: no menus were seen. Run /sc setup%s again, then open the menu.'):format(sd.kind == 'ready' and ' ready' or ''))
            else
                -- the right menu is the one whose cursor value tracked your moves
                local pick, best = nil, 0
                for nm, st in pairs(sd.stats) do
                    local c = cursor_candidates(st, sd.count + 1)
                    if #c > 0 and c[1].pm1 > best then pick, best = nm, c[1].pm1 end
                end
                sd.P.menu = pick or sd.last
                save_cfg()
                say('setup: menus seen: ' .. list_join(sd.seen, '  >  '))
                say(('setup: %s menu = "%s"%s'):format(sd.kind == 'ready' and 'Ready' or 'weapon skill', sd.P.menu,
                    pick and '' or ' (no cursor found, guessed)'))
                finish_calib(sd.stats[sd.P.menu] or {}, sd.P, sd.count, sd.kind)
            end
        end
    end

    -- direct mode: any ability-type list counts for refreshing; the highlighted id decides what it is
    local direct = cfg.direct and sel.ok
    local dmode, dhov, didx
    if direct then
        local is_ab = name:lower():find('ability', 1, true) ~= nil
        ws_hit, rd_hit = is_ab, is_ab
        local sid = is_ab and sel_read() or nil
        if sid then
            local wsx = (sid >= 1 and sid <= 255) and ws_by_id[sid] or nil
            if not wsx and sid >= 1 and sid <= 255 then
                -- weapon skill with no chain property: not in the chain data, but still a weapon skill
                local an = ability_name(sid)
                if an ~= '' then wsx = { id = sid, name = an, props = {} } end
            end
            if wsx then
                dmode = 'ws'
                for i, w in ipairs(mine.main) do
                    if w.id == sid then dhov, didx = w, i break end
                end
                dhov = dhov or { id = wsx.id, name = wsx.name, props = wsx.props or {} }
            else
                local an = ability_name(sid)
                if an ~= '' then
                    local k = petdata.norm(an)
                    for i, m in ipairs(ready.moves) do
                        if petdata.norm(m.name) == k then dmode, dhov, didx = 'ready', m, i break end
                    end
                end
            end
        end
    end

    -- spell menu: only for BLU (main or sub), only while a Blue Magic spell is highlighted
    if direct and not dmode and name:lower():find('magic', 1, true) and sel.spell_ok and player_is_blu() then
        local sp = sel_read_spell()
        if sp then
            local nm, sk = spell_info(sp)
            if sk == 43 then
                dmode = 'blu'
                dhov = blu_by_id[sp] or { id = sp, name = nm, props = {}, key = 'b:' .. sp }
            end
        end
    end

    -- refresh the lists when a matching menu opens, then once a second while it stays open
    local any_hit = ws_hit or rd_hit
    if any_hit and (not was_hit or now - last_check > 1.0) then
        local first = not was_hit
        last_check = now
        if ws_hit then refresh_mine(first) end
        if rd_hit then refresh_ready(first) end
    end
    was_hit = any_hit

    local ws_open = ws_hit and profile_gate(cfg, v, h, #mine.main) and fp_gate(v, h) and text_gate(v, h)
    local rd_open = rd_hit and profile_gate(cfg.ready, v, h, #ready.moves)
    if direct then ws_open, rd_open = false, false end
    local mode = nil                       -- 'ws', 'ready' or nil (neither list is open)
    if ws_open and rd_open then
        mode = 'ws'
        if not warned_same then
            warned_same = true
            say('The weapon skill and Ready menus look identical to me (same name, no size field), so I')
            say('cannot tell them apart. Run /sc debug and open each menu, and send me the names.')
        end
    elseif ws_open then
        mode = 'ws'
    elseif rd_open then
        mode = 'ready'
    end
    if direct then mode = dmode end
    if not mode and pinned.pet and pinned.self and not pinned.party then mode = 'ready' end   -- /sc pets
    local menu_open = (mode ~= nil)

    local hovered, hidx
    hover.raw, hover.idx = nil, nil
    if direct then
        hovered, hidx = dhov, didx
    elseif mode == 'ws' then
        hovered, hidx, hover.raw = read_hover(cfg, mine.main, v, h)
    elseif mode == 'ready' then
        hovered, hidx, hover.raw = read_hover(cfg.ready, ready.moves, v, h)
    end
    hover.idx = hidx
    hover.id = hovered and hovered.id or nil
    local key
    if mode == 'ready' then key = hovered and hovered.key or 'rall'
    elseif mode == 'blu' then key = hovered and hovered.key or 'ball'
    else key = hovered and hovered.id or 'all' end
    local wmode = mode or 'ws'

    if scanreq and now >= scanreq.t then
        local sr = scanreq
        scanreq = nil
        local names = known_name_set()
        local hits = {}
        for _, o in ipairs({ { 'menu', v }, { 'header', h } }) do
            if o[2] ~= 0 then
                for off = 0, 0x3FF do
                    local txt = read_text(o[2], off, false)
                    if #txt >= 4 and names[petdata.norm(txt)] then hits[#hits + 1] = { o[1], off, false, txt } end
                    if sr.deep and off % 4 == 0 then
                        local ptxt = read_text(o[2], off, true)
                        if #ptxt >= 4 and names[petdata.norm(ptxt)] then hits[#hits + 1] = { o[1], off, true, ptxt } end
                    end
                end
            end
        end
        if #hits == 0 then
            say(('scan: no weapon skill name found in the menu objects%s.'):format(sr.deep and '' or ' (inline text only)'))
            if not sr.deep then say('Try /sc scan deep (also follows pointers).') end
        else
            local pick
            for _, hit in ipairs(hits) do
                say(('scan: "%s" at %s+0x%X%s'):format(hit[4], hit[1], hit[2], hit[3] and ' (via pointer)' or ''))
                if hovered and petdata.norm(hit[4]) == petdata.norm(hovered.name) then pick = pick or hit end
            end
            if pick then
                cfg.nm_obj, cfg.nm_off, cfg.nm_ptr = pick[1], pick[2], pick[3]
                save_cfg()
                say(('scan: saved %s+0x%X as the highlighted-text spot. The Self window now needs a weapon skill name there.'):format(pick[1], pick[2]))
            else
                say('scan: none of these matched the skill your cursor is on (or /sc setup is not done), so nothing was saved.')
                say('Hover a weapon skill in the Weapon Skills list and run /sc scan again.')
            end
        end
    end

    -- Self and Party never show together: Party (opened with /sc party) replaces Self.
    -- Self opens by itself only inside the weapon skill / Ready lists, and only until you close it.
    local show_party = pinned.party
    local show_self  = (not show_party) and ((menu_open and self_auto) or pinned.self)
    local show_find  = pinned.find                      -- only ever opened by /sc find
    local show_blu   = pinned.blu
    local show_settings = pinned.settings
    if not (show_self or show_party or show_find or show_blu or show_settings) then return end

    if (show_self or show_party) and not any_hit and now - last_check > 1.0 then
        last_check = now
        refresh_mine(false)
        refresh_ready(false)
    end

    if now - (last_pet_check or 0) > 1.0 then
        last_pet_check = now
        refresh_ready(false)                 -- follows your pet / the jug in your ammo slot
    end

    local nc, nv = theme.push()
    if show_self then draw_self_window(hovered, menu_open, key, hidx, wmode) end
    if show_party then draw_party_window(hovered, menu_open, key, hidx, wmode) end
    if show_find then draw_find_window() end
    if show_blu then draw_blu_window() end
    if show_settings then draw_settings_window() end
    theme.pop(nc, nv)
end)

----------------------------------------------------------------------
-- Commands  (/sc)
----------------------------------------------------------------------
local function parse_types(arg)
    local ids, bad, seen = {}, {}, {}
    for token in arg:gmatch('[^,]+') do
        local key = (token:lower():gsub('[%s%-_]', ''))
        local id = skill_alias[key]
        if id then
            if not seen[id] then
                seen[id] = true
                ids[#ids + 1] = id
            end
        else
            bad[#bad + 1] = token
        end
    end
    table.sort(ids)
    return ids, bad
end

-- "any" -> {}, "1,3" -> {1,3}; nil if invalid
local function parse_levels(a)
    a = a:lower()
    if a == 'any' or a == 'all' or a == '*' or a == '0' then return {} end
    local out = {}
    for token in a:gmatch('[^,]+') do
        local n = tonumber(token)
        if not n or n < 1 or n > 4 or n ~= math.floor(n) then return nil end
        if not lv_has(out, n) then out[#out + 1] = n end
    end
    table.sort(out)
    if #out == 0 then return nil end
    return out
end

local function help()
    say('/sc self         toggle the Self window. It opens by itself in the Weapon Skill list and the')
    say('                 Ready list (Pet Commands > Ready); closing it with X keeps it closed until /sc self')
    say('/sc party        toggle the Party window: Self + extra weapons (replaces Self while open)')
    say('/sc find         toggle the Find window: chains between chosen weapon types (never opens by itself)')
    say('/sc blu          toggle the Blue Mage window (Chain Affinity chains + Burst Affinity bursts)')
    say('Self and Party never show together; Find can show alongside either. Use the buttons in the windows.')
    say('/sc setup        ONE-TIME for weapon skills: open Abilities, then Weapon Skills, move the cursor first > last > first')
    say('Self/Find windows have "Also use: BLU spells / Pet moves" toggles; Self also shows in the spell menu while a blue magic spell is highlighted (BLU only).')
    say('/sc settings     open the settings window (setup, pet, blue magic set, status, every command as a button)')
    say('/sc direct on|off  read the highlighted skill straight from the game (default on; /sc sel shows what it reads)')
    say('/sc scan [deep]  in the Weapon Skills list: find where the game keeps the highlighted skill name (best fix for the Abilities menu)')
    say('/sc exclude      stand in the Abilities menu (the one that wrongly shows the Self window) and run this')
    say('/sc include      then open the Weapon Skills list, cursor on the first skill, and run this')
    say('/sc setup ready  ONE-TIME for pets: with your pet out, open Pet Commands > Ready and do the same')
    say('/sc ready        show the pet and Ready moves I know   /sc ready order listed|alpha|id   /sc pet <name|auto>')
    say('/sc pets         Pet Chains window without the Ready menu (Puppetmaster automaton)   /sc frame harlequin|valoredge|sharpshot|stormwaker')
    say('Find text commands: /sc types axe,sword (max 5) | types clear | level 1,3 or any | steps 2-5')
    say('                     /sc mix on|off (use every selected type) | /sc set <types> <levels> [steps]')
    say('Other: /sc learn  /sc calibrate  /sc debug  /sc menu [text]  /sc refresh')
end

local function cmd_sc(args)
    local cmd = args[2] and args[2]:lower() or 'help'

    if cmd == 'find' then
        pinned.find = not pinned.find

    elseif cmd == 'party' then
        pinned.party = not pinned.party
        if pinned.party then pinned.self = false end
        refresh_mine(true)
        refresh_ready(true)

    elseif cmd == 'self' then
        pinned.pet = false
        if pinned.party then
            pinned.party = false
            pinned.self = true
            self_auto = true
        elseif pinned.self then
            pinned.self = false
        else
            pinned.self = true
            self_auto = true                     -- also lets it open by itself in the menus again
        end
        refresh_mine(true)
        refresh_ready(true)

    elseif cmd == 'settings' or cmd == 'config' or cmd == 'options' then
        pinned.settings = not pinned.settings

    elseif cmd == 'blu' then
        pinned.blu = not pinned.blu

    elseif cmd == 'pets' or cmd == 'automaton' then
        -- Pet Chains window without having to hover the Ready menu (e.g. for a Puppetmaster's automaton)
        if pinned.pet and pinned.self then
            pinned.pet, pinned.self = false, false
        else
            pinned.pet, pinned.self, pinned.party = true, true, false
            self_auto = true
        end
        refresh_ready(true)

    elseif cmd == 'types' then
        if not args[3] then say('Usage: /sc types axe,sword   (or /sc types clear)') return end
        if args[3]:lower() == 'clear' then
            cfg.find.types = {}
            find_changed()
            return
        end
        local ids, bad = parse_types(args[3])
        if #bad > 0 then say('Unknown weapon type: ' .. table.concat(bad, ', ')) return end
        if #ids == 0 then say('No valid weapon types given.') return end
        if #ids > MAX_TYPES then say(('At most %d weapon types.'):format(MAX_TYPES)) return end
        cfg.find.types = ids
        find_changed()

    elseif cmd == 'level' then
        local lv = args[3] and parse_levels(args[3])
        if lv == nil then say('Usage: /sc level <1-4 list like 1,3 | any>') return end
        cfg.find.levels = lv
        find_changed()

    elseif cmd == 'steps' then
        local n = tonumber(args[3])
        if not n or n < 2 or n > MAX_STEPS then say(('Usage: /sc steps <2-%d>'):format(MAX_STEPS)) return end
        cfg.find.steps = n
        find_changed()

    elseif cmd == 'mix' then
        local a = args[3] and args[3]:lower()
        if a ~= 'on' and a ~= 'off' then say('Usage: /sc mix on|off') return end
        cfg.find.all = (a == 'on')
        find_changed()

    elseif cmd == 'set' then
        if not args[3] or not args[4] then
            say('Usage: /sc set <types> <levels> [steps]')
            return
        end
        local ids, bad = parse_types(args[3])
        if #bad > 0 then say('Unknown weapon type: ' .. table.concat(bad, ', ')) return end
        if #ids == 0 then say('No valid weapon types given.') return end
        if #ids > MAX_TYPES then say(('At most %d weapon types.'):format(MAX_TYPES)) return end
        local lv = parse_levels(args[4])
        if lv == nil then say('Levels must be 1-4 (e.g. 3 or 1,3) or "any".') return end
        local steps = cfg.find.steps
        if args[5] then
            steps = tonumber(args[5])
            if not steps or steps < 2 or steps > MAX_STEPS then
                say(('Steps must be between 2 and %d.'):format(MAX_STEPS))
                return
            end
        end
        cfg.find.types, cfg.find.levels, cfg.find.steps = ids, lv, steps
        find_changed()
        say('Find settings saved. Use /sc find to open the window.')

    elseif cmd == 'setup' then
        local kind = (args[3] and args[3]:lower() == 'ready') and 'ready' or 'ws'
        refresh_mine(true)
        refresh_ready(true)
        local count = (kind == 'ready') and #ready.moves or #mine.main
        if count == 0 then
            if kind == 'ready' then
                say("setup ready: I don't know your pet's Ready moves. Call your pet out, or name it with")
                say('/sc pet <name>, or add it to petdata.lua. (/sc ready shows what I currently see.)')
            else
                say("setup: I couldn't read your weapon skill list. Equip a weapon and try again.")
            end
            return
        end
        setup = { kind = kind, P = (kind == 'ready') and cfg.ready or cfg, count = count,
                  t_end = os.clock() + 25, seen = {}, last = '', stats = {}, frame = 0 }
        if kind == 'ready' then
            say('setup ready: with your pet out, open Pet Commands > Ready. Start on the FIRST move, move down')
            say('            to the last, then back up, a couple of times. Takes 25 seconds from now.')
        else
            say('setup: open Abilities (wait a second or two), then Weapon Skills. In the weapon skill list start')
            say('       on the FIRST skill, move down to the last, then back up, a couple of times.')
            say('       Do not move the cursor in any other list. Takes 25 seconds from now.')
        end

    elseif cmd == 'exclude' or cmd == 'include' then
        cap = { kind = (cmd == 'exclude') and 'bad' or 'good', t_end = os.clock() + 3, n = 0, vals = {}, varied = {} }
        say(cmd == 'exclude'
            and 'exclude: keep the ABILITIES menu (the one that wrongly shows the window) open and still for 3 seconds...'
            or  'include: keep the WEAPON SKILLS list open, cursor on the first skill and still, for 3 seconds...')

    elseif cmd == 'bluset' then
        if not blu_set.seen then
            say('No blue magic set seen yet. Zone, change job or change your set so the game sends it again.')
        else
            local names = {}
            for id in pairs(blu_set.ids) do names[#names + 1] = (spell_info(id)) end
            table.sort(names)
            say(('Equipped blue magic (%d): %s'):format(#names, table.concat(names, ', ')))
        end

    elseif cmd == 'direct' then
        local a = args[3] and args[3]:lower()
        if a == 'off' then cfg.direct = false elseif a == 'on' then cfg.direct = true end
        save_cfg()
        say(('direct selection: %s (game hooks found: %s). /sc direct on|off'):format(cfg.direct and 'ON' or 'off', sel.ok and 'yes' or 'NO'))

    elseif cmd == 'sel' then
        local id = sel_read()
        say(('menu: "%s"   highlighted ability id: %s   name: %s'):format(last_name or '', tostring(id), id and ability_name(id) or '-'))

    elseif cmd == 'scan' then
        if args[3] and args[3]:lower() == 'clear' then
            cfg.nm_obj, cfg.nm_off, cfg.nm_ptr = '', -1, false
            save_cfg()
            say('Text spot cleared.')
        else
            scanreq = { t = os.clock() + 3, deep = (args[3] and args[3]:lower() == 'deep') or false }
            say('scan: open the WEAPON SKILLS list, put the cursor on a skill and keep still. Scanning in 3 seconds...')
            if scanreq.deep then say('(deep mode follows pointers; if the game ever crashes while scanning, use plain /sc scan instead)') end
        end

    elseif cmd == 'fp' then
        if args[3] and args[3]:lower() == 'clear' then
            cfg.fp, cfg.cap_bad, cfg.cap_good = {}, {}, {}
            save_cfg()
            say('Fingerprint cleared.')
        else
            say(('Fingerprint: %d markers (Abilities captured: %s, Weapon Skills captured: %s). /sc fp clear resets it.'):format(
                #cfg.fp, next(cfg.cap_bad) and 'yes' or 'no', next(cfg.cap_good) and 'yes' or 'no'))
        end

    elseif cmd == 'ready' then
        local a = args[3] and args[3]:lower()
        if a == 'order' then
            local o = args[4] and args[4]:lower()
            if o ~= 'listed' and o ~= 'alpha' and o ~= 'id' then say('Usage: /sc ready order listed|alpha|id') return end
            cfg.ready.order = o
            save_cfg()
            refresh_ready(true)
        else
            refresh_ready(true)
            say(('Pet: %s%s   order: %s'):format(ready.label, ready.known and '' or '  (NOT in petdata.lua)', cfg.ready.order))
            for i, m in ipairs(ready.moves) do
                say(('  %d. %s  [%s]'):format(i, m.name, #m.props > 0 and table.concat(m.props, '/') or 'no property'))
            end
        end

    elseif cmd == 'frame' then
        local k = args[3] and args[3]:lower() or ''
        if petdata.frame_by_key[k] then
            cfg.frame = k
            save_cfg()
            refresh_ready(true)
            say(('Automaton frame set to %s.'):format(petdata.frame_by_key[k].name))
        else
            local names = {}
            for _, f in ipairs(petdata.frames) do names[#names + 1] = f.key end
            say(('Automaton frame = %s.  Usage: /sc frame %s'):format(cfg.frame, table.concat(names, '|')))
        end

    elseif cmd == 'pet' then
        if not args[3] then
            say(('Pet = %s'):format(cfg.pet ~= '' and cfg.pet or '(automatic)'))
            return
        end
        local nm = table.concat(args, ' ', 3)
        cfg.pet = (nm:lower() == 'auto') and '' or nm
        save_cfg()
        refresh_ready(true)
        say(('Pet set to %s.'):format(cfg.pet ~= '' and cfg.pet or '(automatic)'))

    elseif cmd == 'learn' then
        learn = { t_end = os.clock() + 10, seen = {}, last = '' }
        say('learn: now open Abilities > Weapon Skills and leave that menu open for ~10 seconds.')

    elseif cmd == 'calibrate' then
        local kind = (args[3] and args[3]:lower() == 'ready') and 'ready' or 'ws'
        local P = (kind == 'ready') and cfg.ready or cfg
        if P.menu == '' then say(('Run /sc setup%s first.'):format(kind == 'ready' and ' ready' or '')) return end
        refresh_mine(true)
        refresh_ready(true)
        local count = (kind == 'ready') and #ready.moves or #mine.main
        calib = { P = P, kind = kind, count = count, t_end = os.clock() + 15, stats = {}, frame = 0 }
        say('calibrate: open that menu and move the cursor first > last > first for 15 seconds.')

    elseif cmd == 'debug' then
        debug_on = not debug_on
        say('Menu-name debug ' .. (debug_on and 'on' or 'off') .. '.')

    elseif cmd == 'menu' then
        if args[3] then
            cfg.menu = table.concat(args, ' ', 3)
            save_cfg()
            say(('Weapon skill menu set to "%s".'):format(cfg.menu))
        else
            say(('Weapon skill menu = "%s"; cursor = %s+0x%X base %d; size field = %s; hover raw=%s'):format(
                cfg.menu, cfg.cur_obj == '' and '?' or cfg.cur_obj, math.max(cfg.cur_off, 0),
                cfg.cur_base, cfg.cnt_off >= 0 and ('+0x%X'):format(cfg.cnt_off) or 'none', tostring(hover.raw)))
            local r = cfg.ready
            say(('Ready menu = "%s"; cursor = %s+0x%X base %d; size field = %s'):format(
                r.menu, r.cur_obj == '' and '?' or r.cur_obj, math.max(r.cur_off, 0), r.cur_base,
                r.cnt_off >= 0 and ('+0x%X'):format(r.cnt_off) or 'none'))
        end

    elseif cmd == 'refresh' then
        refresh_mine(true)
        refresh_ready(true)

    else
        help()
    end
end

ashita.events.register('command', 'chainfinder_command', function(e)
    local args = e.command:args()
    if #args == 0 then return end
    if args[1]:lower() == '/sc' then
        e.blocked = true
        cmd_sc(args)
    end
end)
