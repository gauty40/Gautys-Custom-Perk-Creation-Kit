local ENABLE_AUGMENT_HOOKS = true 
local ENABLE_WUNDERFIZZ_KBM_HOOKS = false
local ENABLE_GRID_PROBES = false 
local VERBOSE_AUGMENT_LOGS = false
local H = rawget(_G, "xhash")
local function log(m)
    m = tostring(m)
    if not VERBOSE_AUGMENT_LOGS and not m:lower():find("error", 1, true) and not m:lower():find("failed", 1, true) then
        if m:match("^COOP AUGMENTS .- attempt=") or m:match("^bo7_cp_.*_transport=") or
            (m:match("^bo7_cp_.*_runtime=") and not m:match("^bo7_cp_blaze_phase_runtime=")) then return end
    end
    local f = rawget(_G, "DebugPrint")
    if type(f) == "function" then pcall(f, "[CustomPerks] " .. tostring(m)) end
end
if type(H) ~= "function" then log("xhash unavailable"); return end
local old = rawget(_G, "BO7CustomPerks")
if old and old.version == 128 then return end
if old then
    old.enabled = false
    for _, slot in ipairs(old.overflowPerkIcons or {}) do
        local widget = slot.root or slot
        pcall(function() widget:SetAlpha(0, 0) end)
    end
    if old.stockHudNativePerkContainer then
        local alpha = tonumber(old.stockHudNativePerkAlpha) or 1
        pcall(function() old.stockHudNativePerkContainer:SetAlpha(alpha, 0) end)
    end
end
local previous = old
local S = { version = 128, enabled = true, ticks = 0, hooks = {}, bundles = {}, owned = {}, vitalityLootOptions = {}, augmentLootOptions = {}, pickLoaded = {}, pickLoadTries = {} }
rawset(_G, "BO7CustomPerks", S)
local vitalitySelection = rawget(_G, "BO7VitalityAugmentSelection")
if type(vitalitySelection) ~= "table" then
    vitalitySelection = { major = 0, minor = 0, pending = { major = false, minor = false } }
    rawset(_G, "BO7VitalityAugmentSelection", vitalitySelection)
elseif type(vitalitySelection.pending) ~= "table" then
    vitalitySelection.pending = { major = false, minor = false }
end
if type(vitalitySelection.failureLogged) ~= "table" then
    vitalitySelection.failureLogged = {}
end

local CUSTOM = {
    {
        ref = "specialty_bandolier", code = 78, name = "Bandolier Bandit",
        creator = "Gauty",
        desc = "Your weapons hold 50% more reserve ammo. Equip augments for additional effects.",
        icon = "ui_icon_perks_zm_bandolier", -- EDIT BANDOLIER BANDIT ICON MATERIAL HERE; nil keeps the Juggernog placeholder
    },
    {
        ref = "specialty_tortoise", code = 73, name = "Victorious Tortoise",
        creator = "Gauty",
        desc = "Take 15% less damage while wearing armor. Equip augments for additional effects.",
        icon = "ui_icon_perks_zm_tortoise", -- EDIT VICTORIOUS TORTOISE ICON MATERIAL HERE; nil keeps the Juggernog placeholder
    },
    {
        ref = "specialty_gautys_gold", code = 82, name = "Gauty's Gold",
        creator = "Gauty",
        desc = "Earns 1.25x points while this perk is active. Equip augments for additional effects.",
        icon = "ui_icon_perks_zm_Gautys_Gold", -- EDIT GAUTY'S GOLD ICON MATERIAL HERE; nil keeps the Juggernog placeholder
    },
    {
        ref = "specialty_jug2", code = 71, name = "Roo Brew",
        desc = "Jump five times as high. Equip Moon Hop to reduce gravity for 5 seconds after jumping. Equip augments for additional effects.",
        creator = "Gauty",
        icon = "ui_icons_perks_zm_roo_brew", -- EDIT ROO BREW ICON MATERIAL HERE; nil keeps the Juggernog placeholder
    },
    {
        ref = "specialty_electric_cherry", code = 72, name = "Electric Cherry",
        creator = "Gauty",
        desc = "Reloading shocks nearby zombies for 50% of their max health and stuns survivors for 2 seconds (15 second cooldown). Equip augments for additional effects.",
        icon = "ui_icons_perks_zm_electric_cherry", -- EDIT ELECTRIC CHERRY ICON MATERIAL HERE; nil keeps the Juggernog placeholder
    },
    }
S.customPerks = CUSTOM
local PERK_PACK_ICONS = {
    ["specialty_juggernog"] = "ui_icon_perks_zm_juggernaut",
    ["specialty_quick_revive"] = "ui_icon_perks_zm_quickrevive",
    ["specialty_speedcola"] = "ui_icon_perks_zm_speedloader",
    ["specialty_staminup"] = "ui_icon_perks_zm_staminup",
    ["specialty_deadshot"] = "ui_icon_perks_zm_deadshot",
    ["specialty_elemental_pop"] = "ui_icon_perks_zm_elemental_pop",
    ["specialty_phd_flopper"] = "ui_icon_perks_zm_phdslider",
    ["specialty_death_perception"] = "ui_icon_perks_zm_deathperception",
    ["specialty_vulture_aid"] = "ui_icon_perks_vulture_aid",
    ["specialty_m_mod"] = "ui_icon_perks_melee_macchiato",
    ["specialty_d_mod"] = "ui_icon_perks_double_tap",
    ["specialty_w_mod"] = "ui_icon_perks_wisp_tea",
    ["specialty_y_mod"] = "ui_icon_perks_widows_wine",
    ["specialty_z_mod"] = "ui_icon_perks_zm_mulekick",
}
local perkPackRefs = {}
for ref in pairs(PERK_PACK_ICONS) do perkPackRefs[#perkPackRefs + 1] = ref end
for _, ref in ipairs(perkPackRefs) do
    local image = PERK_PACK_ICONS[ref]
    local hashed = H(ref)
    if hashed ~= nil then PERK_PACK_ICONS[hashed] = image; PERK_PACK_ICONS[tostring(hashed)] = image end
end
S.perkPackIcons = PERK_PACK_ICONS
local byRef = {}
for _, c in ipairs(CUSTOM) do
    byRef[c.ref] = c
    local refHash = H(c.ref)
    if refHash ~= nil then
        byRef[refHash] = c
        byRef[tostring(refHash)] = c
    end
end
local isCustomPerkAvailable

local function hk(name)
    local ok, v = pcall(H, name)
    if ok then return v end
    return nil
end
local function g(t, k)
    if type(t) ~= "table" then return nil end
    local hv = hk(k)
    local v
    if hv ~= nil then v = t[hv] end
    if v == nil then v = t[k] end
    return v
end
local function s(t, k, v)
    local hv = hk(k)
    if hv ~= nil then t[hv] = v end
    t[k] = v
end

local function allFnKeys(tbl, name)
    local keys, seen = {}, {}
    for _, key in ipairs({ name, hk(name), hk(name:lower()) }) do
        if key ~= nil and not seen[key] then
            seen[key] = true
            local ok, f = pcall(function() return tbl[key] end)
            if ok and type(f) == "function" then keys[#keys + 1] = { key = key, fn = f } end
        end
    end
    return keys
end
local function findFn(tbl, name)
    local candidates = { name, hk(name), hk(name:lower()) }
    for _, key in ipairs(candidates) do
        local ok, f = pcall(function() return tbl[key] end)
        if ok and type(f) == "function" then return key, f end
    end
    return nil
end

local function restorePrototypeAugmentHooks()
    if type(previous) ~= "table" or type(previous.hooks) ~= "table" then return end
    local hookTargets = {
        { "augmentPerkList", rawget(_G, "PERK"), "getallperks" },
        { "vitalityPerkList", rawget(_G, "ZMPERK"), "getperklist" },
        { "augmentFullCache", rawget(_G, "ZMAUGMENT"), "createfullaugmentcache" },
        { "augmentUnlocked", rawget(_G, "LOOT"), "isunlockedwithid" },
        { "augmentFullList", rawget(_G, "ZMAUGMENT"), "initfullaugmentlist" },
        { "augmentTypeList", rawget(_G, "ZMAUGMENT"), "inittypeaugmentlist" },
        { "augmentRefreshList", rawget(_G, "ZMAUGMENT"), "refreshaugmentlistdata" },
        { "augmentEquippedRead", rawget(_G, "ZMAUGMENT"), "getequippedaugmentbyref" },
        { "augmentEquippedWrite", rawget(_G, "ZMAUGMENT"), "modifyselectedaugment" },
        { "vitalityFullAugmentRows", rawget(_G, "ZMAUGMENT"), "initfullaugmentlist" },
        { "vitalityTypedAugmentRows", rawget(_G, "ZMAUGMENT"), "inittypeaugmentlist" },
        { "vitalityAugmentUnlock", rawget(_G, "LOOT"), "isunlockedwithid" },
        { "vitalityAugmentRead", rawget(_G, "ZMAUGMENT"), "getequippedaugmentbyref" },
        { "vitalityAugmentWrite", rawget(_G, "ZMAUGMENT"), "modifyselectedaugment" },
    }
    for _, target in ipairs(hookTargets) do
        local state = previous.hooks[target[1]]
        if type(state) == "table" and type(state.wrapper) == "function" and type(state.original) == "function" then
            for _, entry in ipairs(allFnKeys(target[2], target[3])) do
                if entry.fn == state.wrapper then target[2][entry.key] = state.original end
            end
        end
    end

    local perks = rawget(_G, "ZMPERK")
    local perkList = perks and g(perks, "zmperklist")
    if type(perkList) == "table" then
        for index = #perkList, 1, -1 do
            local ref = g(perkList[index], "ref")
        end
    end
    local augment = rawget(_G, "ZMAUGMENT")
    if type(augment) == "table" then
        for _, name in ipairs({ "augmentlist_full", "augmentlist_major", "augmentlist_minor" }) do
            local list = g(augment, name)
            if type(list) == "table" then
            end
        end
    end
end

local function customPackIcon(icon)
    if type(icon) ~= "string" then return icon end
    local packs = rawget(_G, "BO7CustomPerkIconPacks")
    if type(packs) ~= "table" then return icon end
    local getter = g(rawget(_G, "Dvar"), "GetDvarString")
    local hash = rawget(_G, "xhashdvar") or g(rawget(_G, "CLUA"), "PushXHashDvar")
    local selected
    if type(getter) == "function" and type(hash) == "function" then
        local ok, value = pcall(getter, hash("kr_perk_icons"))
        if ok and value ~= nil then selected = tostring(value) end
    end
    if not selected or selected == "" then selected = packs.defaultPack or "Black Ops 7" end
    local pack = packs.packs and packs.packs[selected:lower()]
    return pack and pack[icon] or icon
end
S.resolvePerkPackIcon = customPackIcon

local function bundleFor(c, original)
    if S.bundles[c.ref] then return S.bundles[c.ref] end
    local base = original("specialty_juggernog")
    if base == nil then return nil end
    local b = {}
    local ok = pcall(function() for k, v in pairs(base) do b[k] = v end end)
    if not ok or next(b) == nil then b = setmetatable({}, { __index = base }) end
    s(b, "ref", c.ref)
    s(b, "name", c.name)
    s(b, "description", c.desc)
    s(b, "shortdesc", c.desc)
    if c.ref == "specialty_bandolier" or c.ref == "specialty_tortoise" or c.ref == "specialty_gautys_gold" or c.ref == "specialty_electric_cherry" or c.ref == "specialty_vitality" or c.ref == "specialty_jug2" then s(b, "augmentlist", nil) end
    if c.icon then
        local icon = customPackIcon(c.icon)
        local assetHash = rawget(_G, "xhashasset") or g(rawget(_G, "CLUA"), "PushXHashAsset")
        if type(assetHash) == "function" then
            local hashed, value = pcall(assetHash, icon)
            if hashed and value ~= nil then icon = value end
        end
        for _, f in ipairs({ "hudimage", "image", "legacyimage", "bwimage" }) do s(b, f, icon) end
    end
    S.bundles[c.ref] = b
    return b
end

local function installPerk()
    local PERK = rawget(_G, "PERK")
    if type(PERK) ~= "table" then return false end
    local keys = allFnKeys(PERK, "GetBundleByRef")
    if #keys == 0 then return false end
    local original = keys[1].fn
    if S.hooks.perkWrapper then
        local all = true
        for _, e in ipairs(keys) do if e.fn ~= S.hooks.perkWrapper then all = false end end
        if all then return true end
        original = S.hooks.perkOriginal or original
    else
        S.hooks.perkOriginal = original
    end
    local wrapper = function(ref, ...)
        local c = byRef[ref] or byRef[tostring(ref)]
        if c then
            local b = bundleFor(c, S.hooks.perkOriginal)
            if b then return b end
        end
        return S.hooks.perkOriginal(ref, ...)
    end
    for _, e in ipairs(keys) do PERK[e.key] = wrapper end
    S.hooks.perkWrapper = wrapper
    if not S.loggedPerk then S.loggedPerk = true; log("perk bundle hook installed on " .. #keys .. " key(s)") end
    return true
end

local seenRefs = {}
local function addCells(tab)
    if type(tab) ~= "table" then return end
    local ref = g(tab, "ref")
    local items = g(tab, "items")
    local key = tostring(ref)
    if not seenRefs[key] then
        seenRefs[key] = true
        local refs = {}
        if type(items) == "table" then
            for i, it in ipairs(items) do if i <= 8 then refs[#refs + 1] = tostring(g(it, "itemref")) end end
        end
        log("menu tab seen: ref=" .. key .. " items=" .. (type(items) == "table" and #items or -1) ..
            " first=" .. table.concat(refs, ","))
    end
    if (ref ~= "wunderfizz_perks" and ref ~= hk("wunderfizz_perks") and tostring(ref) ~= tostring(hk("wunderfizz_perks"))) or type(items) ~= "table" then return end
    local fallbackTemplate = items[1]
    local nativeSwitches = {
        ["specialty_juggernog"] = "bo7_cp_off_native_juggernog",
        ["specialty_quick_revive"] = "bo7_cp_off_native_quick_revive",
        ["specialty_speedcola"] = "bo7_cp_off_native_speedcola",
        ["specialty_staminup"] = "bo7_cp_off_native_staminup",
        ["specialty_deadshot"] = "bo7_cp_off_native_deadshot",
        ["specialty_elemental_pop"] = "bo7_cp_off_native_elemental_pop",
        ["specialty_phd_flopper"] = "bo7_cp_off_native_phd_flopper",
        ["specialty_death_perception"] = "bo7_cp_off_native_death_perception",
        ["specialty_vulture_aid"] = "bo7_cp_off_native_vulture_aid",
        ["specialty_m_mod"] = "bo7_cp_off_native_m_mod",
        ["specialty_d_mod"] = "bo7_cp_off_native_d_mod",
        ["specialty_w_mod"] = "bo7_cp_off_native_w_mod",
        ["specialty_y_mod"] = "bo7_cp_off_native_y_mod",
        ["specialty_z_mod"] = "bo7_cp_off_native_z_mod",
    }
    for i = #items, 1, -1 do
        local itemRef = g(items[i], "itemref")
        for nativeRef, setting in pairs(nativeSwitches) do
            if (itemRef == nativeRef or itemRef == hk(nativeRef) or tostring(itemRef) == tostring(hk(nativeRef))) and (function() local getter = g(rawget(_G, "Dvar"), "GetDvarString"); local hash = rawget(_G, "xhashdvar"); if type(getter) ~= "function" or type(hash) ~= "function" then return false end; local ok, value = pcall(getter, hash(setting)); return ok and tostring(value) == "1" end)() then
                table.remove(items, i)
                break
            end
        end
    end
    local present, template = {}, nil
    for _, it in ipairs(items) do
        local r = g(it, "itemref")
        present[r or ""] = it
        if r == "specialty_juggernog" or r == hk("specialty_juggernog") then template = it end
    end
    if not template then template = items[1] or fallbackTemplate end
    if not template then return end
    local hashedRefs = type(g(template, "itemref")) == "number"
    local customItems = {}
    for _, c in ipairs(CUSTOM) do
      if c.cell ~= false and isCustomPerkAvailable and isCustomPerkAvailable(c) then
        local item = present[c.ref] or present[hk(c.ref) or ""]
        if not item then
            item = {}
            for k, v in pairs(template) do item[k] = v end
            local refValue = c.ref
            if hashedRefs then refValue = hk(c.ref) or c.ref end
            s(item, "itemref", refValue)
            for _, f in ipairs({ "maxpurchasederrorstring", "progressiongating", "unlockitemref", "loottype", "omnvaritem",
                                 "itempurchasecountomnvar", "itempurchasestockomnvar", "maxstack", "haspurchaselimit", "purchaselimit" }) do
                s(item, f, nil)
            end
            s(item, "menuitemindex", 1700 + c.code)
            s(item, "purchasenotify", "perk_choice_purchase")
            s(item, "showtail", true)
            present[refValue] = item
        end
        for _, f in ipairs({ "maxpurchasederrorstring", "progressiongating", "unlockitemref", "loottype", "omnvaritem",
                             "itempurchasecountomnvar", "itempurchasestockomnvar", "maxstack", "haspurchaselimit", "purchaselimit" }) do
            s(item, f, nil)
        end
        s(item, "displayname", c.name)
        s(item, "shortdisplayname", c.name)
        s(item, "description", c.desc)
        s(item, "menuitemindex", 1700 + c.code)
        s(item, "purchasenotify", "perk_choice_purchase")
        if c.icon then s(item, "image", c.icon); s(item, "toplineimage", c.icon) end
        customItems[#customItems + 1] = item
      end
    end

    for index = #items, 1, -1 do
        local itemRef = g(items[index], "itemref")
        if byRef[itemRef] or byRef[tostring(itemRef)] then
            table.remove(items, index)
        end
    end
    for _, item in ipairs(customItems) do
        s(item, "tabitemindex", #items + 1)
        table.insert(items, item)
    end
    if S.loggedCells ~= #customItems then
        S.loggedCells = #customItems
        log("Wunderfizz cells appended: " .. #customItems .. " custom (items now " .. #items .. ")")
        local fields = {}
        for k, v in pairs(tab) do
            local t = type(v)
            fields[#fields + 1] = tostring(k) .. "=" .. ((t == "table") and ("table#" .. #v) or (t == "function" and "fn" or tostring(v)))
        end
        log("Wunderfizz tab fields: " .. table.concat(fields, ", "))
        local tmplFields = {}
        for k, v in pairs(items[1]) do tmplFields[#tmplFields + 1] = tostring(k) .. "=" .. tostring(v) end
        log("Wunderfizz first item fields: " .. table.concat(tmplFields, ", "))
    end
end

local function processResult(res)
    if type(res) ~= "table" then return end
    if type(g(res, "items")) == "table" then
        local ok, e = pcall(addCells, res)
        if not ok and not S.errCell then S.errCell = true; log("addCells error: " .. tostring(e)) end
    else
        for _, tab in ipairs(res) do
            local ok, e = pcall(addCells, tab)
            if not ok and not S.errCell then S.errCell = true; log("addCells error: " .. tostring(e)) end
        end
    end
end

local function hookMenuFn(PMU, name, tag)
    local keys = allFnKeys(PMU, name)
    if #keys == 0 then return false end
    local st = S.hooks[tag] or {}
    S.hooks[tag] = st
    if st.wrapper then
        local all = true
        for _, e in ipairs(keys) do if e.fn ~= st.wrapper then all = false end end
        if all then return true end
    else
        st.original = keys[1].fn
        st.wrapper = function(...)
            if tag == "buttonAction" then
                local button = select(1, ...)
                local ok, data = pcall(function() return button:getbuttondata() end)
                if ok and type(data) == "table" then
                    local index = g(data, "menuitemindex")
                    if index == 1770 or index == 1771 or index == 1772 then
                        local key = "loggedClick_" .. tostring(index)
                        if not S[key] then
                            S[key] = true
                            log("custom cell click: ref=" .. tostring(g(data, "itemref")) ..
                                " channel=" .. tostring(g(data, "purchasenotify")) ..
                                " index=" .. tostring(index))
                        end
                    end
                end
            end
            log("Wunderfizz open trace: enter " .. name)
            local res = st.original(...)
            log("Wunderfizz open trace: returned " .. name)
            if not S["called_" .. tag] then S["called_" .. tag] = true; log(name .. " wrapper called") end
            processResult(res)
            log("Wunderfizz open trace: processed " .. name)
            return res
        end
    end
    for _, e in ipairs(keys) do PMU[e.key] = st.wrapper end
    if not st["logged"] then st.logged = true; log(name .. " hooked on " .. #keys .. " key(s)") end
    return true
end

local function installMenu()
    local PMU = rawget(_G, "PurchaseMenuUtils")
    if type(PMU) ~= "table" then return false end
    local a = hookMenuFn(PMU, "setupmenutabinfo", "menuInfo")
    local b = hookMenuFn(PMU, "setuptabinfostruct", "tabStruct")
    local c = hookMenuFn(PMU, "zmhandlebuttonaction", "buttonAction")
    return a or b or c
end

local function installNotifyServer()
    local engine = rawget(_G, "Engine")
    if engine == nil then return false end
    local keys = allFnKeys(engine, "NotifyServer")
    if #keys == 0 then return false end

    local st = S.hooks.engineNotify
    if not st then
        st = { original = keys[1].fn }
        st.wrapper = function(channel, value, ...)
            if channel == "perk_choice_purchase" and (value == 1770 or value == 1771 or value == 1772) then
                log("Engine.NotifyServer called: channel=" .. tostring(channel) .. " index=" .. tostring(value))
            end
            return st.original(channel, value, ...)
        end
        S.hooks.engineNotify = st
    end

    for _, e in ipairs(keys) do
        local ok, err = pcall(function() engine[e.key] = st.wrapper end)
        if not ok then
            if not st.failed then
                st.failed = true
                log("Engine.NotifyServer hook failed: " .. tostring(err))
            end
            return false
        end
    end

    if not st.logged then
        st.logged = true
        log("Engine.NotifyServer hook installed")
    end
    return true
end

local function readDebugDvar(name)
    local dvar = rawget(_G, "Dvar")
    local getter = g(dvar, "GetDvarString")
    local hashDvar = rawget(_G, "xhashdvar") or rawget(_G, "PushXHashDvar")
    local clua = rawget(_G, "CLUA")
    if type(hashDvar) ~= "function" and type(clua) == "table" then
        hashDvar = g(clua, "PushXHashDvar")
    end
    if type(getter) ~= "function" or type(hashDvar) ~= "function" then
        if not S.errDvarReadback then
            S.errDvarReadback = true
            log("Dvar readback unavailable (GetDvarString or xhashdvar missing)")
        end
        return nil
    end
    local okHash, dvarHash = pcall(hashDvar, name)
    if not okHash then
        if not S.errDvarHash then
            S.errDvarHash = true
            log("Dvar hash failed for " .. name)
        end
        return nil
    end
    local ok, value = pcall(getter, dvarHash)
    if not ok then
        if not S.errDvarGet then
            S.errDvarGet = true
            log("Dvar read failed: " .. tostring(value))
        end
        return nil
    end
    if value == nil then return nil end
    return tostring(value)
end

local function readCustomPerkManifest()
    if readDebugDvar("bo7_cp_perk_manifest_ready") ~= "1" then
        if not S.perkManifestWaitLogged then
            S.perkManifestWaitLogged = true
            log("Wunderfizz custom entries hidden until the GSC registration manifest is ready")
        end
        return nil
    end

    local raw = readDebugDvar("bo7_cp_registered_perks")
    if not raw or raw:sub(1, 3) ~= "v1:" then
        if not S.perkManifestInvalidLogged then
            S.perkManifestInvalidLogged = true
            log("Wunderfizz custom entries hidden: registered-perk manifest is missing or invalid")
        end
        return nil
    end

    if S.perkManifestRaw ~= raw then
        local registered = {}
        for id in raw:sub(4):gmatch("[^,]+") do
            registered[id] = true
        end
        S.perkManifestRaw = raw
        S.perkManifest = registered
        log("GSC registered-perk manifest ready: " .. (raw:sub(4) ~= "" and raw:sub(4) or "(none)"))
    end
    return S.perkManifest
end

isCustomPerkAvailable = function(perk)
    if type(perk) ~= "table" then return false end
    local manifest = readCustomPerkManifest()
    if not manifest then
        
        
        
        local frontend = g(rawget(_G, "Engine"), "InFrontend")
        local client = g(rawget(_G, "Game"), "getplayerclientnum")
        if type(frontend) ~= "function" or type(client) ~= "function" then return false end
        local frontOk, inFrontend = pcall(frontend)
        local slotOk, slot = pcall(client, 0)
        slot = slotOk and tonumber(slot) or nil
        if not frontOk or inFrontend ~= false or not slot or slot < 0 or slot > 3 or slot ~= math.floor(slot) then return false end
        if not S.loggedLocalPerkCatalog then
            S.loggedLocalPerkCatalog = true
            log("In-match custom perk catalog enabled locally; server manifest unavailable, purchases remain server-validated")
        end
        return byRef[perk.ref] ~= nil
    end
    local id = perk.id or tostring(perk.ref or ""):gsub("^specialty_", "")
    return manifest[id] == true
end

local function installOwnedPerkDisplay()
    local perks = rawget(_G, "ZMPERK")
    if type(perks) ~= "table" then return false end
    local keys = allFnKeys(perks, "HasPerk")
    if #keys == 0 then return false end

    local st = S.hooks.ownedPerkDisplay
    if not st then
        st = { original = keys[1].fn }
        st.wrapper = function(controller, ref, ...)
            local custom = byRef[ref] or byRef[tostring(ref)]
            if custom then
                local owned = readDebugDvar("bo7_cp_client_owned_" .. custom.ref:gsub("^specialty_", ""))
                if owned == "1" or owned == "true" then
                    S.owned[custom.ref] = true
                elseif owned == "0" or owned == "false" then
                    S.owned[custom.ref] = false
                end
                local checkState = tostring(owned) .. "/" .. tostring(S.owned[custom.ref])
                if S["lastOwnedCheck_" .. custom.ref] ~= checkState then
                    S["lastOwnedCheck_" .. custom.ref] = checkState
                    log("HasPerk custom check: ref=" .. tostring(ref) ..
                        " marker=" .. tostring(owned) ..
                        " cached=" .. tostring(S.owned[custom.ref]))
                end
                if S.owned[custom.ref] then return true end
            end
            return st.original(controller, ref, ...)
        end
        S.hooks.ownedPerkDisplay = st
    end

    for _, e in ipairs(keys) do perks[e.key] = st.wrapper end
    if not st.logged then
        st.logged = true
        log("owned perk display hook installed on " .. #keys .. " key(s)")
    end
    return true
end

local function customHudThemeActive()
    for _, name in ipairs({ "BO4HUDPost", "HaloUI" }) do
        local api = rawget(_G, name)
        local themes = g(api, "themes")
        local current = g(themes, "current")
        if type(current) == "function" then
            local ok, theme = pcall(current, 0)
            if ok and theme ~= nil then return true end
        end
    end
    return false
end

local function stockHudPerkDataLookup()
    local debugApi = rawget(_G, "debug")
    if type(debugApi) ~= "table" or type(debugApi.getinfo) ~= "function" then
        if not S.stockHudPerkLookupUnavailableLogged then
            S.stockHudPerkLookupUnavailableLogged = true
            log("stock HUD lookup detection unavailable; preserving custom perk IDs")
        end
        return false
    end
    for level = 2, 12 do
        local ok, info = pcall(debugApi.getinfo, level, "S")
        local source = ok and info and info.source
        if type(source) == "string" and source:lower():find("zmperkutils", 1, true) then
            if not S.stockHudPerkLookupLogged then
                S.stockHudPerkLookupLogged = true
                log("filtering custom IDs from stock HUD data lookup")
            end
            return true
        end
    end
    return false
end

local function installHudPerkIds()
    local perks = rawget(_G, "ZMPERK")
    if type(perks) ~= "table" then return false end
    local keys = allFnKeys(perks, "getperkrefbyid")
    if #keys == 0 then return false end

    local st = S.hooks.hudPerkIds
    if not st then
        st = { original = keys[1].fn }
        st.wrapper = function(id, ...)
            for _, c in ipairs(CUSTOM) do
                if isCustomPerkAvailable and isCustomPerkAvailable(c) then
                    local customId = tonumber(readDebugDvar("bo7_cp_hud_id_" .. c.ref:gsub("^specialty_", "")))
                    if customId and tonumber(id) == customId then
                        
                        
                        return c.ref
                    end
                end
            end
            return st.original(id, ...)
        end
        S.hooks.hudPerkIds = st
    end

    for _, e in ipairs(keys) do perks[e.key] = st.wrapper end
    local idsToRefs = g(perks, "perks_id_to_ref")
    if type(idsToRefs) == "table" then
        for _, c in ipairs(CUSTOM) do
            if isCustomPerkAvailable and isCustomPerkAvailable(c) then
                local customId = tonumber(readDebugDvar("bo7_cp_hud_id_" .. c.ref:gsub("^specialty_", "")))
                if customId and customId >= 1 and customId <= 31 then
                    idsToRefs[customId] = c.ref
                    local logKey = "loggedHudId_" .. c.ref
                    if not S[logKey] then
                        S[logKey] = true
                        log("HUD perk ID mapped: " .. c.ref .. " id=" .. customId)
                    end
                end
            end
        end
    end
    if not st.logged then
        st.logged = true
        log("HUD perk ID mapping hook installed")
    end
    return true
end

local function closeOverflowPerkIcons()
    for _, slot in ipairs(S.overflowPerkIcons or {}) do
        local widget = slot.root or slot
        pcall(function() widget:closeTree() end)
    end
    S.overflowPerkIcons = {}
    S.overflowPerkRoot = nil
end

local function hideOverflowPerkIcons()
    for _, slot in ipairs(S.overflowPerkIcons or {}) do
        local widget = slot.root or slot
        pcall(function() widget:SetAlpha(0, 0) end)
    end
end

local function overflowPerkIconValue(item, ctrl)
    for _, name in ipairs({ "image", "icon", "imageName", "perkIcon", "hudimage", "legacyimage", "bwimage" }) do
        local keys = { name }
        local hashed = hk(name)
        if hashed ~= nil and hashed ~= name then keys[#keys + 1] = hashed end
        local lowerHashed = hk(name:lower())
        if lowerHashed ~= nil and lowerHashed ~= name and lowerHashed ~= hashed then
            keys[#keys + 1] = lowerHashed
        end
        for _, key in ipairs(keys) do
            local ok, source = pcall(function() return item[key] end)
            if ok and source ~= nil then
                local okValue, value = pcall(function()
                    local sourceType = type(source)
                    if sourceType ~= "table" and sourceType ~= "userdata" then return source end
                    if type(source.GetValue) == "function" then return source:GetValue(ctrl) end
                    return source
                end)
                if okValue and value ~= nil and value ~= "" then return value end
            end
        end
    end
end

local function stockHudOverflowPerkRefs()
    if S.stockHudOverflowRefsSnapshot and S.polls - S.stockHudOverflowRefsPoll < 3 then
        return S.stockHudOverflowRefsSnapshot
    end
    local value = readDebugDvar("bo7_cp_client_overflow_perks")
    if not value or value:sub(1, 3) ~= "v1:" then return nil end

    local refs = {}
    for ref in value:sub(4):gmatch("[^,]+") do
        refs[#refs + 1] = ref
    end
    S.stockHudOverflowRefsSnapshot = refs
    S.stockHudOverflowRefsPoll = S.polls
    return refs
end

local function slotHudStatus(message)
    if S.lastSlotHudStatus ~= message then
        S.lastSlotHudStatus = message
        log("HUD snapshot: " .. message)
    end
end

local function localPlayerPerkSnapshot()
    local frontend = g(rawget(_G, "Engine"), "InFrontend")
    if type(frontend) ~= "function" then return nil end
    local okFront, isFront = pcall(frontend)
    if not okFront or isFront ~= false then return nil end
    local getClient = g(rawget(_G, "Game"), "getplayerclientnum")
    if type(getClient) ~= "function" then slotHudStatus("local-player API unavailable"); return nil end
    local okClient, slot = pcall(getClient, 0)
    slot = okClient and tonumber(slot) or nil
    if not slot or slot < 0 or slot > 3 or slot ~= math.floor(slot) then
        slotHudStatus("invalid local slot=" .. tostring(slot)); return nil
    end
    local value = readDebugDvar("bo7_cp_hud_slot_" .. tostring(slot))
    local prefix = "slot=" .. tostring(slot) .. ";v1:"
    if type(value) ~= "string" or value:sub(1, #prefix) ~= prefix then
        slotHudStatus("slot=" .. tostring(slot) .. " waiting; server=" .. tostring(readDebugDvar("bo7_cp_hud_watch_debug")))
        return nil
    end
    local payload = value:sub(#prefix + 1)
    local owned, eternal = payload:match("^(.-);eternal:(.*)$")
    S.eternalPerkRefs = {}
    for ref in (eternal or ""):gmatch("[^,]+") do S.eternalPerkRefs[ref] = true end
    local result = "v1:" .. (owned or payload)
    slotHudStatus("slot=" .. tostring(slot) .. " full list=" .. result)
    return result
end

local function stockHudAllPerkRefs()
    if S.stockHudAllRefsSnapshot and S.polls - S.stockHudAllRefsPoll < 3 then
        return S.stockHudAllRefsSnapshot
    end
    local value = localPlayerPerkSnapshot() or readDebugDvar("bo7_cp_client_all_perks")
    if not value or value:sub(1, 3) ~= "v1:" then return nil end

    local refs, seen = {}, {}
    for ref in value:sub(4):gmatch("[^,]+") do
        if ref ~= "" and not seen[ref] then
            refs[#refs + 1] = ref
            seen[ref] = true
        end
    end
    S.stockHudAllRefsSnapshot = refs
    S.stockHudAllRefsPoll = S.polls
    return refs
end

local function stockHudPerkItemByRef(ref)
    S.stockHudOverflowItemsByRef = S.stockHudOverflowItemsByRef or {}
    local cached = S.stockHudOverflowItemsByRef[ref]
    if cached then return cached end

    local getBundle = g(rawget(_G, "PERK"), "GetBundleByRef")
    local customPerk = byRef[ref] or byRef[tostring(ref)]
    local icon = (customPerk and customPerk.icon) or PERK_PACK_ICONS[ref] or PERK_PACK_ICONS[tostring(ref)]
    if icon == nil and type(getBundle) == "function" then
        local okBundle, bundle = pcall(getBundle, ref)
        if okBundle and type(bundle) == "table" then
            icon = overflowPerkIconValue(bundle, 0)
        end
    end
    if icon == nil then
        local filters = g(rawget(_G, "PERK"), "filters")
        local getIcon = g(filters, "getperkicon")
        if type(getIcon) == "function" then
            local okIcon, value = pcall(getIcon, ref)
            if okIcon and value ~= nil and value ~= "" then icon = value end
        end
    end
    icon = customPackIcon(icon)
    local item = { icon = icon, ref = ref }
    if item.icon ~= nil then S.stockHudOverflowItemsByRef[ref] = item end
    return item
end

local function stockHudOwnedPerks()
    if S.stockHudOwnedSnapshot and S.polls - S.stockHudOwnedSnapshotPoll < 5 then
        return S.stockHudOwnedSnapshot
    end
    local zmPerk = rawget(_G, "ZMPERK")
    local getList = g(zmPerk, "getperklist")
    local hasPerkKeys = allFnKeys(zmPerk, "HasPerk")
    local getBundle = g(rawget(_G, "PERK"), "GetBundleByRef")
    if type(getList) ~= "function" or #hasPerkKeys == 0 or type(getBundle) ~= "function" then
        return nil
    end

    local okList, entries = pcall(getList)
    if not okList or type(entries) ~= "table" then
        okList, entries = pcall(getList, 0)
    end
    if not okList or type(entries) ~= "table" then return nil end

    local nativeOwned, customOwned, seen = {}, {}, {}
    local function addOwnedRef(ref, entry)
        if ref == nil then return end
        local custom = byRef[ref] or byRef[tostring(ref)]
        local refKey = custom and custom.ref or tostring(ref)
        if seen[refKey] then return end
        seen[refKey] = true
        local okOwned, isOwned = pcall(hasPerkKeys[1].fn, 0, ref)
        if okOwned and isOwned then
            local okBundle, bundle = pcall(getBundle, ref)
            if not okBundle or type(bundle) ~= "table" then bundle = g(entry, "data") end
            local icon = bundle and overflowPerkIconValue(bundle, 0)
            if icon then
                local destination = custom and customOwned or nativeOwned
                destination[#destination + 1] = { icon = icon, ref = ref }
            elseif not S.stockHudPerkIconMissingLogged then
                S.stockHudPerkIconMissingLogged = true
                log("Stock HUD overflow: owned perk icon unavailable for " .. refKey)
            end
        end
    end
    for _, entry in ipairs(entries) do
        addOwnedRef(g(entry, "ref"), entry)
    end
    for _, c in ipairs(CUSTOM) do
        if isCustomPerkAvailable and isCustomPerkAvailable(c) then
            addOwnedRef(c.ref)
        end
    end
    local owned = { native = nativeOwned, custom = customOwned }
    S.stockHudOwnedSnapshot = owned
    S.stockHudOwnedSnapshotPoll = S.polls
    return owned
end

local function overflowPerkList()
    local paths = {
        { "inGame", "ZM", "perks" },
        { "inGame", "ZM", "perks", "list" },
        { "inGame", "player", "perks" },
    }
    local roots = {}
    local plainRoot = rawget(_G, "DataSources")
    local hashedRoot = rawget(_G, "_DataSources")
    if plainRoot then roots[#roots + 1] = plainRoot end
    if hashedRoot and hashedRoot ~= plainRoot then roots[#roots + 1] = hashedRoot end

    local function child(node, key)
        local keys = { key }
        local hashed = hk(key)
        if hashed ~= nil and hashed ~= key then keys[#keys + 1] = hashed end
        local lowerHashed = hk(key:lower())
        if lowerHashed ~= nil and lowerHashed ~= key and lowerHashed ~= hashed then
            keys[#keys + 1] = lowerHashed
        end
        for _, candidate in ipairs(keys) do
            local ok, value = pcall(function() return node[candidate] end)
            if ok and value ~= nil then return value end
        end
    end

    for _, root in ipairs(roots) do
        for _, path in ipairs(paths) do
            local node = root
            for _, key in ipairs(path) do
                node = child(node, key)
                if node == nil then break end
            end
            if node then
                local okList, valid = pcall(function()
                    return type(node.GetCountValue) == "function"
                        and type(node.GetDataSourceAtIndex) == "function"
                end)
                if okList and valid then return node end
            end
        end
    end
end

local function stockHudActivePerkOrder()
    local roots = {}
    local hashedRoot = rawget(_G, "_DataSources")
    local plainRoot = rawget(_G, "DataSources")
    if hashedRoot then roots[#roots + 1] = hashedRoot end
    if plainRoot and plainRoot ~= hashedRoot then roots[#roots + 1] = plainRoot end
    local paths = {
        { "zm", "in_game", "player", "perks", "active_perks" },
        { "inGame", "ZM", "player", "perks", "active_perks" },
    }
    local function readValue(node, controller)
        local ok, value = pcall(function()
            if type(node) == "table" or type(node) == "userdata" then
                local getter = node.GetValue
                if type(getter) == "function" then return getter(node, controller) end
            end
            return node
        end)
        return ok and value or nil
    end

    for _, root in ipairs(roots) do
        if root then
            for _, path in ipairs(paths) do
                local node = root
                for _, key in ipairs(path) do
                    node = g(node, key)
                    if node == nil then break end
                end
                if node then
                    local count = tonumber(readValue(g(node, "count"), 0))
                    local getPerkRef = g(rawget(_G, "ZMPERK"), "getperkrefbyid")
                    if count and count >= 0 and count <= 24 and type(getPerkRef) == "function" then
                        local refs, valid = {}, true
                        for index = 1, math.floor(count) do
                            local okSlot, slot = pcall(function() return node[index] end)
                            local id = okSlot and tonumber(readValue(g(slot, "id"), 0))
                            if not id or id <= 0 then
                                valid = false
                                break
                            end
                            local okRef, ref = pcall(getPerkRef, id)
                            if not okRef or ref == nil then
                                valid = false
                                break
                            end
                            refs[#refs + 1] = ref
                        end
                        if valid then return refs end
                    end
                end
            end
        end
    end
end

local function stockHudRoot()
    local lui = rawget(_G, "LUI")
    if type(lui) ~= "table" or type(lui.GetRoot) ~= "function" then return nil end
    local ok, root = pcall(lui.GetRoot)
    return ok and root or nil
end

local function installNativePerkCapture()
    local lui = rawget(_G, "LUI")
    local targets = {
        { owner = rawget(_G, "MenuBuilder"), name = "BuildRegisteredType", key = "nativePerkCapture", method = false },
        { owner = g(lui, "UIElement"), name = "AddWidget", key = "nativePerkAddWidget", method = true },
    }
    for _, target in ipairs(targets) do
        local keys = allFnKeys(target.owner, target.name)
        if #keys > 0 then
            local st = S.hooks[target.key]
            if not st then
                st = { original = keys[1].fn, method = target.method }
                st.wrapper = function(...)
                    local widget = st.original(...)
                    local name = select(st.method and 2 or 1, ...)
                    if S.enabled and widget and (name == "perkcontainer" or name == hk("perkcontainer")) then
                        S.nativePerkContainers = S.nativePerkContainers or setmetatable({}, { __mode = "k" })
                        if not S.nativePerkContainers[widget] then log("Native perk widget captured") end
                        S.nativePerkContainers[widget] = true
                        if S.fullPerkHudRendered then pcall(function() widget:SetAlpha(0, 0) end) end
                    end
                    return widget
                end
                S.hooks[target.key] = st
            end
            for _, entry in ipairs(keys) do target.owner[entry.key] = st.wrapper end
        end
    end
end

local function findNativePerkContainer(root)
    for widget in pairs(S.nativePerkContainers or {}) do
        local okParent, parent = pcall(function() return widget:getParent() end)
        if okParent and parent ~= nil then
            if S.stockHudNativePerkContainer ~= widget then
                S.stockHudNativePerkContainer = widget
                S.stockHudNativePerkRoot = root
                local okAlpha, alpha = pcall(function() return widget:GetAlpha() end)
                S.stockHudNativePerkAlpha = okAlpha and tonumber(alpha) or 1
            end
            return widget
        end
    end
    local cached = S.stockHudNativePerkContainer
    if cached and S.stockHudNativePerkRoot == root then
        local okParent, parent = pcall(function() return cached:getParent() end)
        if not okParent or parent ~= nil then return cached end
        S.stockHudNativePerkContainer = nil
    end

    if S.stockHudPerkContainerSearchRoot ~= root then
        S.stockHudPerkContainerSearchRoot = root
        S.stockHudPerkContainerSearchCooldown = 0
    elseif (S.stockHudPerkContainerSearchCooldown or 0) > 0 then
        S.stockHudPerkContainerSearchCooldown = S.stockHudPerkContainerSearchCooldown - 1
        return nil
    end

    local maxNodes = 20000
    local queue = { root }
    local visited = {}
    local cursor = 1
    while cursor <= #queue and cursor <= maxNodes do
        local node = queue[cursor]
        cursor = cursor + 1
        if node ~= nil and not visited[node] then
            visited[node] = true
            local okId, id = pcall(function() return g(node, "id") end)
            if okId and id == "perkcontainer" then
                S.stockHudNativePerkContainer = node
                S.stockHudNativePerkRoot = root
                local okAlpha, alpha = pcall(function() return node:GetAlpha() end)
                S.stockHudNativePerkAlpha = okAlpha and tonumber(alpha) or 1
                S.stockHudPerkContainerSearchCooldown = 0
                return node
            end

            local okFirst, child = pcall(function() return node:getFirstChild() end)
            if okFirst then
                local siblingSeen = {}
                local childCount = 0
                while child and not siblingSeen[child] and childCount < 256 and #queue < maxNodes do
                    siblingSeen[child] = true
                    childCount = childCount + 1
                    queue[#queue + 1] = child
                    local okNext, nextChild = pcall(function() return child:getNextSibling() end)
                    if not okNext then break end
                    child = nextChild
                end
            end
        end
    end

    S.stockHudPerkContainerSearchCooldown = 10
    if cursor > maxNodes and not S.stockHudPerkContainerSearchLimitLogged then
        S.stockHudPerkContainerSearchLimitLogged = true
        log("Stock HUD native perk search reached its node limit")
    end
    return nil
end

local restoreNativePerkVisibility
local function restoreNativePerkContainer()
    S.fullPerkHudRendered = false
    local container = S.stockHudNativePerkContainer
    if container then
        local alpha = S.stockHudNativePerkAlpha
        if type(alpha) ~= "number" then alpha = 1 end
        pcall(function() container:SetAlpha(alpha, 0) end)
    end
    S.stockHudNativePerkContainer = nil
    S.stockHudNativePerkRoot = nil
    S.stockHudNativePerkAlpha = nil
    if restoreNativePerkVisibility then restoreNativePerkVisibility() end
end

local function hideNativePerkContainer(container)
    if not container then return false end
    if S.stockHudNativePerkContainer ~= container then
        S.stockHudNativePerkContainer = container
        local okAlpha, alpha = pcall(function() return container:GetAlpha() end)
        S.stockHudNativePerkAlpha = okAlpha and tonumber(alpha) or 1
    end
    local ok = pcall(function() container:SetAlpha(0, 0) end)
    return ok
end

local function stockHudPerkContainerVisible()
    local roots = {}
    local hashedRoot = rawget(_G, "_DataSources")
    local plainRoot = rawget(_G, "DataSources")
    if hashedRoot then roots[#roots + 1] = hashedRoot end
    if plainRoot and plainRoot ~= hashedRoot then roots[#roots + 1] = plainRoot end

    for _, root in ipairs(roots) do
        local node = root
        for _, key in ipairs({ "zm", "in_game", "player", "perks", "perk_container_visibility" }) do
            node = g(node, key)
            if node == nil then break end
        end
        if node ~= nil then
            local okValue, value = pcall(function()
                if type(node.GetValue) == "function" then return node:GetValue(0) end
                return nil
            end)
            if okValue and type(value) == "boolean" then return value end
        end
    end
    return true
end

local function nativePerkVisibilitySource()
    local roots = {}
    local hashedRoot = rawget(_G, "_DataSources")
    local plainRoot = rawget(_G, "DataSources")
    if hashedRoot then roots[#roots + 1] = hashedRoot end
    if plainRoot and plainRoot ~= hashedRoot then roots[#roots + 1] = plainRoot end

    for _, root in ipairs(roots) do
        local node = root
        for _, key in ipairs({ "zm", "in_game", "player", "perks", "perk_container_visibility" }) do
            node = g(node, key)
            if node == nil then break end
        end
        if node ~= nil then return node end
    end
    return nil
end

local function writeNativePerkVisibility(value)
    local source = nativePerkVisibilitySource()
    if source == nil then return false end

    local okModel, model = pcall(function()
        if type(source.GetModel) == "function" then return source:GetModel(0) end
        return nil
    end)
    local dataModel = rawget(_G, "DataModel")
    local setModelValue = g(dataModel, "SetModelValue")
    if okModel and model ~= nil and type(setModelValue) == "function" then
        pcall(setModelValue, model, value)
    end

    pcall(function()
        if type(source.SetValue) == "function" then source:SetValue(0, value) end
    end)
    local okValue, current = pcall(function() return source:GetValue(0) end)
    return okValue and current == value
end

local function hideNativePerkVisibility()
    local source = nativePerkVisibilitySource()
    if source == nil then return false end
    if S.stockHudNativePerkVisibilityOriginal == nil then
        local okValue, current = pcall(function() return source:GetValue(0) end)
        if okValue and type(current) == "boolean" then
            S.stockHudNativePerkVisibilityOriginal = current
        end
    end

    local okValue, current = pcall(function() return source:GetValue(0) end)
    if okValue and current == false then return true end
    return writeNativePerkVisibility(false)
end

restoreNativePerkVisibility = function()
    local original = S.stockHudNativePerkVisibilityOriginal
    if type(original) == "boolean" then writeNativePerkVisibility(original) end
    S.stockHudNativePerkVisibilityOriginal = nil
end

local CUSTOM_PERK_ROW_LIMIT = 22
local STOCK_HUD_NATIVE_PERK_LIMIT = 16
local DEBUG_PERK_HUD_AT_TOP = false
local CUSTOM_PERK_ROW_VERTICAL_SHIFT = 6
local CUSTOM_PERK_ROW_SPACING = 30

local function appendPerkRows(rows, items, firstRow, maxColumns)
    local index = 1
    local row = firstRow
    while index <= #items do
        local rowCount = math.min(maxColumns, #items - index + 1)
        for column = 0, rowCount - 1 do
            rows[#rows + 1] = {
                item = items[index],
                row = row,
                column = column,
                rowCount = rowCount,
            }
            index = index + 1
        end
        row = row + 1
    end
end

local function buildFullPerkRows(refs)
    local native, custom, seen = {}, {}, {}
    for _, ref in ipairs(refs) do
        local customPerk = byRef[ref] or byRef[tostring(ref)]
        local key = customPerk and customPerk.ref or tostring(ref)
        if not seen[key] then
            seen[key] = true
            local item = stockHudPerkItemByRef(ref)
            if item.icon == nil then return nil end
            local destination = customPerk and custom or native
            destination[#destination + 1] = item
        end
    end

    local combined = {}
    for _, item in ipairs(native) do combined[#combined + 1] = item end
    for _, item in ipairs(custom) do combined[#combined + 1] = item end

    local rows = {}
    local bottom, upper = {}, {}
    for index, item in ipairs(combined) do
        if index <= CUSTOM_PERK_ROW_LIMIT then
            bottom[#bottom + 1] = item
        else
            upper[#upper + 1] = item
        end
    end
    appendPerkRows(rows, bottom, 0, CUSTOM_PERK_ROW_LIMIT)
    appendPerkRows(rows, upper, 1, CUSTOM_PERK_ROW_LIMIT)
    return rows, #combined
end

local function buildOverflowRows(items)
    local rows = {}
    appendPerkRows(rows, items, 1, 15)
    return rows
end

local function renderStockHudPerkIcons(root, rows, total)
    local icons = S.overflowPerkIcons
    local pack = readDebugDvar("kr_perk_icons") or ""
    if S.activePerkIconPack ~= pack then
        S.activePerkIconPack = pack
        S.stockHudPerkMaterials = {}
        log("HUD icon pack: " .. (pack ~= "" and pack or "Black Ops 7"))
    end
    local scale = 1.5 * math.max(0.82, 1 - math.max(0, total - CUSTOM_PERK_ROW_LIMIT) * 0.004)
    local materials = {}
    local selectedEternalFrame
    local frameStyle = tonumber(readDebugDvar("bo7_cp_eternal_frame_style")) or 0
    for _, entry in ipairs(rawget(_G, "BO7EternalFramePacks") or {}) do
        if entry.id == frameStyle then selectedEternalFrame = entry; break end
    end
    local eternalImage = selectedEternalFrame and selectedEternalFrame.material or "ui_icon_eternalperk"
    if S.eternalFrameImage ~= eternalImage then
        S.eternalFrameImage = eternalImage
        S.eternalFrameMaterial = nil
    end
    local eternalMaterial = S.eternalFrameMaterial
    if eternalMaterial == nil then
        local register = rawget(_G, "RegisterMaterial")
        local hashAsset = rawget(_G, "xhashasset") or g(rawget(_G, "CLUA"), "PushXHashAsset")
        if type(register) == "function" and type(hashAsset) == "function" then
            local ok, material = pcall(function() return register(hashAsset(eternalImage)) end)
            if ok and material then S.eternalFrameMaterial = material; eternalMaterial = material end
        end
    end
    local materialCache = S.stockHudPerkMaterials or {}
    S.stockHudPerkMaterials = materialCache

    for ordinal, row in ipairs(rows) do
        local ref = row.item and row.item.ref
        local custom = ref and (byRef[ref] or byRef[tostring(ref)])
        local iconValue = (custom and custom.icon) or (ref and (PERK_PACK_ICONS[ref] or PERK_PACK_ICONS[tostring(ref)])) or (row.item and overflowPerkIconValue(row.item, 0))
        if iconValue == nil then
            if not S.errOverflowIcon then
                S.errOverflowIcon = true
                log("Stock HUD perk icon missing at position " .. ordinal)
            end
            return false
        end

        iconValue = customPackIcon(iconValue)
        local iconKey = pack .. ":" .. tostring(iconValue)
        local material = materialCache[iconKey]
        if material == nil then
            local asset = iconValue
            local clua = rawget(_G, "CLUA")
            if type(iconValue) == "string" and type(clua) == "table"
                and type(clua.PushXHashAsset) == "function" then
                local okAsset, pushed = pcall(clua.PushXHashAsset, iconValue)
                if okAsset and pushed ~= nil then asset = pushed end
            end
            local register = rawget(_G, "RegisterMaterial")
            if type(register) ~= "function" then return false end
            local okMaterial, registered = pcall(register, asset)
            if not okMaterial or registered == nil then
                if not S.errOverflowMaterial then
                    S.errOverflowMaterial = true
                    log("Stock HUD perk material unavailable: " .. iconKey)
                end
                return false
            end
            material = registered
            materialCache[iconKey] = material
        end
        materials[ordinal] = { key = iconKey, value = material }
    end

    local okRender, renderError = pcall(function()
        for ordinal, row in ipairs(rows) do
            local slot = icons[ordinal]
            local isNew = slot == nil
            if isNew then
                local frame = LUI.UIElement.new()
                frame:SetHandleMouse(false)
                local image = LUI.UIImage.new()
                image:SetHandleMouse(false)
                local border = LUI.UIImage.new()
                border:SetHandleMouse(false)
                border:SetAlpha(0, 0)
                frame:addElement(border)
                frame:addElement(image)
                slot = { root = frame, image = image, eternalBorder = border }
            end

            local icon = slot.image
            if icon._bo7PerkIconKey ~= materials[ordinal].key then
                icon:setImage(materials[ordinal].value, 0)
                icon._bo7PerkIconKey = materials[ordinal].key
            end
            icon:SetAnchorsAndPosition(
                0, 1, 0, 1,
                scale, 31 * scale, 0, 30 * scale
            )

            local eternal = S.eternalPerkRefs and row.item and S.eternalPerkRefs[tostring(row.item.ref)] == true
            if slot.eternalBorder then
                if eternalMaterial then slot.eternalBorder:setImage(eternalMaterial, 0) end
                local iconSize = 30 * scale
                local frameScale = 1.10
                local source = selectedEternalFrame or {width = 320, height = 308, centerX = 156, centerY = 156, referenceSize = 256}
                frameScale = source.scale or frameScale
                local frameWidth = iconSize * (source.width / source.referenceSize) * frameScale
                local frameHeight = iconSize * (source.height / source.referenceSize) * frameScale
                local frameLeft = scale + iconSize / 2 - frameWidth * (source.centerX / source.width)
                local frameTop = iconSize / 2 - frameHeight * (source.centerY / source.height)
                slot.eternalBorder:SetAnchorsAndPosition(0, 1, 0, 1, frameLeft, frameLeft + frameWidth, frameTop, frameTop + frameHeight)
                slot.eternalBorder:SetAlpha(eternal and eternalMaterial and 1 or 0, 0)
            end

            local left = -row.rowCount * 34 / 2 + row.column *34
            if DEBUG_PERK_HUD_AT_TOP then
                local yTop = 24 + row.row * 41
                slot.root:SetAnchorsAndPosition(
                    0.5, 0.5, 0, 1,
                    left * scale, (left + 32) * scale,
                    yTop * scale, (yTop + 41) * scale
                )
            else
                local yTop = -41 - (row.row * CUSTOM_PERK_ROW_SPACING)
                    + CUSTOM_PERK_ROW_VERTICAL_SHIFT
                slot.root:SetAnchorsAndPosition(
                    0.5, 0.5, 1, 0,
                    left * scale, (left + 32) * scale,
                    yTop * scale, (yTop + 41) * scale
                )
            end
            slot.root:SetAlpha(1, 0)
            if isNew then
                root:addElement(slot.root)
                icons[ordinal] = slot
            end
        end

        for ordinal = #rows + 1, #icons do
            icons[ordinal].root:SetAlpha(0, 0)
        end
    end)

    if not okRender then
        if not S.errOverflowRender then
            S.errOverflowRender = true
            log("Stock HUD perk icon render failed: " .. tostring(renderError))
        end
        return false
    end
    return true
end

local function pauseMenuIsOpen()
    local cod = rawget(_G, "CoD")
    local getPauseMenu = g(cod, "GetPauseMenuFromCurrentContext")
    local flow = g(rawget(_G, "LUI"), "FlowManager")
    local isInStack = g(flow, "IsInStack")
    if type(getPauseMenu) ~= "function" or type(isInStack) ~= "function" then
        if not S.stockHudPauseCheckUnavailableLogged then
            S.stockHudPauseCheckUnavailableLogged = true
            log("Stock HUD pause-menu check unavailable")
        end
        return false
    end

    local okMenu, menu = pcall(getPauseMenu)
    if not okMenu or menu == nil then return false end
    local okOpen, isOpen = pcall(isInStack, menu)
    return okOpen and isOpen == true
end

local function updateStockHudPerkOverflow()
    if customHudThemeActive() then
        restoreNativePerkContainer()
        closeOverflowPerkIcons()
        return
    end
    local engine = rawget(_G, "Engine")
    if type(engine) ~= "table" or type(engine.InFrontend) ~= "function" then
        restoreNativePerkContainer()
        closeOverflowPerkIcons()
        return
    end
    local okFrontend, frontend = pcall(engine.InFrontend)
    if not okFrontend or frontend then
        restoreNativePerkContainer()
        closeOverflowPerkIcons()
        return
    end
    if pauseMenuIsOpen() then
        hideOverflowPerkIcons()
        return
    end

    local root = stockHudRoot()
    if not root then
        if not S.stockHudRootMissingLogged then
            S.stockHudRootMissingLogged = true
            log("Stock HUD overflow: LUI root unavailable")
        end
        restoreNativePerkContainer()
        closeOverflowPerkIcons()
        return
    end
    if S.overflowPerkRoot ~= root then
        restoreNativePerkContainer()
        closeOverflowPerkIcons()
        S.overflowPerkRoot = root
        S.overflowPerkIcons = {}
    end

    local allRefs = stockHudAllPerkRefs()
    if allRefs then
        local nativeVisibilityHidden = false

        local nativeContainer = findNativePerkContainer(root)
        local fullRows, total = buildFullPerkRows(allRefs)
        if not fullRows then
            if not S.stockHudFullIconDataMissingLogged then
                S.stockHudFullIconDataMissingLogged = true
                log("Stock HUD full perk replacement unavailable: an owned perk icon is missing")
            end
        elseif renderStockHudPerkIcons(root, fullRows, total) then
            S.fullPerkHudRendered = true
            nativeVisibilityHidden = hideNativePerkVisibility()
            local nativeHidden = nativeContainer and hideNativePerkContainer(nativeContainer)
            local nativeStatus = nativeHidden and "widget hidden"
                or (nativeVisibilityHidden and "visibility model hidden" or "widget not found")
            local status = "GSC full total=" .. tostring(total) .. " native=" .. nativeStatus
            if S.stockHudOverflowStatus ~= status then
                S.stockHudOverflowStatus = status
                log("Stock HUD perk replacement: " .. status)
            end
            return
        elseif nativeContainer and not S.stockHudPerkHideFailedLogged then
            S.stockHudPerkHideFailedLogged = true
            log("Stock HUD native perk container could not be hidden")
        end

        if nativeVisibilityHidden or nativeContainer then
            hideOverflowPerkIcons()
            restoreNativePerkContainer()
            return
        end
        if not nativeContainer and not S.stockHudPerkContainerMissingLogged then
            S.stockHudPerkContainerMissingLogged = true
            log("Stock HUD perk container not found; keeping native row and overflow fallback")
        end
    else
        restoreNativePerkContainer()
    end

    local overflowItems = {}
    local total
    local sourceName
    local owned = stockHudOwnedPerks()
    if owned then
        local native = owned.native or {}
        local custom = owned.custom or {}
        local combined = {}
        for _, item in ipairs(native) do combined[#combined + 1] = item end
        for _, item in ipairs(custom) do combined[#combined + 1] = item end
        total = #combined
        local activeOrder = stockHudActivePerkOrder()
        if activeOrder and (#activeOrder > 0 or total == 0) then
            local visibleRefs = {}
            for _, ref in ipairs(activeOrder) do
                local customItem = byRef[ref] or byRef[tostring(ref)]
                visibleRefs[customItem and customItem.ref or tostring(ref)] = true
            end
            for _, item in ipairs(combined) do
                local customItem = byRef[item.ref] or byRef[tostring(item.ref)]
                local key = customItem and customItem.ref or tostring(item.ref)
                if not visibleRefs[key] then
                    overflowItems[#overflowItems + 1] = item
                end
            end
            sourceName = "ZMPERK active"
        else
            for index = STOCK_HUD_NATIVE_PERK_LIMIT + 1, #combined do
                overflowItems[#overflowItems + 1] = combined[index]
            end
            sourceName = "ZMPERK catalog"
        end
    else
        local list = overflowPerkList()
        if list then
            local okCount, count = pcall(function() return list:GetCountValue(0) end)
            if okCount and tonumber(count) then
                total = math.max(0, math.floor(tonumber(count)))
                for index = STOCK_HUD_NATIVE_PERK_LIMIT, total do
                    local okItem, item = pcall(function() return list:GetDataSourceAtIndex(index - 1, 0) end)
                    if okItem and item ~= nil then overflowItems[#overflowItems + 1] = item end
                end
                sourceName = "HUD"
            end
        end
        if total == nil then
            if not S.stockHudListMissingLogged then
                S.stockHudListMissingLogged = true
                log("Stock HUD overflow: perk data source and owned perk catalog unavailable")
            end
            hideOverflowPerkIcons()
            return
        end
    end
    local serverOverflowRefs = stockHudOverflowPerkRefs()
    if serverOverflowRefs then
        overflowItems = {}
        total = STOCK_HUD_NATIVE_PERK_LIMIT + #serverOverflowRefs
        for _, ref in ipairs(serverOverflowRefs) do
            overflowItems[#overflowItems + 1] = stockHudPerkItemByRef(ref)
        end
        sourceName = "GSC overflow"
    end
    local extra = #overflowItems

    local status = sourceName .. " total=" .. tostring(total) .. " extra=" .. tostring(extra)
    if S.stockHudOverflowStatus ~= status then
        S.stockHudOverflowStatus = status
        log("Stock HUD overflow: perk count/extra=" .. status)
    end
    local rows = buildOverflowRows(overflowItems)
    if not renderStockHudPerkIcons(root, rows, total) then hideOverflowPerkIcons() end
end

local BANDOLIER_REF = "specialty_bandolier"
local BANDOLIER_REF_HASH = hk(BANDOLIER_REF)
local BANDOLIER_AUGMENTS = {
    major = {
        { name = "Stowed Reload", description = "Weapons you are not holding slowly refill their magazines from reserve ammo." },
        { name = "Deep Pockets", description = "Increases the extra reserve ammo from 50% to 100%." },
    },
    minor = {
        { name = "Restock", description = "At the end of every round, your weapons are refilled to the extended maximum." },
        { name = "Magazine Mule", description = "Killing a zombie has a 5% chance to refill the magazine of your held weapon." },
    },
}
local bandolierSelection = rawget(_G, "BO7BandolierAugmentSelection")
if type(bandolierSelection) ~= "table" then
    bandolierSelection = { major = 0, minor = 0, pending = { major = false, minor = false } }
    rawset(_G, "BO7BandolierAugmentSelection", bandolierSelection)
elseif type(bandolierSelection.pending) ~= "table" then
    bandolierSelection.pending = { major = false, minor = false }
end

local TORTOISE_REF = "specialty_tortoise"
local TORTOISE_REF_HASH = hk(TORTOISE_REF)
local TORTOISE_AUGMENTS = {
    major = {
        { name = "Thorns", description = "50% of the damage a zombie does to you is reflected back to the zombie." },
        { name = "Reinforced Shell", description = "Take an additional 10% less damage while wearing armor." },
    },
    minor = {
        { name = "Reserve Plate", description = "Hold an extra armor plate in reserve." },
        { name = "Crusader's Ale", description = "Your armor is fully repaired between rounds." },
    },
}
local tortoiseSelection = rawget(_G, "BO7TortoiseAugmentSelection")
if type(tortoiseSelection) ~= "table" then
    tortoiseSelection = { major = 0, minor = 0, pending = { major = false, minor = false } }
    rawset(_G, "BO7TortoiseAugmentSelection", tortoiseSelection)
elseif type(tortoiseSelection.pending) ~= "table" then
    tortoiseSelection.pending = { major = false, minor = false }
end

local GAUTYS_GOLD_REF = "specialty_gautys_gold"
local GAUTYS_GOLD_REF_HASH = hk(GAUTYS_GOLD_REF)
local GAUTYS_GOLD_AUGMENTS = {
    major = {
        { name = "Golden Payout", description = "Increases points from 1.25x to 1.35x while the perk is active." },
        { name = "15x Points", description = "Multiplies points by 1.5 while Gauty's Gold is active (debug augment)." },
        { name = "Golden Refund", description = "Purchases have a 25% chance to refund their full cost." },
    },
    minor = {
        { name = "Golden Strike", description = "Awards double points for melee kills." },
    },
}
local gautys_goldSelection = rawget(_G, "BO7GautysGoldAugmentSelection")
if type(gautys_goldSelection) ~= "table" then
    gautys_goldSelection = { major = 0, minor = 0, pending = { major = false, minor = false } }
    rawset(_G, "BO7GautysGoldAugmentSelection", gautys_goldSelection)
elseif type(gautys_goldSelection.pending) ~= "table" then
    gautys_goldSelection.pending = { major = false, minor = false }
end

local ELECTRIC_CHERRY_REF = "specialty_electric_cherry"
local ELECTRIC_CHERRY_REF_HASH = hk(ELECTRIC_CHERRY_REF)
local ELECTRIC_CHERRY_AUGMENTS = {
    major = {
        { name = "Chain Lightning", description = "The reload shock can chain between zombies." },
        { name = "Static Salvage", description = "Zombies killed by the electric shock have a chance to give you an armor plate." },
    },
    minor = {
        { name = "Quick Charge", description = "Cooldown time reduced by 50%." },
        { name = "Muscle Milk", description = "Melee hits on zombies also set off the electric shock (same cooldown)." },
        { name = "High Voltage", description = "The electric shock deals 5% more damage." },
    },
}
local electric_cherrySelection = rawget(_G, "BO7ElectricCherryAugmentSelection")
if type(electric_cherrySelection) ~= "table" then
    electric_cherrySelection = { major = 0, minor = 0, pending = { major = false, minor = false } }
    rawset(_G, "BO7ElectricCherryAugmentSelection", electric_cherrySelection)
elseif type(electric_cherrySelection.pending) ~= "table" then
    electric_cherrySelection.pending = { major = false, minor = false }
end

local AUGMENT_MINOR_OFFSET = 5
local JUG2_REF = "specialty_jug2"
local JUG2_REF_HASH = hk(JUG2_REF)
local JUG2_AUGMENTS = {
    major = {
        { name = "Moon Hop", description = "Jumping reduces your gravity by 50% for 5 seconds." },
    },
    minor = {
    },
}
local jug2Selection = rawget(_G, "BO7Jug2AugmentSelection")
if type(jug2Selection) ~= "table" then
    jug2Selection = { major = 0, minor = 0, pending = { major = false, minor = false } }
    rawset(_G, "BO7Jug2AugmentSelection", jug2Selection)
elseif type(jug2Selection.pending) ~= "table" then
    jug2Selection.pending = { major = false, minor = false }
end

local AUG_PERKS = {
    { key = "bandolier", label = "Bandolier Bandit", ref = BANDOLIER_REF, refHash = BANDOLIER_REF_HASH, augments = BANDOLIER_AUGMENTS,
      selection = bandolierSelection, pickDvar = "bo7_cp_bandolier_pick", syncBase = 8000, ackDvar = "bo7_cp_bandolier_pick_ack", lootBase = 2147483020 },
    { key = "tortoise", label = "Victorious Tortoise", ref = TORTOISE_REF, refHash = TORTOISE_REF_HASH, augments = TORTOISE_AUGMENTS,
      selection = tortoiseSelection, pickDvar = "bo7_cp_tortoise_pick", syncBase = 7000, ackDvar = "bo7_cp_tortoise_pick_ack", lootBase = 2147483030 },
    { key = "gautys_gold", label = "Gauty's Gold", ref = GAUTYS_GOLD_REF, refHash = GAUTYS_GOLD_REF_HASH, augments = GAUTYS_GOLD_AUGMENTS,
      selection = gautys_goldSelection, pickDvar = "bo7_cp_gautys_gold_pick", syncBase = 4000, ackDvar = "bo7_cp_gold_pick_ack", lootBase = 2147483040 },
    { key = "electric_cherry", label = "Electric Cherry", ref = ELECTRIC_CHERRY_REF, refHash = ELECTRIC_CHERRY_REF_HASH, augments = ELECTRIC_CHERRY_AUGMENTS,
      selection = electric_cherrySelection, pickDvar = "bo7_cp_electric_cherry_pick", syncBase = 6000, ackDvar = "bo7_cp_electric_cherry_pick_ack", lootBase = 2147483050 },
    
    { key = "jug2", label = "Roo Brew", ref = JUG2_REF, refHash = JUG2_REF_HASH, augments = JUG2_AUGMENTS,
      selection = jug2Selection, pickDvar = "bo7_cp_jug2_pick", syncBase = 10000, ackDvar = "bo7_cp_jug2_pick_ack", minorLootOffset = 10, lootBase = 2147481020 },
}

local function augPerkFor(ref)
    if ref == nil then return nil end
    for _, p in ipairs(AUG_PERKS) do
        if ref == p.ref or (p.refHash ~= nil and (ref == p.refHash or tostring(ref) == tostring(p.refHash))) then
            return p
        end
    end
    return nil
end

local function tryWriteAugmentDvar(name, value)
    local dvar = rawget(_G, "Dvar")
    local setter = g(dvar, "SetDvarString")
    local hashDvar = rawget(_G, "xhashdvar") or rawget(_G, "PushXHashDvar")
    local clua = rawget(_G, "CLUA")
    if type(hashDvar) ~= "function" and type(clua) == "table" then
        hashDvar = g(clua, "PushXHashDvar")
    end
    local expected = tostring(value)
    local engine = rawget(_G, "Engine")
    local execNow = g(engine, "ExecNow")
    local ok, result = false, "setter unavailable"
    if type(setter) == "function" and type(hashDvar) == "function" then
        local okHash, dvarHash = pcall(hashDvar, name)
        if okHash then
            ok, result = pcall(setter, dvarHash, expected)
            local actual = readDebugDvar(name)
            if ok and actual == expected then return true end
        else
            result = "Dvar hash failed"
        end
    end

    if type(execNow) == "function" then
        local commandOk, commandError = pcall(execNow, "set " .. name .. " " .. expected .. "\n", 0)
        if not commandOk then
            log("Vitality Dvar set fallback failed for " .. name .. ": " .. tostring(commandError))
        end
        if readDebugDvar(name) == expected then return true end
    end

    if not vitalitySelection.failureLogged[name] then
        vitalitySelection.failureLogged[name] = true
        log("Vitality augment selection not saved for " .. name ..
            " (setter=" .. tostring(ok) .. "/" .. tostring(result) ..
            ", readback=" .. tostring(readDebugDvar(name)) .. ")")
    end
    return false
end

local PICK_DVAR = "bo7_cp_vitality_pick"

local function dvarTokenCandidates(name)
    local hashDvar = rawget(_G, "xhashdvar") or rawget(_G, "PushXHashDvar")
    local clua = rawget(_G, "CLUA")
    if type(hashDvar) ~= "function" and type(clua) == "table" then hashDvar = g(clua, "PushXHashDvar") end
    if type(hashDvar) ~= "function" then return {} end
    local ok, h = pcall(hashDvar, name)
    if not ok or h == nil then return {} end
    local list = {}
    local function add(t) if t and t ~= "" then list[#list + 1] = t end end

    local okT, text = pcall(tostring, h)
    if okT and type(text) == "string" then add(text:match("#x%x+")) end
    if type(h) == "string" then
        if h:sub(1, 2) == "#x" then add(h) else add("#x3" .. h); add("#x" .. h); add(h) end
    else
        local okF, hex = pcall(string.format, "%x", h)
        if not okF and math.tointeger then
            local okI, i = pcall(math.tointeger, h)
            if okI and i then okF, hex = pcall(string.format, "%x", i) end
        end
        if okF and hex then add("#x3" .. hex); add("#x" .. hex) end
        if okT then add(text) end
    end
    return list
end

local function persistDvar(name, value)
    local engine = rawget(_G, "Engine")
    local execNow = g(engine, "ExecNow")
    if type(execNow) ~= "function" then
        if not S.errPersist then S.errPersist = true; log("Engine.ExecNow unavailable; cannot persist " .. name) end
        return false
    end
    local expected = tostring(value)
    local list = dvarTokenCandidates(name)
    if S.goodTokenIndex and list[S.goodTokenIndex] then
        table.insert(list, 1, list[S.goodTokenIndex])
    end
    for i, token in ipairs(list) do
        pcall(execNow, "set " .. token .. " " .. expected .. "\n", 0)
        if readDebugDvar(name) == expected then
            if not S.goodToken then
                S.goodToken = true
                log("persisted " .. name .. "=" .. expected .. " using console token form '" .. token:gsub("%x%x%x%x%x%x%x%x+$", "<hash>") .. "'")
            end
            return true
        end
    end
    if not S.errPersistFail then
        S.errPersistFail = true
        local tried = {}
        for _, t in ipairs(list) do tried[#tried + 1] = t end
        log("could not persist " .. name .. "=" .. expected .. "; tried " .. table.concat(tried, " | ") ..
            "; readback=" .. tostring(readDebugDvar(name)))
    end
    return false
end

local function persistSelection(perk)
    perk = perk or AUG_PERKS[1]
    if not perk then return false end
    local major = math.max(0, math.min(#perk.augments.major, tonumber(perk.selection.major) or 0))
    local minor = math.max(0, math.min(#perk.augments.minor, tonumber(perk.selection.minor) or 0))
    local bonus = math.max(0, math.min(#perk.augments.minor, tonumber(perk.selection.bonus) or 0))
    if bonus == minor then bonus = 0 end

    return persistDvar(perk.pickDvar, bonus * 100 + major * 10 + minor)
end

local function loadOnePersisted(perk)
    if S.pickLoaded[perk.key] then return true end
    local raw = readDebugDvar(perk.pickDvar)
    if raw == nil then
        S.pickLoadTries[perk.key] = (S.pickLoadTries[perk.key] or 0) + 1
        return false
    end
    S.pickLoaded[perk.key] = true
    log("saved " .. perk.label .. " dvar read: '" .. tostring(raw) .. "'")
    local n = tonumber(raw)
    if n and n >= 0 and n <= 999 then
        n = math.floor(n)
        local low = n % 100
        perk.selection.major = math.floor(low / 10)
        perk.selection.minor = low % 10
        perk.selection.bonus = math.floor(n / 100)
        log("loaded saved " .. perk.label .. " augments: major=" .. perk.selection.major .. " minor=" .. perk.selection.minor .. " bonus=" .. perk.selection.bonus)
    end
    return true
end

local function loadPersistedSelection()
    for _, perk in ipairs(AUG_PERKS) do
        loadOnePersisted(perk)
    end
end

local function writeAugmentDvar(perk, slot, value)
    if not perk then return false end

    loadOnePersisted(perk)
    perk.selection[slot] = value
    perk.selection.pending[slot] = true
    S.pickLoaded[perk.key] = true
    persistSelection(perk)
    return true
end
local function flushVitalityAugments()
    if readDebugDvar("bo7_cp_debug_state") == nil then return end
    for _, slot in ipairs({ "major", "minor" }) do
        local name = "bo7_cp_vitality_" .. slot
        local selected = tonumber(vitalitySelection[slot]) or 0
        if vitalitySelection.pending[slot] or tonumber(readDebugDvar(name)) ~= selected then
            if tryWriteAugmentDvar(name, selected) then
                vitalitySelection.pending[slot] = false
                vitalitySelection.failureLogged[name] = nil
                log("Vitality " .. slot .. " augment applied to the in-game Dvar")
            end
        end
    end
end

local function hookAugmentFunction(object, name, tag, handler)
    if type(object) ~= "table" then return false end
    local keys = allFnKeys(object, name)
    if #keys == 0 then return false end
    local state = S.hooks[tag]
    if not state then
        state = { original = keys[1].fn }
        state.wrapper = function(...)
            return handler(state.original, ...)
        end
        S.hooks[tag] = state
    else
        local allInstalled = true
        for _, entry in ipairs(keys) do
            if entry.fn ~= state.wrapper then allInstalled = false end
        end
        if allInstalled then return true end
    end
    for _, entry in ipairs(keys) do object[entry.key] = state.wrapper end
    return true
end

local function installAugmentHooks()
    local perks = rawget(_G, "PERK")
    if type(perks) == "table" then
        hookAugmentFunction(perks, "getallperks", "augmentPerkList", function(original, ...)
            local list = original(...)
            if type(list) ~= "table" then return list end
            for _, item in ipairs(list) do
                if isVitalityRef(g(item, "ref")) then return list end
            end
            list[#list + 1] = { ref = VITALITY_REF_HASH or VITALITY_REF }
            return list
        end)
    end

    local augment = rawget(_G, "ZMAUGMENT")
    if type(augment) ~= "table" then return false end
    local loot = rawget(_G, "LOOT")
    hookAugmentFunction(augment, "createfullaugmentcache", "augmentFullCache", function(original, controller, equipmentList, equipmentType, ...)
        if equipmentType ~= g(g(augment, "equipment_type"), "perk") or type(equipmentList) ~= "table" then
            return original(controller, equipmentList, equipmentType, ...)
        end
        local filtered = {}
        for _, entry in ipairs(equipmentList) do
            local ref = g(entry, "ref")
            if not isVitalityRef(ref) then
                filtered[#filtered + 1] = entry
            end
        end
        return original(controller, filtered, equipmentType, ...)
    end)
    hookAugmentFunction(loot, "isunlockedwithid", "augmentUnlocked", function(original, controller, lootId, ...)
        if S.vitalityLootOptions[tonumber(lootId)] then return true end
        return original(controller, lootId, ...)
    end)
    hookAugmentFunction(augment, "initfullaugmentlist", "augmentFullList", function(original, ...)
        local result = original(...)
        local ok, err = pcall(ensureVitalityAugments)
        if not ok then log("Vitality augment cache error: " .. tostring(err)) end
        return result
    end)
    hookAugmentFunction(augment, "inittypeaugmentlist", "augmentTypeList", function(original, controller, equipmentType, ...)
        local result = original(controller, equipmentType, ...)
        local perkType = g(g(augment, "equipment_type"), "perk")
        if equipmentType == perkType then
            local ok, err = pcall(ensureVitalityAugments)
            if not ok then log("Vitality augment list error: " .. tostring(err)) end
        end
        return result
    end)
    hookAugmentFunction(augment, "refreshaugmentlistdata", "augmentRefreshList", function(original, controller, ref, ...)
        local result = original(controller, ref, ...)
        if not isVitalityRef(ref) then return result end
        local ok, err = pcall(function()
            if not ensureVitalityAugments() then return end
            local dataSources = rawget(_G, "_DataSources")
            local zm = g(dataSources, "zm")
            local frontend = g(zm, "frontend")
            local select = g(frontend, "augment_select")
            local function updateRows(listName, definitions, rows)
                local list = g(select, listName)
                if type(list) ~= "table" then return end
                for index, definition in ipairs(definitions) do
                    local entry = list[index]
                    local item = g(entry, "item")
                    if type(item) == "table" then
                        for field, value in pairs({
                            name = definition.name,
                            description = definition.description,
                            is_unlocked = true,
                            loot_id = g(rows[index], "lootid"),
                        }) do
                            local setter = g(g(item, field), "SetValue")
                            if type(setter) == "function" then
                                local success, message = pcall(setter, g(item, field), controller, value)
                                if not success then error(message) end
                            end
                        end
                    end
                end
            end
            local major = g(g(augment, "augmentlist_major"), VITALITY_REF)
            local minor = g(g(augment, "augmentlist_minor"), VITALITY_REF)
            updateRows("major_augment_list", VITALITY_AUGMENTS.major, major)
            updateRows("minor_augment_list", VITALITY_AUGMENTS.minor, minor)
        end)
        if not ok then log("Vitality augment UI refresh error: " .. tostring(err)) end
        return result
    end)
    hookAugmentFunction(augment, "getequippedaugmentbyref", "augmentEquippedRead", function(original, controller, ref, slot, equipmentType, ...)
        if isVitalityRef(ref) and equipmentType == g(g(augment, "equipment_type"), "perk") then
            local selectionSlot = slot == g(g(augment, "slot"), "major") and "major" or "minor"
            local selected = tonumber(vitalitySelection[selectionSlot]) or 0
            return math.max(0, math.min(#VITALITY_AUGMENTS[selectionSlot], selected))
        end
        return original(controller, ref, slot, equipmentType, ...)
    end)
    hookAugmentFunction(augment, "modifyselectedaugment", "augmentEquippedWrite", function(original, controller, selected, lootId, ref, equipmentType, ...)
        if not isVitalityRef(ref) or equipmentType ~= g(g(augment, "equipment_type"), "perk") then
            return original(controller, selected, lootId, ref, equipmentType, ...)
        end
        local option = S.vitalityLootOptions[tonumber(lootId)]
        if not option then
            log("Vitality augment selection ignored: no custom option for loot ID " .. tostring(lootId))
            return
        end
        local dvarName = "bo7_cp_vitality_" .. option.slot
        local current = tonumber(vitalitySelection[option.slot]) or 0
        local value = current == option.index and 0 or option.index
        if not writeAugmentDvar(dvarName, option.slot, value) then return end
        local slot = option.slot == "major" and g(g(augment, "slot"), "major") or g(g(augment, "slot"), "minor")
        local refresh = g(augment, "refreshequippedaugmentdata")
        if type(refresh) == "function" then
            local ok, err = pcall(refresh, controller, slot, value)
            if not ok then log("Vitality equipped augment refresh error: " .. tostring(err)) end
        end
        log("Vitality " .. option.slot .. " augment selection set to " .. tostring(value))
    end)

    local perkList = g(rawget(_G, "ZMPERK"), "zmperklist")
    if type(perkList) == "table" then
        local found = false
        for _, entry in ipairs(perkList) do
            if isVitalityRef(g(entry, "ref")) then found = true; break end
        end
        if not found then
            local perk = rawget(_G, "PERK")
            local getBundle = perk and (g(perk, "GetBundleByRef"))
            if type(getBundle) == "function" then
                local bundle = getBundle(VITALITY_REF_HASH or VITALITY_REF)
                if bundle then
                    perkList[#perkList + 1] = { data = bundle, ref = VITALITY_REF_HASH or VITALITY_REF }
                    log("Vitality added to cached Zombies perk list")
                end
            end
        end
    end
    local requiredHooks = {
        "augmentPerkList", "augmentFullCache", "augmentUnlocked", "augmentFullList",
        "augmentTypeList", "augmentRefreshList", "augmentEquippedRead", "augmentEquippedWrite",
    }
    local allInstalled = true
    for _, tag in ipairs(requiredHooks) do
        if not S.hooks[tag] then allInstalled = false; break end
    end
    if allInstalled and not S.loggedAugmentHooks then
        S.loggedAugmentHooks = true
        log("Vitality Dvar-backed augment hooks installed")
    end
    return true
end

local function installVitalityPerkList()
    local perks = rawget(_G, "ZMPERK")
    if type(perks) ~= "table" then return false end
    return hookAugmentFunction(perks, "getperklist", "vitalityPerkList", function(original, ...)
        local list = original(...)
        if type(list) ~= "table" then
            if not S.loggedPerkListFailure then
                S.loggedPerkListFailure = true
                log("augment perk entries not added: ZMPERK.getperklist returned " .. type(list))
            end
            return list
        end

        for _, perk in ipairs(AUG_PERKS) do
            local present = false
            for _, entry in ipairs(list) do
                if augPerkFor(g(entry, "ref")) == perk then present = true; break end
            end
            if not present then
                local lib = rawget(_G, "PERK")
                local getBundle = lib and g(lib, "GetBundleByRef")
                local ref = perk.refHash or perk.ref
                local ok, bundle = false, nil
                if type(getBundle) == "function" then ok, bundle = pcall(getBundle, ref) end
                if ok and type(bundle) == "table" and g(bundle, "zombiesperk") and g(bundle, "showninmenu") then
                    local entry = {}
                    s(entry, "data", bundle)
                    s(entry, "ref", ref)
                    list[#list + 1] = entry
                    if not S["loggedPerkList_" .. perk.key] then
                        S["loggedPerkList_" .. perk.key] = true
                        log(perk.label .. " added to augment perk list; custom augments will be built from Juggernog visuals")
                    end
                elseif not S["loggedPerkListFail_" .. perk.key] then
                    S["loggedPerkListFail_" .. perk.key] = true
                    log(perk.label .. " augment entry not added: perk bundle unavailable or not marked for Zombies/menu")
                end
            end
        end
        return list
    end)
end

local function makeAugmentRows(perk)
    if not perk then return false end
    local augment = rawget(_G, "ZMAUGMENT")
    if type(augment) ~= "table" then return false end
    local full = g(augment, "augmentlist_full")
    local juggernog = g(full, "specialty_juggernog")
    if type(full) ~= "table" or type(juggernog) ~= "table" then return false end

    local majorType = g(g(augment, "type"), "major")
    local minorType = g(g(augment, "type"), "minor")
    local sources = { major = {}, minor = {} }
    for _, row in ipairs(juggernog) do
        local rowType = g(row, "type")
        local slot = rowType == majorType and "major" or (rowType == minorType and "minor" or nil)
        if slot then
            sources[slot][#sources[slot] + 1] = row
        end
    end
    if #sources.major < 1 or #sources.minor < 1 then
        if not S.loggedAugmentSourceFailure then
            S.loggedAugmentSourceFailure = true
            log("augment setup failed: Juggernog cache lacks a major or a minor row")
        end
        return false
    end

    local rowsBySlot = { major = {}, minor = {} }
    for _, slot in ipairs({ "major", "minor" }) do
        for index, definition in ipairs(perk.augments[slot]) do
            local row = {}

            local source = sources[slot][((index - 1) % #sources[slot]) + 1]
            for key, value in pairs(source) do row[key] = value end
            local lootId = perk.lootBase + (slot == "major" and index or index + (perk.minorLootOffset or AUGMENT_MINOR_OFFSET))
            s(row, "displayname", definition.name)
            s(row, "description", definition.description)
            s(row, "lootid", lootId)
            s(row, "IsUnlocked", true)
            s(row, "isUnlocked", true)
            s(row, "isResearchComplete", false)
            s(row, "amountNeededToUnlock", 0)
            s(row, "hideinequipui", false)
            s(row, "equipmenttype", g(g(augment, "equipment_type"), "perk"))
            rowsBySlot[slot][index] = row
            S.augmentLootOptions[lootId] = { perk = perk, slot = slot, index = index }
        end
    end

    local combined = {}
    for _, slot in ipairs({ "major", "minor" }) do
        for _, row in ipairs(rowsBySlot[slot]) do combined[#combined + 1] = row end
    end
    combined.isSorted = true

    combined.isResearchComplete = true
    combined.totalProgress = 0
    s(full, perk.ref, combined)
    local logKey = "loggedAugmentRows_" .. perk.key
    if not S[logKey] then
        S[logKey] = true
        log(perk.label .. " custom augment rows cached: " .. #perk.augments.major .. " major, " .. #perk.augments.minor .. " minor")
    end
    return rowsBySlot
end

local function installVitalityAugmentHooks()
    local augment = rawget(_G, "ZMAUGMENT")
    if type(augment) ~= "table" then return false end
    local perks = rawget(_G, "ZMPERK")
    if type(perks) ~= "table" then return false end
    local loot = rawget(_G, "LOOT")
    local perkEquipment = g(g(augment, "equipment_type"), "perk")
    local slotIds = g(augment, "slot") or {}

    hookAugmentFunction(augment, "initfullaugmentlist", "vitalityFullAugmentRows", function(original, ...)
        local result = original(...)
        for _, perk in ipairs(AUG_PERKS) do
            local ok, rowsOrError = pcall(makeAugmentRows, perk)
            if not ok then
                log(perk.label .. " augment cache error: " .. tostring(rowsOrError))
            elseif not rowsOrError then
                log(perk.label .. " augment cache unavailable; Juggernog rows were not replaced")
            end
        end
        return result
    end)

    hookAugmentFunction(augment, "inittypeaugmentlist", "vitalityTypedAugmentRows", function(original, controller, equipmentType, ...)
        local result = original(controller, equipmentType, ...)
        if equipmentType ~= perkEquipment then return result end
        local majorLists = g(augment, "augmentlist_major")
        local minorLists = g(augment, "augmentlist_minor")
        for _, perk in ipairs(AUG_PERKS) do
            local ok, rowsOrError = pcall(makeAugmentRows, perk)
            if not ok then
                log(perk.label .. " typed augment list error: " .. tostring(rowsOrError))
            elseif rowsOrError then
                if type(majorLists) == "table" then s(majorLists, perk.ref, rowsOrError.major) end
                if type(minorLists) == "table" then s(minorLists, perk.ref, rowsOrError.minor) end
            end
        end
        return result
    end)

    hookAugmentFunction(augment, "refreshaugmentlistdata", "customAugmentListRefresh", function(original, controller, ref, ...)
        local result = original(controller, ref, ...)
        local perk = augPerkFor(ref)
        if not perk then return result end
        local ok, err = pcall(function()
            local rows = makeAugmentRows(perk)
            if not rows then return end
            local select = g(g(g(rawget(_G, "_DataSources"), "zm"), "frontend"), "augment_select")
            local function setValue(field, value)
                local setter = g(field, "SetValue")
                if type(setter) == "function" then pcall(setter, field, controller, value) end
            end
            local function fill(listName, source)
                local list = g(select, listName)
                if list == nil then return end
                for i = 1, #source do
                    local item = g(list[i], "item")
                    local row = source[i]
                    if item ~= nil then
                        setValue(g(item, "name"), g(row, "displayname"))
                        setValue(g(item, "description"), g(row, "description"))
                        setValue(g(item, "icon"), g(row, "icon"))
                        setValue(g(item, "type"), g(row, "type"))
                        setValue(g(item, "is_unlocked"), true)
                        setValue(g(item, "loot_id"), g(row, "lootid"))
                    end
                end

                for i = #source + 1, math.max(#list, #source + 12) do
                    rawset(list, i, nil)
                end
                setValue(g(list, "count"), #source)
            end
            fill("major_augment_list", rows.major)
            fill("minor_augment_list", rows.minor)
        end)
        if not ok and not S.loggedRefreshErr then
            S.loggedRefreshErr = true
            log(perk.label .. " augment list refresh error: " .. tostring(err))
        end
        return result
    end)

    hookAugmentFunction(loot, "isunlockedwithid", "vitalityAugmentUnlock", function(original, controller, lootId, ...)
        local option = S.augmentLootOptions[tonumber(lootId)]
        if option then return true end
        return original(controller, lootId, ...)
    end)

    hookAugmentFunction(augment, "getequippedaugmentbyref", "vitalityAugmentRead", function(original, controller, ref, slot, equipmentType, ...)
        local perk = augPerkFor(ref)
        if not perk or equipmentType ~= perkEquipment then
            return original(controller, ref, slot, equipmentType, ...)
        end
        if slot == g(slotIds, "major") then
            return math.max(0, math.min(#perk.augments.major, tonumber(perk.selection.major) or 0))
        elseif slot == g(slotIds, "minor") then
            return math.max(0, math.min(#perk.augments.minor, tonumber(perk.selection.minor) or 0))
        elseif slot == g(slotIds, "bonus_minor") then
            return math.max(0, math.min(#perk.augments.minor, tonumber(perk.selection.bonus) or 0))
        end
        return 0
    end)

    hookAugmentFunction(augment, "modifyselectedaugment", "vitalityAugmentWrite", function(original, controller, selected, lootId, ref, equipmentType, ...)
        local perk = augPerkFor(ref)
        if not perk or equipmentType ~= perkEquipment then
            return original(controller, selected, lootId, ref, equipmentType, ...)
        end
        local option = S.augmentLootOptions[tonumber(lootId)]
        if not option or option.perk ~= perk then
            log(perk.label .. " selection ignored an unknown augment loot ID: " .. tostring(lootId))
            return
        end
        local refresh = g(augment, "refreshequippedaugmentdata")
        local function refreshSlot(slotId, value)
            if type(refresh) ~= "function" then return end
            local ok, err = pcall(refresh, controller, slotId, value)
            if not ok then log(perk.label .. " equipped-row refresh failed: " .. tostring(err)) end
        end
        if option.slot == "major" then
            local current = tonumber(perk.selection.major) or 0
            local selectedIndex = current == option.index and 0 or option.index
            if not writeAugmentDvar(perk, "major", selectedIndex) then return end
            refreshSlot(g(slotIds, "major"), selectedIndex)
            log(perk.label .. " major selection set to " .. tostring(selectedIndex))
            return
        end

        local minor = tonumber(perk.selection.minor) or 0
        local bonus = tonumber(perk.selection.bonus) or 0
        local index = option.index
        if index == minor then
            minor, bonus = bonus, 0
        elseif index == bonus then
            bonus = 0
        elseif minor == 0 then
            minor = index
        else
            bonus = index
        end
        loadOnePersisted(perk)
        perk.selection.minor = minor
        perk.selection.bonus = bonus
        perk.selection.pending.minor = true
        perk.selection.pending.bonus = true
        S.pickLoaded[perk.key] = true
        persistSelection(perk)
        refreshSlot(g(slotIds, "minor"), minor)
        refreshSlot(g(slotIds, "bonus_minor"), bonus)
        local item = g(g(g(g(rawget(_G, "_DataSources"), "zm"), "frontend"), "augment_list"), "focused_equipment_item")
        local okRead, readBack = pcall(function() return g(item, "equipped_augment_bonus_minor_index"):GetValue(controller) end)
        log(perk.label .. " minor selection set to " .. tostring(minor) .. " / " .. tostring(bonus) ..
            " (bonus slot id " .. tostring(g(slotIds, "bonus_minor")) .. ", panel bonus index " .. tostring(okRead and readBack or "unreadable") .. ")")
    end)

    local required = {
        "vitalityFullAugmentRows", "vitalityTypedAugmentRows",
        "vitalityAugmentUnlock", "vitalityAugmentRead", "vitalityAugmentWrite",
    }
    for _, name in ipairs(required) do
        if not S.hooks[name] then return false end
    end
    if not S.loggedVitalityAugmentHooks then
        S.loggedVitalityAugmentHooks = true
        log("custom augment display and Dvar selection hooks installed (" .. #AUG_PERKS .. " perks)")
    end
    return true
end

restorePrototypeAugmentHooks()

local function diag(label, tbl, want)
    if type(tbl) ~= "table" then log("diag " .. label .. ": not a table (" .. type(tbl) .. ")"); return end
    local n, fns, sample = 0, 0, {}
    for k, v in pairs(tbl) do
        n = n + 1
        if type(v) == "function" then
            fns = fns + 1
            if #sample < 6 then sample[#sample + 1] = tostring(k) end
        end
    end
    log("diag " .. label .. ": entries=" .. n .. " functions=" .. fns .. " plainKey=" .. type(tbl[want]) ..
        " hashedKey=" .. type(tbl[hk(want) or 0]) .. " sampleFnKeys=" .. table.concat(sample, ","))
end

local packFn = table.pack or function(...) return { n = select("#", ...), ... } end
local unpackFn = table.unpack or unpack
local function describeArgs(...)
    local parts = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        local t = type(v)
        if t == "table" then
            local ref = g(v, "ref")
            local items = g(v, "items")
            if ref ~= nil or type(items) == "table" then
                local vis = g(v, "visibleitems")
                parts[#parts + 1] = "tab(ref=" .. tostring(ref) .. " items=" .. (type(items) == "table" and #items or -1) ..
                    " supportsvis=" .. tostring(g(v, "supportsitemvisibility")) ..
                    " visible=" .. (type(vis) == "table" and #vis or -1) .. ")"
            else
                parts[#parts + 1] = "table"
            end
        elseif t == "userdata" then
            parts[#parts + 1] = "widget"
        else
            parts[#parts + 1] = t .. ":" .. tostring(v)
        end
    end
    return table.concat(parts, ", ")
end

local function probeFn(object, name, tag, limit)
    if type(object) ~= "table" then return false end
    local keys = allFnKeys(object, name)
    if #keys == 0 then return false end
    local st = S.hooks[tag]
    if not st then
        st = { original = keys[1].fn, count = 0 }
        st.wrapper = function(...)
            local args = packFn(...)
            local res = packFn(st.original(...))
            st.count = st.count + 1
            if st.count <= (limit or 4) then
                pcall(function()
                    log("probe " .. name .. " #" .. st.count .. " args[" .. describeArgs(unpackFn(args, 1, args.n)) .. "] result[" ..
                        describeArgs(unpackFn(res, 1, res.n)) .. "]")
                end)
            end
            return unpackFn(res, 1, res.n)
        end
        S.hooks[tag] = st
    else
        local all = true
        for _, e in ipairs(keys) do if e.fn ~= st.wrapper then all = false end end
        if all then return true end
    end
    for _, e in ipairs(keys) do object[e.key] = st.wrapper end
    return true
end

local function traceAllFunctions(tbl, label)
    if type(tbl) ~= "table" then return end
    S.traced = S.traced or {}
    S.traced[label] = S.traced[label] or {}
    local done = S.traced[label]
    local snapshot = {}
    for k, v in pairs(tbl) do
        if type(v) == "function" then snapshot[#snapshot + 1] = { key = k, fn = v } end
    end
    for _, e in ipairs(snapshot) do
        local keyText = tostring(e.key)
        local st = done[keyText]
        if not st then
            st = { count = 0 }
            done[keyText] = st
            st.wrapper = function(...)
                local args = packFn(...)
                local res = packFn(e.fn(...))
                st.count = st.count + 1
                if st.count <= 20 then
                    pcall(function()
                        for i = 1, args.n do
                            local grid = args[i] and args[i].perkgridlayout
                            if grid then
                                log("trace gridstate via " .. label .. "." .. keyText .. ": rows=" .. tostring(grid:GetNumRows()) ..
                                    " cols=" .. tostring(grid:GetNumColumns()) .. " children=" .. tostring(grid:GetNumChildren()) ..
                                    " focusIndex=" .. tostring(grid:GetFocusPositionIndex()))
                            end
                        end
                    end)
                    pcall(function()
                        log("trace " .. label .. "." .. keyText .. " #" .. st.count .. " args[" ..
                            describeArgs(unpackFn(args, 1, args.n)) .. "] result[" .. describeArgs(unpackFn(res, 1, res.n)) .. "]")
                    end)
                end
                return unpackFn(res, 1, res.n)
            end
            tbl[e.key] = st.wrapper
        end
    end
end

local function isWheelEvent(e)
    return e.qualifier == "mousewheel" or e.key == "MWHEELUP" or e.key == "MWHEELDOWN"
end

local function isNavEvent(e)
    local b = e.button
    return b == "up" or b == "down" or b == "left" or b == "right"
end

local function configureWunderfizzKBM(menu, grid)
    menu.bo7_kbm = true
    pcall(function() grid:SetUseMouseWheelRawInput(true) end)

    local rule = menu.inputRule
    if type(rule) == "table" and type(rule.predicate) == "function" then
        local orig = rule.predicate
        rule.predicate = function(e, ...)
            if type(e) == "table" and e.name == "gamepad_button" and (isWheelEvent(e) or isNavEvent(e)) then
                return false
            end
            return orig(e, ...)
        end
    else
        log("Wunderfizz KBM: menu.inputRule.predicate missing")
    end

    pcall(function()
        menu:addEventHandler("gamepad_button", function(_, e)
            if type(e) ~= "table" or not e.down or not isWheelEvent(e) then return end
            local dir = e.button
            if e.key == "MWHEELUP" then dir = "up" elseif e.key == "MWHEELDOWN" then dir = "down" end
            if dir == "up" or dir == "down" then
                if not S.loggedWheelFallback then S.loggedWheelFallback = true; log("Wunderfizz wheel fallback scroll " .. dir) end
                grid:HandleMouseScroll(dir)
                return true
            end
        end)
    end)
    log("Wunderfizz KBM scroll configured (rows=" .. tostring(pcall(grid.GetNumRows, grid) and grid:GetNumRows()) ..
        " children=" .. tostring(pcall(grid.GetNumChildren, grid) and grid:GetNumChildren()) .. ")")
end

local function installKBMScrollSupport()
    local PMU = rawget(_G, "PurchaseMenuUtils")
    if type(PMU) ~= "table" then return false end
    S.kbmWrapped = S.kbmWrapped or {}
    local ours = {}
    for _, st in pairs(S.hooks) do
        if type(st) == "table" and st.wrapper then ours[st.wrapper] = true end
    end
    local snapshot = {}
    for k, v in pairs(PMU) do
        if type(v) == "function" and not ours[v] then snapshot[#snapshot + 1] = { key = k, fn = v } end
    end
    for _, e in ipairs(snapshot) do
        local known = S.kbmWrapped[e.key]
        if known ~= e.fn then
            local fn = e.fn
            local wrapper
            wrapper = function(...)
                local res = packFn(fn(...))
                for i = 1, select("#", ...) do
                    local a = select(i, ...)
                    if type(a) == "table" or type(a) == "userdata" then
                        local ok, grid = pcall(function() return a.perkgridlayout end)
                        if ok and grid and not a.bo7_kbm then
                            local okC, errC = pcall(configureWunderfizzKBM, a, grid)
                            if not okC then log("Wunderfizz KBM configure error: " .. tostring(errC)) end
                        end
                    end
                end
                return unpackFn(res, 1, res.n)
            end
            PMU[e.key] = wrapper
            S.kbmWrapped[e.key] = wrapper
        end
    end
    return true
end

local function installGridProbes()
    local PMU = rawget(_G, "PurchaseMenuUtils")
    traceAllFunctions(PMU, "PMU")
    traceAllFunctions(rawget(_G, "GRID_AND_LIST"), "GRID")
    traceAllFunctions(rawget(_G, "GRIDPAGEPIPS"), "PIPS")
    return true
end

local function syncLuaAugmentRows()
    if not ENABLE_AUGMENT_HOOKS or S.appliedLuaAugmentRows then return end

    local augment = rawget(_G, "ZMAUGMENT")
    if type(augment) ~= "table" then return end
    local full = g(augment, "augmentlist_full")
    local juggernog = g(full, "specialty_juggernog")
    if type(full) ~= "table" or type(juggernog) ~= "table" then return end

    local majorLists = g(augment, "augmentlist_major")
    local minorLists = g(augment, "augmentlist_minor")
    if type(majorLists) ~= "table" or type(minorLists) ~= "table" then return end
    local allReady = true
    for _, perk in ipairs(AUG_PERKS) do
        local ok, rows = pcall(makeAugmentRows, perk)
        if not ok then
            allReady = false
            log(perk.label .. " augment row reconciliation error: " .. tostring(rows))
        elseif rows then
            s(majorLists, perk.ref, rows.major)
            s(minorLists, perk.ref, rows.minor)
        else
            allReady = false
        end
    end
    if allReady then S.appliedLuaAugmentRows = true end
end

local function syncCoopAugmentPicks()
    local engine = rawget(_G, "Engine")
    local frontend = g(engine, "InFrontend")
    if type(frontend) ~= "function" then return end
    local okFront, inFrontend = pcall(frontend)
    if not okFront or inFrontend ~= false then
        S.augmentSync = {}
        S.hudSlotRegistration = nil
        S.augmentSyncCursor = 0
        S.augmentSyncDelay = 0
        S.augmentNextSendAt = nil
        return
    end
    local connected = g(engine, "IsConnectedToGameServer")
    if type(connected) == "function" then
        local okConnected, isConnected = pcall(connected)
        if not okConnected or not isConnected then return end
    end
    local notify = g(engine, "NotifyServer")
    if type(notify) ~= "function" then return end
    local clock = g(engine, "GetMilliseconds")
    if type(clock) ~= "function" then return end
    local clockOk, syncNow = pcall(clock)
    if not clockOk or type(syncNow) ~= "number" then return end
    if S.augmentNextSendAt and syncNow < S.augmentNextSendAt then return end
    if stockHudActivePerkOrder() == nil then
        if not S.augmentWaitingForGameplay then
            S.augmentWaitingForGameplay = true
            log("COOP AUGMENTS waiting for gameplay perk data; no attempts spent")
        end
        return
    end
    if S.augmentWaitingForGameplay then
        S.augmentWaitingForGameplay = false
        log("COOP AUGMENTS gameplay perk data ready; starting sync")
    end
    S.augmentSync = S.augmentSync or {}
    S.augmentSyncDelay = math.max(0, (S.augmentSyncDelay or 0) - 1)
    if S.augmentSyncDelay > 0 then return end
    local getClient = g(rawget(_G, "Game"), "getplayerclientnum")
    if type(getClient) == "function" then
        local okClient, slot = pcall(getClient, 0)
        slot = okClient and tonumber(slot) or nil
        if slot and slot >= 0 and slot <= 3 and slot == math.floor(slot) then
            local registration = S.hudSlotRegistration
            if not registration or registration.slot ~= slot then
                registration = { slot = slot, attempts = 0 }
                S.hudSlotRegistration = registration
            end
            local packet = readDebugDvar("bo7_cp_hud_slot_" .. tostring(slot))
            local prefix = "slot=" .. tostring(slot) .. ";v1:"
            local accepted = type(packet) == "string" and packet:sub(1, #prefix) == prefix
            local clock = g(engine, "GetMilliseconds")
            local clockOk, now = false, nil
            if type(clock) == "function" then clockOk, now = pcall(clock) end
            local canRetry = clockOk and type(now) == "number" and
                (not registration.nextSendAt or now >= registration.nextSendAt)
            if (registration.attempts == 0 or not accepted) and registration.attempts < 60 and canRetry then
                registration.attempts = registration.attempts + 1
                registration.nextSendAt = now + 2000
                S.augmentNextSendAt = syncNow + 500
                S.augmentSyncDelay = 12
                local ok, err = pcall(notify, "perk_choice_purchase", 9000 + slot)
                log("HUD slot registration slot=" .. tostring(slot) .. " attempt=" .. tostring(registration.attempts) .. " queued=" .. tostring(ok))
                if not ok then log("HUD slot registration error: " .. tostring(err)) end
                return
            end
        end
    end
    for offset = 1, #AUG_PERKS do
        local index = ((S.augmentSyncCursor or 0) + offset - 1) % #AUG_PERKS + 1
        local perk = AUG_PERKS[index]
        if perk.syncBase and loadOnePersisted(perk) then
            local state = S.augmentSync[perk.key] or {}
            S.augmentSync[perk.key] = state
            local major = math.floor(math.max(0, math.min(#perk.augments.major, tonumber(perk.selection.major) or 0)))
            local minor = math.floor(math.max(0, math.min(#perk.augments.minor, tonumber(perk.selection.minor) or 0)))
            local bonus = math.floor(math.max(0, math.min(#perk.augments.minor, tonumber(perk.selection.bonus) or 0)))
            if bonus == minor then bonus = 0 end
            local pick = bonus * 100 + major * 10 + minor
            local accepted = readDebugDvar(perk.ackDvar) == "accepted:" .. tostring(pick)
            if accepted and state.ackLogged ~= pick then
                state.ackLogged = pick
                log("COOP AUGMENTS " .. perk.key .. " acknowledged pick=" .. tostring(pick))
            end
            if state.pick ~= pick then
                state.pick = pick
                state.attempts = 0
                state.ackLogged = nil
                state.nextSendAt = nil
            end
            if ( (state.attempts or 0) == 0 or not accepted ) and (state.attempts or 0) < 30 and
                (not state.nextSendAt or syncNow >= state.nextSendAt) then
                state.attempts = (state.attempts or 0) + 1
                state.nextSendAt = syncNow + 2000
                S.augmentNextSendAt = syncNow + 500
                S.augmentSyncCursor = index
                S.augmentSyncDelay = 12
                local ok, err = pcall(notify, "perk_choice_purchase", perk.syncBase + pick)
                log("COOP AUGMENTS " .. perk.key .. " attempt=" .. tostring(state.attempts) .. " pick=" .. tostring(pick) .. " queued=" .. tostring(ok))
                if not ok then log("COOP AUGMENTS send failed: " .. tostring(err)) end
                return
            end
        end
    end
end

local function poll()
    local okCapture, errCapture = pcall(installNativePerkCapture)
    if not okCapture and not S.errNativeCapture then S.errNativeCapture = true; log("native perk capture error: " .. tostring(errCapture)) end
    S.polls = (S.polls or 0) + 1
    local okGold, errGold = pcall(syncCoopAugmentPicks)
    if not okGold and not S.goldSyncError then S.goldSyncError = true; log("COOP AUGMENTS sync error: " .. tostring(errGold)) end
    local okAugments, errAugments = pcall(syncLuaAugmentRows)
    if not okAugments and not S.errLuaAugmentRows then
        S.errLuaAugmentRows = true
        log("Lua-defined augment row sync error: " .. tostring(errAugments))
    end
    if ENABLE_AUGMENT_HOOKS then
        local okL, eL = pcall(loadPersistedSelection)
        if not okL and not S.errLoad then S.errLoad = true; log("load selection error: " .. tostring(eL)) end
        if S.polls % 50 == 0 then
            for _, perk in ipairs(AUG_PERKS) do
                local major = tonumber(perk.selection.major) or 0
                local minor = tonumber(perk.selection.minor) or 0
                if S.pickLoaded[perk.key] and (major > 0 or minor > 0) then
                    local bonus = tonumber(perk.selection.bonus) or 0
                    if bonus == minor then bonus = 0 end
                    local expected = tostring(bonus * 100 + major * 10 + minor)
                    if readDebugDvar(perk.pickDvar) ~= expected then pcall(persistSelection, perk) end
                end
            end
        end
    end
    for _, name in ipairs({ "bo7_cp_blaze_phase_stance_raw", "bo7_cp_blaze_phase_debug", "bo7_cp_blaze_phase_runtime", "bo7_cp_debug_state", "bo7_cp_augment_store_status", "bo7_cp_vitality_debug", "bo7_cp_cherry_runtime", "bo7_cp_gautys_gold_debug", "bo7_cp_gautys_gold_runtime", "bo7_cp_gold_transport", "bo7_cp_augments_transport", "bo7_cp_gold_event_debug", "bo7_cp_handler_build", "bo7_cp_hud_watch_debug", "bo7_cp_client_all_perks", "bo7_cp_registered_perks", "bo7_cp_perk_manifest_ready" }) do
        local value = readDebugDvar(name)
        if value and value ~= "" and S["last_" .. name] ~= value then
            S["last_" .. name] = value
            log(name .. "=" .. value)
        end
    end
    for _, c in ipairs(CUSTOM) do
        if isCustomPerkAvailable(c) then
            local owned = readDebugDvar("bo7_cp_client_owned_" .. c.ref:gsub("^specialty_", ""))
            local isOwned
            if owned == "1" or owned == "true" then
                isOwned = true
            elseif owned == "0" or owned == "false" then
                isOwned = false
            end
            if isOwned ~= nil and S.owned[c.ref] ~= isOwned then
                S.owned[c.ref] = isOwned
                log("owned state " .. c.ref .. "=" .. tostring(owned))
            end
        end
    end
    if S.polls == 40 then
        diag("PERK", rawget(_G, "PERK"), "GetBundleByRef")
        diag("PurchaseMenuUtils", rawget(_G, "PurchaseMenuUtils"), "setupmenutabinfo")
        if not S.hooks.engineNotify then
            log("Engine.NotifyServer unavailable; could not verify purchase notification")
        end
    end
    local ok1, e1 = pcall(installPerk)
    if not ok1 and not S.err1 then S.err1 = true; log("perk hook error: " .. tostring(e1)) end
    local ok2, e2 = pcall(installMenu)
    if not ok2 and not S.err2 then S.err2 = true; log("menu hook error: " .. tostring(e2)) end
    local ok3, e3 = pcall(installNotifyServer)
    if not ok3 and not S.err3 then S.err3 = true; log("NotifyServer hook error: " .. tostring(e3)) end
    local ok4, e4 = pcall(installOwnedPerkDisplay)
    if not ok4 and not S.errOwnedDisplay then S.errOwnedDisplay = true; log("owned perk display hook error: " .. tostring(e4)) end
    local ok5, e5 = pcall(installHudPerkIds)
    if not ok5 and not S.errHudPerkIds then S.errHudPerkIds = true; log("HUD perk ID hook error: " .. tostring(e5)) end
    local okOverflow, eOverflow = pcall(updateStockHudPerkOverflow)
    if not okOverflow and not S.errStockHudOverflow then
        S.errStockHudOverflow = true
        log("stock HUD perk overflow error: " .. tostring(eOverflow))
    end
    if ENABLE_GRID_PROBES then
        local okP, eP = pcall(installGridProbes)
        if not okP and not S.errProbes then S.errProbes = true; log("grid probe error: " .. tostring(eP)) end
    end
    if ENABLE_AUGMENT_HOOKS and ENABLE_WUNDERFIZZ_KBM_HOOKS then
        local okKBM, eKBM = pcall(installKBMScrollSupport)
        if not okKBM and not S.errKBM then S.errKBM = true; log("KBM scroll error: " .. tostring(eKBM)) end
    end
    if ENABLE_AUGMENT_HOOKS then
        local ok6, e6 = pcall(installVitalityPerkList)
        if not ok6 and not S.errVitalityPerkList then S.errVitalityPerkList = true; log("Vitality augment list hook error: " .. tostring(e6)) end
        local ok7, e7 = pcall(installVitalityAugmentHooks)
        if not ok7 and not S.errVitalityAugmentHooks then S.errVitalityAugmentHooks = true; log("Vitality custom augment hook error: " .. tostring(e7)) end
    elseif not S.loggedAugmentsOff then
        S.loggedAugmentsOff = true
        log("augment hooks DISABLED by ENABLE_AUGMENT_HOOKS = false")
    end
end

local frame = rawget(_G, "Frame")
local dw = frame and (g(frame, "DoWork") or frame.DoWork)
local qkey, qfn
if dw then qkey, qfn = findFn(dw, "Queue") end
if qfn then
    qfn(dw, function()
        if not S.enabled then return false end
        S.ticks = S.ticks + 1
        if S.ticks >= 5 then S.ticks = 0; poll() end
        return true
    end)
else
    log("Frame.DoWork unavailable; trying once")
end
if previous and (previous.version == 19 or previous.version == 20 or previous.version == 21) then
    log("restored previous Vitality perk-list hook before installing custom augment rows")
end
poll()
do
    local list = dvarTokenCandidates("lumen_mod_menu_request")
    log("token self-test (expect #x3e55f003787597bc4 as first/any entry): " .. table.concat(list, " | "))
end
log("post script loaded (version 128; raw native stance diagnostics)")
