local previous = rawget(_G, "BO7PerkToggles")
if previous then
    previous.enabled = false
    if previous.panel then pcall(function() previous.panel:closeTree() end) end
end
local S = { enabled = true, hooks = {}, reported = {} }
rawset(_G, "BO7PerkToggles", S)
local H = rawget(_G, "xhash")
local perks = {
    {"bandolier", "Bandolier Bandit"},
    {"tortoise", "Victorious Tortoise"}, {"gautys_gold", "Gauty's Gold"},
    {"electric_cherry", "Electric Cherry"}, {"jug2", "Roo Brew"},
    {"native_juggernog", "Juggernog", "specialty_juggernog"},
    {"native_quick_revive", "Quick Revive", "specialty_quick_revive"},
    {"native_speedcola", "Speed Cola", "specialty_speedcola"},
    {"native_staminup", "Stamin-Up", "specialty_staminup"},
    {"native_deadshot", "Deadshot Daiquiri", "specialty_deadshot"},
    {"native_elemental_pop", "Elemental Pop", "specialty_elemental_pop"},
    {"native_phd_flopper", "PhD Flopper", "specialty_phd_flopper"},
    {"native_death_perception", "Death Perception", "specialty_death_perception"},
    {"native_vulture_aid", "Vulture Aid", "specialty_vulture_aid"},
    {"native_m_mod", "Melee Macchiato", "specialty_m_mod"},
    {"native_d_mod", "Double Tap", "specialty_d_mod"},
    {"native_w_mod", "W Mod", "specialty_w_mod"},
    {"native_y_mod", "Y Mod", "specialty_y_mod"},
    {"native_z_mod", "Z Mod", "specialty_z_mod"}
}
local function get(t, key)
    if t == nil then return nil end
    local ok, value = pcall(function() return t[key] end)
    if ok and value ~= nil then return value end
    if type(H) == "function" then
        ok, value = pcall(function() return t[H(key)] end)
        if ok then return value end
    end
end
local function call(t, key, ...)
    local f = get(t, key)
    if type(f) == "function" then return f(t, ...) end
end
local function log(message)
    local f = rawget(_G, "DebugPrint")
    if type(f) == "function" then f("[PerkToggles] " .. tostring(message)) end
end
local function once(key, message)
    if not S.reported[key] then S.reported[key] = true; log(message) end
end
local function dvarHash(name)
    local f = rawget(_G, "xhashdvar") or get(rawget(_G, "CLUA"), "PushXHashDvar")
    if type(f) == "function" then return f(name) end
    return name
end
local function read(name)
    local f = get(rawget(_G, "Dvar"), "GetDvarString")
    if type(f) == "function" then
        local ok, value = pcall(f, dvarHash(name))
        if ok and value ~= nil then return tostring(value) end
    end
    return ""
end
local function write(name, value)
    local f = get(rawget(_G, "Dvar"), "SetDvarString")
    if type(f) == "function" then pcall(f, dvarHash(name), value) end
    if read(name) == value then return true end
    local exec = get(rawget(_G, "Engine"), "ExecNow")
    if type(exec) == "function" then pcall(exec, "set " .. name .. " " .. value .. "\n", 0) end
    return read(name) == value
end
local function frontend()
    local f = get(rawget(_G, "Engine"), "InFrontend")
    return type(f) == "function" and f() == true
end
local function zombies()
    local f = get(rawget(_G, "GameModesUtils"), "isactivegamemodezm")
    return type(f) == "function" and f() == true
end
local function make(kind)
    local f = get(get(rawget(_G, "LUI"), kind), "new")
    assert(type(f) == "function", kind .. " unavailable")
    return f()
end
local function position(element, x, y, width, height)
    call(element, "SetAnchorsAndPosition", 0, 1, 0, 1, x, x + width, y, y + height)
end
local function text(parent, value, x, y, width, height)
    local t = make("UIText")
    position(t, x, y, width, height)
    call(t, "setText", value)
    call(t, "SetRGB", 0xffffff)
    call(parent, "addElement", t)
    return t
end
local function focus(button)
    call(button, "processEvent", { name = "gain_focus" })
end
local function rect(parent, x, y, width, height, color, alpha)
    local image = make("UIImage")
    position(image, x, y, width, height)
    call(image, "SetRGB", color)
    call(image, "SetAlpha", alpha or 1)
    call(parent, "addElement", image)
    return image
end
local function icon(parent, material, x, y, size)
    local hud = rawget(_G, "BO7CustomPerks")
    if hud and type(hud.resolvePerkPackIcon) == "function" then material = hud.resolvePerkPackIcon(material) end
    local image = make("UIImage")
    position(image, x, y, size, size)
    local register = rawget(_G, "RegisterMaterial")
    local hash = rawget(_G, "xhashasset") or get(rawget(_G, "CLUA"), "PushXHashAsset")
    if type(register) == "function" then
        local ok, asset = pcall(function() return register(type(material) == "string" and type(hash) == "function" and hash(material) or material) end)
        if ok and asset then call(image, "setImage", asset) end
    end
    call(parent, "addElement", image)
    return image
end
local artwork = {
    bandolier = {"ui_icon_perks_zm_bandolier", "Carry additional reserve ammunition for your weapons."},
    tortoise = {"ui_icon_perks_zm_tortoise", "Reduce incoming damage while wearing armor."},
    gautys_gold = {"ui_icon_perks_zm_Gautys_Gold", "Earn additional points. Selected augments can improve earnings or refund purchases."},
    electric_cherry = {"ui_icons_perks_zm_electric_cherry", "Reload to unleash an electric shock that damages and stuns nearby zombies."},
    jug2 = {"ui_icons_perks_zm_roo_brew", "Jump five times as high. Moon Hop reduces gravity for five seconds after jumping."},
}
local open
open = function(parent, controller)
    if not frontend() then return end
    if S.panel then call(S.panel, "closeTree"); S.panel = nil end
    local allPerks = {}
    local hud = rawget(_G, "BO7CustomPerks")
    if hud and type(hud.customPerks) == "table" then
        for _, perk in ipairs(hud.customPerks) do
            local id = perk.ref:gsub("^specialty_", "")
            allPerks[#allPerks + 1] = {id, perk.name}
            artwork[id] = {perk.icon or "ui_icon_perks_zm_juggernaut", perk.desc or "Custom perk.", perk.creator or ""}
        end
    else
        for _, perk in ipairs(perks) do if not perk[3] then allPerks[#allPerks + 1] = perk end end
    end
    for _, perk in ipairs(perks) do if perk[3] then allPerks[#allPerks + 1] = perk end end
    local pageCount = math.ceil(#allPerks / 16)
    local page = tonumber(S.page) or 1
    if page < 1 or page > pageCount then page = 1 end
    S.page = page
    local perks = {}
    for i = (page - 1) * 16 + 1, math.min(page * 16, #allPerks) do
        local entry = allPerks[i]
        if entry[3] then
            local getter = get(rawget(_G, "PERK"), "GetBundleByRef")
            local ok, bundle = false, nil
            if type(getter) == "function" then ok, bundle = pcall(getter, entry[3]) end
            if ok and bundle then
                local localize = get(rawget(_G, "Engine"), "Localize")
                local name, description = get(bundle, "name"), get(bundle, "description")
                if type(localize) == "function" then
                    local good, value = pcall(localize, name)
                    if good and value and value ~= "" then entry[2] = tostring(value) end
                    good, value = pcall(localize, description)
                    if good and value then description = tostring(value) end
                end
                local customHud = rawget(_G, "BO7CustomPerks")
                local packIcons = customHud and customHud.perkPackIcons
                artwork[entry[1]] = {(packIcons and packIcons[entry[3]]) or get(bundle, "hudimage") or get(bundle, "image") or "ui_icon_perks_zm_juggernaut", type(description) == "string" and description or "Native Zombies perk."}
            end
            if not artwork[entry[1]] then artwork[entry[1]] = {"ui_icon_perks_zm_juggernaut", "Native Zombies perk; availability depends on the map."} end
            artwork[entry[1]][3] = "Treyarch"
        end
        perks[#perks + 1] = entry
    end
    local panel = make("UIVerticalNavigator")
    panel.id = "GautysCustomPerkToggles"
    position(panel, 0, 0, 1920, 1080)
    call(panel, "SetPriority", 1000)
    rect(panel, 0, 0, 1920, 1080, 0x0b0d10, 0.99)
    rect(panel, 0, 0, 1920, 80, 0x15171b)
    local title = text(panel, "CUSTOM PERKS", 280, 30, 450, 36)
    call(title, "SetFontSize", 28 * (rawget(_G, "_PT") or 1))
    text(panel, "PERK AVAILABILITY  /  " .. page .. " OF " .. pageCount, 96, 112, 600, 28)
    rect(panel, 96, 154, 1184, 2, 0x4b4e53)
    rect(panel, 96, 152, 265, 4, 0xf39b35)
    text(panel, "Choose the perks available in your next match.", 96, 178, 1184, 26)
    rect(panel, 1330, 112, 1, 745, 0x393c42)
    local creatorCredit = text(panel, "", 1372, 185, 448, 28)
    call(creatorCredit, "SetFontSize", 18 * (rawget(_G, "_PT") or 1))
    local detailIcon = icon(panel, artwork[perks[1][1]][1], 1458, 225, 200)
    local detailName = text(panel, perks[1][2], 1372, 470, 448, 42)
    local detailState = text(panel, "", 1372, 531, 448, 28)
    rect(panel, 1372, 580, 448, 1, 0x4b4e53)
    local detailDesc = text(panel, "", 1372, 610, 448, 120)
    call(detailDesc, "SetFontSize", 18 * (rawget(_G, "_PT") or 1))
    call(detailDesc, "SetWordWrap", true)
    text(panel, "Co-op uses the host's settings.", 1372, 790, 448, 26)
    text(panel, "Changes apply next match.", 1372, 827, 448, 26)
    local status = text(panel, "Selections save automatically.", 96, 884, 1184, 28)
    local buttons, labels, fills, tops, states, borders = {}, {}, {}, {}, {}, {}
    local selected = 1
    local footerIndex = nil
    local footerButtons, footerFills = {}, {}
    local function close()
        call(panel, "closeTree")
        S.panel = nil
        call(parent, "processEvent", {name = "gain_focus"})
    end
    local function details()
        local perk = perks[selected]
        local disabled = read("bo7_cp_off_" .. perk[1]) == "1"
        local creator = artwork[perk[1]][3]
        if type(creator) ~= "string" then creator = "" end
        call(creatorCredit, "setText", creator ~= "" and ("Created By: " .. creator) or "")
        call(detailName, "setText", perk[2])
        call(detailState, "setText", disabled and "DISABLED" or "ENABLED")
        call(detailState, "SetRGB", disabled and 0x96999f or 0xf6ac4e)
        call(detailDesc, "setText", artwork[perk[1]][2])
        local register = rawget(_G, "RegisterMaterial")
        local hash = rawget(_G, "xhashasset") or get(rawget(_G, "CLUA"), "PushXHashAsset")
        if type(register) == "function" then
            local ok, asset = pcall(function() local name = artwork[perk[1]][1]; local hud = rawget(_G, "BO7CustomPerks"); if hud and type(hud.resolvePerkPackIcon) == "function" then name = hud.resolvePerkPackIcon(name) end; return register(type(name) == "string" and type(hash) == "function" and hash(name) or name) end)
            if ok and asset then call(detailIcon, "setImage", asset) end
        end
    end
    local function select(index)
        footerIndex = nil
        for _, fill in ipairs(footerFills) do call(fill, "SetRGB", 0x24272d) end
        selected = index
        for i = 1, #buttons do
            local active = i == selected
            call(fills[i], "SetRGB", active and 0x34302a or 0x1b1e23)
            call(tops[i], "SetRGB", active and 0xffb34d or 0x4d5056)
            call(labels[i], "SetRGB", active and 0xffc575 or 0xf0f0f0)
            for _, edge in ipairs(borders[i]) do call(edge, "SetRGB", active and 0xffb34d or 0x40444a) end
        end
        details()
    end
    local function refresh(i)
        local disabled = read("bo7_cp_off_" .. perks[i][1]) == "1"
        call(states[i], "setText", disabled and "OFF" or "ON")
        call(states[i], "SetRGB", disabled and 0x96999f or 0xffbd62)
        details()
    end
    for i, perk in ipairs(perks) do
        local index, id, name = i, perk[1], perk[2]
        local button = make("UIButton")
        button.id = "PerkToggle_" .. id
        local column, row = (i - 1) % 4, math.floor((i - 1) / 4)
        position(button, 96 + column * 300, 240 + row * 158, 284, 146)
        call(button, "setHandleMouse", true)
        call(button, "setFocusable", true)
        fills[i] = rect(button, 0, 0, 284, 146, 0x1b1e23)
        tops[i] = rect(button, 0, 0, 284, 3, 0x4d5056)
        borders[i] = {rect(button, 0, 3, 1, 142, 0x40444a), rect(button, 283, 3, 1, 142, 0x40444a), rect(button, 0, 145, 284, 1, 0x40444a)}
        icon(button, artwork[id][1], 100, 8, 84)
        labels[i] = text(button, name, 12, 94, 260, 22)
        call(labels[i], "SetFontSize", 18 * (rawget(_G, "_PT") or 1))
        rect(button, 16, 119, 252, 1, 0x414349)
        states[i] = text(button, "", 16, 123, 252, 20)
        call(states[i], "SetFontSize", 16 * (rawget(_G, "_PT") or 1))
        call(button, "registerEventHandler", "button_action", function()
            select(index)
            local key = "bo7_cp_off_" .. id
            local value = read(key) == "1" and "0" or "1"
            if write(key, value) then
                refresh(index)
                call(status, "setText", name .. (value == "1" and " disabled" or " enabled") .. " for the next match.")
                log(id .. " off=" .. value)
            else
                call(status, "setText", "Could not save this setting. See the console for details.")
                log("ERROR writing " .. key)
            end
            return true
        end)
        call(button, "registerEventHandler", "button_over", function() select(index) end)
        call(panel, "addElement", button)
        buttons[i] = button
        refresh(i)
    end
    rect(panel, 96, 940, 1728, 1, 0x4b4e53)
    local back = make("UIButton")
    position(back, 96, 967, 270, 50)
    footerFills[1] = rect(back, 0, 0, 270, 50, 0x24272d)
    footerButtons[1] = back
    call(back, "setFocusable", true)
    call(back, "setHandleMouse", true)
    text(back, "BACK", 12, 7, 246, 35)
    call(back, "registerEventHandler", "button_action", function() close(); return true end)
    call(panel, "addElement", back)
    local function pageButton(label, x, change)
        local button = make("UIButton")
        position(button, x, 967, 230, 50)
        footerFills[#footerFills + 1] = rect(button, 0, 0, 230, 50, 0x24272d)
        footerButtons[#footerButtons + 1] = button
        call(button, "setFocusable", true)
        call(button, "setHandleMouse", true)
        text(button, label, 10, 7, 210, 35)
        call(button, "registerEventHandler", "button_action", function()
            S.page = (page - 1 + change) % pageCount + 1
            open(parent, controller)
            return true
        end)
        call(panel, "addElement", button)
    end
    pageButton("PREVIOUS", 400, -1)
    pageButton("NEXT", 660, 1)
    local frameChoices = {{id = 0, name = "Default"}}
    for _, entry in ipairs(rawget(_G, "BO7EternalFramePacks") or {}) do frameChoices[#frameChoices + 1] = entry end
    local frameButton = make("UIButton")
    position(frameButton, 920, 967, 430, 50)
    footerFills[#footerFills + 1] = rect(frameButton, 0, 0, 430, 50, 0x24272d)
    footerButtons[#footerButtons + 1] = frameButton
    call(frameButton, "setFocusable", true)
    call(frameButton, "setHandleMouse", true)
    local frameLabel = text(frameButton, "", 12, 8, 406, 34)
    call(frameLabel, "SetFontSize", 18 * (rawget(_G, "_PT") or 1))
    local function frameChoiceIndex()
        local selectedId = tonumber(read("bo7_cp_eternal_frame_style")) or 0
        for i, entry in ipairs(frameChoices) do if entry.id == selectedId then return i end end
        return 1
    end
    local function updateFrameLabel()
        call(frameLabel, "setText", "FRAME: " .. frameChoices[frameChoiceIndex()].name)
    end
    updateFrameLabel()
    call(frameButton, "registerEventHandler", "button_action", function()
        local nextChoice = frameChoices[frameChoiceIndex() % #frameChoices + 1]
        if write("bo7_cp_eternal_frame_style", tostring(nextChoice.id)) then
            updateFrameLabel()
            call(status, "setText", "Eternal perk frame: " .. nextChoice.name)
        else
            call(status, "setText", "Could not save the frame selection.")
        end
        return true
    end)
    call(panel, "addElement", frameButton)
    local systemCredit = text(panel, "Custom perk system created by Gauty", 1380, 977, 445, 28)
    call(systemCredit, "SetFontSize", 16 * (rawget(_G, "_PT") or 1))
    call(panel, "registerEventHandler", "button_secondary", function() close(); return true end)
    local function focusFooter(index)
        footerIndex = index
        for i, fill in ipairs(footerFills) do
            call(fill, "SetRGB", i == index and 0x805521 or 0x24272d)
        end
        focus(footerButtons[index])
    end
    for i, button in ipairs(footerButtons) do
        local index = i
        call(button, "registerEventHandler", "button_over", function()
            footerIndex = index
            for j, fill in ipairs(footerFills) do
                call(fill, "SetRGB", j == index and 0x805521 or 0x24272d)
            end
        end)
    end
    call(panel, "registerEventHandler", "gamepad_button", function(_, event)
        if not event or event.down == false then return end
        if event.button == "secondary" then close(); return true end
        if footerIndex then
            if event.button == "left" then focusFooter((footerIndex - 2) % #footerButtons + 1)
            elseif event.button == "right" then focusFooter(footerIndex % #footerButtons + 1)
            elseif event.button == "up" then select(selected); focus(buttons[selected])
            elseif event.button == "down" then return true
            else return end
            return true
        end
        local nextIndex = selected
        if event.button == "up" then nextIndex = selected > 4 and selected - 4 or selected
        elseif event.button == "down" then
            if selected + 4 > #buttons then
                focusFooter(1)
                return true
            end
            nextIndex = selected + 4
        elseif event.button == "left" then nextIndex = selected > 1 and selected - 1 or #buttons
        elseif event.button == "right" then nextIndex = selected < #buttons and selected + 1 or 1
        else return end
        select(nextIndex)
        focus(buttons[nextIndex])
        return true
    end)
    call(parent, "addElement", panel)
    S.panel = panel
    select(1)
    focus(buttons[1])
    log("augment-style toggle panel opened")
end

local function setValue(row, key, controller, value)
    local node = get(row, key)
    local f = get(node, "SetValue")
    assert(type(f) == "function", "missing button field " .. key)
    f(node, controller, value)
end
local function attach(menu, controller)
    if not frontend() or not zombies() then return end
    local ds = rawget(_G, "_DataSources")
    for _, key in ipairs({"mp", "weapons", "cac", "weapons_tab", "weapon_tab_buttons"}) do ds = get(ds, key) end
    assert(ds ~= nil, "weapons button datasource unavailable")
    local countNode = get(ds, "count")
    local count = tonumber(call(countNode, "GetValue", controller))
    assert(count and count >= 0 and count < 20, "invalid weapons button count")
    for i = 1, count do
        if call(get(get(ds, i), "auto_id"), "GetValue", controller) == "gautys_custom_perks" then return end
    end
    local insertion = 2
    local weapon = rawget(_G, "WEAPON")
    local loadoutId = get(get(weapon, "weapontabbuttonid"), "loadouts")
    for i = 1, count do
        local source = get(ds, i)
        local id = call(get(source, "button_id"), "GetValue", controller)
        local autoId = call(get(source, "auto_id"), "GetValue", controller)
        if (loadoutId ~= nil and id == loadoutId) or autoId == "loadouts_weaponmenubutton" then
            insertion = i + 1
            break
        end
    end
    if insertion > count + 1 then insertion = count + 1 end
    local fields = {"Label", "command", "is_locked", "unlock_string", "auto_id", "button_id"}
    for i = count, insertion, -1 do
        local source, destination = get(ds, i), get(ds, i + 1)
        assert(destination ~= nil, "weapons button row unavailable")
        for _, key in ipairs(fields) do
            setValue(destination, key, controller, call(get(source, key), "GetValue", controller))
        end
    end
    local row = get(ds, insertion)
    assert(row ~= nil, "weapons button row unavailable")
    setValue(row, "Label", controller, "CUSTOM PERKS")
    local commandNew = get(get(rawget(_G, "LUI"), "Command"), "new")
    assert(type(commandNew) == "function", "LUI.Command constructor unavailable")
    local command = commandNew(function()
        log("Custom Perks command executed")
        local ok, err = pcall(open, menu, controller)
        if not ok then log("ERROR opening panel: " .. tostring(err)) end
    end)
    setValue(row, "command", controller, command)
    setValue(row, "is_locked", controller, false)
    setValue(row, "unlock_string", controller, "")
    setValue(row, "auto_id", controller, "gautys_custom_perks")
    setValue(row, "button_id", controller, 1985)
    call(countNode, "SetValue", controller, count + 1)
    log("Custom Perks button added to Weapons tab")
end
local function hook()
    local owner = rawget(_G, "WEAPON")
    if type(owner) ~= "table" then return end
    local keys = {"initweapontabbuttonsdatasource"}
    if type(H) == "function" then keys[#keys + 1] = H(keys[1]) end
    for _, key in ipairs(keys) do
        local original = owner[key]
        if type(original) == "function" and S.hooks[key] ~= original then
            local wrapper = function(menu, controller, ...)
                local result = original(menu, controller, ...)
                local current = rawget(_G, "BO7PerkToggles")
                if current == S and S.enabled then
                    local ok, err = pcall(attach, menu, controller)
                    if not ok then
                        once("attach", "Native button list unavailable: " .. tostring(err))
                        if not get(menu, "gautysPerkToggleButton") then
                            local added, failure = pcall(function()
                                local button = make("UIButton")
                                position(button, 90, 810, 340, 55)
                                text(button, "CUSTOM PERKS", 12, 6, 320, 40)
                                call(button, "setHandleMouse", true)
                                call(button, "setFocusable", true)
                                call(button, "registerEventHandler", "button_action", function()
                                    local opened, detail = pcall(open, menu, controller)
                                    if not opened then log("ERROR opening panel: " .. tostring(detail)) end
                                    return true
                                end)
                                call(menu, "addElement", button)
                                menu.gautysPerkToggleButton = button
                            end)
                            if not added then once("fallback", "ERROR adding fallback button: " .. tostring(failure)) end
                        end
                    end
                end
                return result
            end
            owner[key] = wrapper
            S.hooks[key] = wrapper
            once("hook", "Weapons tab hook installed")
        end
    end
end
local function tick()
    if not S.enabled then return end
    hook()
    local f = get(rawget(_G, "LUI"), "GetRoot")
    if type(f) ~= "function" then return end
    local ok, root = pcall(f)
    if not ok or not root then return end
    local timer = call(root, "Wait", 1000)
    if timer then timer.onComplete = tick end
end
tick()
log("custom perk switches loaded")
