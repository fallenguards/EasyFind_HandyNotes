-- HandyNotes' map pins as EasyFind search rows: every plugin's pins found
-- by name, a click asks EasyFind's GPS for directions to the pin. Pins
-- are read at runtime through HandyNotes' plugin interface, the way its
-- own map reads them; nothing of a plugin's is copied.
local _, ns = ...
local API = EasyFind and EasyFind.API
if not (API and API.VERSION == 1) then return end

local L = ns.L
local KEY = "handynotes"
local ICON = "Interface\\AddOns\\EasyFind_HandyNotes\\map"
local COSMIC, AZEROTH = 946, 947
local MAPS_PER_FRAME = 60
local RESOLVE_WAIT, RESOLVE_TRIES = 2, 3   -- names the server has not sent yet
local REWALK_WAIT = 3                      -- after a plugin says its pins changed
local NAME_FIELDS = { "label", "name", "title", "text", "desc" }

local C_Map, C_Item, C_QuestLog, C_Spell, C_CurrencyInfo, C_Reputation, C_TooltipInfo, C_Timer, C_AddOns =
      C_Map, C_Item, C_QuestLog, C_Spell, C_CurrencyInfo, C_Reputation, C_TooltipInfo, C_Timer, C_AddOns
local IsShiftKeyDown, CreateVector2D = IsShiftKeyDown, CreateVector2D
local sformat, tsort, floor, wipe = string.format, table.sort, math.floor, wipe
local issecretvalue = issecretvalue or function(_) return false end

-- Module state: HandyNotes once bound, the map list, the index per
-- plugin, what to walk again.
local H = { ready = false, index = {}, lookup = {}, titles = {}, npcs = {}, dirty = {}, all = true, gen = 0 }

local function DB()
    EasyFindHandyNotesDB = EasyFindHandyNotesDB or {}
    return EasyFindHandyNotesDB
end

local function ErrorHandler(err)
    geterrorhandler()(err .. "\n" .. debugstack(2))
end

-- ==== names ================================================================

local function Strip(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
             :gsub("\n", ", "):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function NpcName(id)
    local name = H.npcs[id]
    if name then return name end
    local data = C_TooltipInfo.GetHyperlink("unit:Creature-0-0-0-0-" .. id)
    local line = data and data.lines and data.lines[1]
    name = line and line.leftText
    if name == nil or issecretvalue(name) then return nil end
    if type(name) ~= "string" or name == "" or name == UNKNOWNOBJECT then return nil end
    H.npcs[id] = name
    return name
end

-- A criterion under 100 is an index into the achievement, above it an id.
local function CriteriaName(achievement, criterion)
    local ok, text
    if criterion < 100 then
        ok, text = pcall(GetAchievementCriteriaInfo, achievement, criterion)
    else
        ok, text = pcall(GetAchievementCriteriaInfoByID, achievement, criterion)
    end
    if ok and type(text) == "string" and text ~= "" then return text end
    return nil
end

local function AchievementName(id)
    local ok, _, name = pcall(GetAchievementInfo, id)
    return ok and name or nil
end

local function TokenName(what, id, sub, text)
    if what =="npc" then return NpcName(id) or text end
    if what =="item" then
        local name = C_Item.GetItemNameByID(id)
        if not name then C_Item.RequestLoadItemDataByID(id) end
        return name or text
    end
    if what == "quest" or what == "daily" then
        local name = C_QuestLog.GetTitleForQuestID(id)
        if not name then C_QuestLog.RequestLoadQuestByID(id) end
        return name or text
    end
    if what =="spell" then
        local name = C_Spell.GetSpellName(id)
        if not name then C_Spell.RequestLoadSpellData(id) end
        return name or text
    end
    if what =="achievement" then
        if sub then return CriteriaName(id, sub) or text end
        return AchievementName(id) or text
    end
    if what =="currency" then
        local info = C_CurrencyInfo.GetCurrencyInfo(id)
        return info and info.name or text
    end
    if what =="faction" then
        local info = C_Reputation.GetFactionDataByID(id)
        return info and info.name or text
    end
    if what =="map" then
        local info = C_Map.GetMapInfo(id)
        return info and info.name or text
    end
    if what =="area" then return C_Map.GetAreaInfo(id) or text end
    if what =="pet" and C_PetJournal then return C_PetJournal.GetPetInfoBySpeciesID(id) or text end
    return text
end

-- A label's {kind:id}, {kind:id.sub} and {kind:id:text} tokens become
-- names and {kind:text} keeps its text; the second result says a name is
-- still on its way from the server.
local function Render(label)
    local unresolved = false
    local out = label:gsub("{(%l+):(%d+)%.?(%d*):?([^{}]*)}", function(what, id, sub, text)
        local name = TokenName(what, tonumber(id), tonumber(sub), text ~= "" and text or nil)
        if name then return name end
        unresolved = true
        return ""
    end)
    out = out:gsub("{%l+:([^{}]*)}", "%1")
    return Strip(out), unresolved
end

-- A plugin's node may answer a field through a getter that throws.
local function Field(node, key)
    local ok, value = pcall(function() return node[key] end)
    if ok then return value end
    return nil
end

-- A pin without a text field, named from the ids it carries.
local function IdName(node)
    local npc = Field(node, "npc")
    if type(npc) == "number" then return NpcName(npc), true end
    local achievement, criterion = Field(node, "achievement"), Field(node, "criteria")
    if type(criterion) == "table" then criterion = criterion[1] end
    if type(achievement) == "number" and type(criterion) == "number" then
        local name = CriteriaName(achievement, criterion)
        if name then return name, false end
    end
    local loot = Field(node, "loot")
    local first = type(loot) == "table" and loot[1]
    local item = type(first) == "table" and first.id or first
    if type(item) == "number" then
        local name = C_Item.GetItemNameByID(item)
        if not name then C_Item.RequestLoadItemDataByID(item) end
        return name, true
    end
    if type(achievement) == "number" then
        local name = AchievementName(achievement)
        if name then return name, false end
    end
    local currency = Field(node, "currency")
    if type(currency) == "number" then
        local info = C_CurrencyInfo.GetCurrencyInfo(currency)
        if info then return info.name, false end
    end
    return nil, false
end

-- The pin's name from the node its plugin keeps behind the coord: its
-- first text field with the tokens rendered, else its ids.
local function NameOf(node)
    for i = 1, #NAME_FIELDS do
        local value = Field(node, NAME_FIELDS[i])
        if type(value) == "string" and value ~= "" then
            if value:find("{", 1, true) then return Render(value) end
            return Strip(value), false
        end
    end
    return IdName(node)
end

-- Done as the plugin sees it: its own check, else its quests all flagged.
local function IsDone(node)
    local check = Field(node, "IsCompleted")
    if type(check) == "function" then
        local ok, done = pcall(check, node)
        return ok and done == true
    end
    local quest = Field(node, "quest")
    if type(quest) == "number" then return C_QuestLog.IsQuestFlaggedCompleted(quest) end
    if type(quest) == "table" and #quest > 0 then
        for i = 1, #quest do
            if not C_QuestLog.IsQuestFlaggedCompleted(quest[i]) then return false end
        end
        return true
    end
    return false
end

-- ==== HandyNotes ===========================================================

local function Bind()
    local HN = _G.HandyNotes
    if type(HN) ~= "table" or type(HN.plugins) ~= "table" or type(HN.getXY) ~= "function"
       or type(HN.UpdatePluginMap) ~= "function" then
        return false
    end
    H.hn = HN
    return true
end

local function HandyNotesOn()
    local HN = H.hn
    if type(HN.IsEnabled) ~= "function" then return true end
    return HN:IsEnabled() == true
end

-- The player's own switch for the plugin in HandyNotes' options.
local function PluginShown(name)
    local profile = H.hn.db and H.hn.db.profile
    local enabled = profile and profile.enabledPlugins
    return not enabled or enabled[name] ~= false
end

local function PluginTitle(name)
    local title = H.titles[name]
    if title then return title end
    title = C_AddOns.GetAddOnMetadata(name, "Title") or C_AddOns.GetAddOnMetadata("HandyNotes_" .. name, "Title")
    title = title and (Strip(title):gsub("^HandyNotes:%s*", "")) or name
    H.titles[name] = title
    return title
end

local function ZoneName(mapID)
    local info = C_Map.GetMapInfo(mapID)
    return info and info.name or "?"
end

local function MapList()
    if H.maps then return H.maps end
    local list, seen = { COSMIC, AZEROTH }, { [COSMIC] = true, [AZEROTH] = true }
    local kids = C_Map.GetMapChildrenInfo(COSMIC, nil, true)
    for i = 1, kids and #kids or 0 do
        local id = kids[i].mapID
        if not seen[id] then
            seen[id] = true
            list[#list + 1] = id
        end
    end
    H.maps = list
    return list
end

local function EntryKey(mapID, coord)
    return mapID * 100000000 + coord
end

local function Entry(plugin, mapID, coord, node, iconpath)
    local name, unresolved = NameOf(node)
    local x, y = H.hn:getXY(coord)
    local icon = iconpath
    if type(iconpath) == "table" then icon = not iconpath.tCoordLeft and iconpath.icon or nil end
    if type(icon) ~= "string" and type(icon) ~= "number" then icon = nil end
    local e = { name = name, plugin = plugin, mapID = mapID, coord = coord, x = x, y = y, node = node,
                icon = icon, done = IsDone(node), unresolved = unresolved or nil, gen = H.gen }
    local continent, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
    if pos then
        e.ci = continent
        e.wx, e.wy = pos:GetXY()
    end
    return e
end

-- One plugin's pins on one map, through the iterator HandyNotes' own map
-- uses, so the plugin's settings (hidden groups, done pins) apply. The
-- iterator's state leads to the node behind each coord.
local function WalkMap(plugin, handler, mapID, out)
    local iter, state, init = handler:GetNodes2(mapID, false)
    if type(iter) ~= "function" then return end
    local prev = init
    while true do
        local coord, mapID2, iconpath = iter(state, prev)
        if coord == nil then break end
        prev = coord
        -- A zone's pin shown on its continent is indexed from the zone.
        if not (mapID2 and mapID2 ~= mapID) and type(state) == "table" then
            local node = rawget(state, coord)
            if node == nil then
                local data = rawget(state, "data")
                node = type(data) == "table" and rawget(data, coord) or nil
            end
            if type(node) == "table" then out[#out + 1] = Entry(plugin, mapID, coord, node, iconpath) end
        end
    end
end

-- ==== the index ============================================================

local StartWalk

local function Refresh()
    API.RefreshSearchProvider(KEY)
end

local function Add(e)
    local plugin = e.plugin
    local index = H.index[plugin]
    if not index then
        index = {}
        H.index[plugin] = index
        H.lookup[plugin] = {}
    end
    index[#index + 1] = e
    H.lookup[plugin][EntryKey(e.mapID, e.coord)] = e
end

-- Pins whose name had not arrived: asked again a little later.
local function Resolve(pending, try)
    C_Timer.After(RESOLVE_WAIT, function()
        local left, added = {}, false
        for i = 1, #pending do
            local e = pending[i]
            if e.gen == H.gen then
                local name, unresolved = NameOf(e.node)
                if name then
                    e.name, e.unresolved = name, nil
                    Add(e)
                    added = true
                elseif unresolved then
                    left[#left + 1] = e
                end
            end
        end
        if added then Refresh() end
        if #left > 0 and try < RESOLVE_TRIES then Resolve(left, try + 1) end
    end)
end

local function Finish(fresh)
    H.walking = false
    local pending = {}
    for plugin, entries in pairs(fresh) do
        H.index[plugin], H.lookup[plugin] = nil, nil
        for i = 1, #entries do
            local e = entries[i]
            if e.name then
                Add(e)
            elseif e.unresolved then
                pending[#pending + 1] = e
            end
        end
    end
    if #pending > 0 then Resolve(pending, 1) end
    Refresh()
    if H.all or next(H.dirty) then StartWalk() end
end

-- Walks every map for the plugins that need it, a few maps per frame.
StartWalk = function()
    if H.walking or not H.ready then return end
    local HN = H.hn
    local plugins, fresh = {}, {}
    for name, handler in pairs(HN.plugins) do
        if not PluginShown(name) then
            H.index[name], H.lookup[name] = nil, nil
        elseif (H.all or H.dirty[name]) and type(handler.GetNodes2) == "function" then
            plugins[#plugins + 1] = name
            fresh[name] = {}
        end
    end
    H.all = false
    wipe(H.dirty)
    H.walked = true
    if #plugins == 0 then
        Refresh()
        return
    end
    H.walking = true
    H.gen = H.gen + 1
    local maps, at = MapList(), 0
    local function Step()
        local stop = math.min(at + MAPS_PER_FRAME, #maps)
        for m = at + 1, stop do
            for i = 1, #plugins do
                local name = plugins[i]
                xpcall(WalkMap, ErrorHandler, name, HN.plugins[name], maps[m], fresh[name])
            end
        end
        at = stop
        if at < #maps then
            C_Timer.After(0, Step)
        else
            Finish(fresh)
        end
    end
    C_Timer.After(0, Step)
end

local function MarkDirty(plugin)
    if plugin then H.dirty[plugin] = true else H.all = true end
    if H.rewalk or not H.walked then return end
    H.rewalk = true
    C_Timer.After(REWALK_WAIT, function()
        H.rewalk = nil
        StartWalk()
    end)
end

-- ==== rows =================================================================

local function EntryOf(row)
    local lookup = row.plugin and H.lookup[row.plugin]
    return lookup and lookup[EntryKey(row.mapID, row.coord)] or nil
end

-- The same pin drawn on two maps (a zone and its continent) is one row.
local function SpotKey(e)
    if not e.wx then return e.plugin .. "\0" .. e.name .. "\0" .. e.mapID end
    return e.plugin .. "\0" .. e.name .. "\0" .. e.ci .. "\0" .. floor(e.wx / 5) .. "\0" .. floor(e.wy / 5)
end

local function ByName(a, b) return a.name < b.name end

local function Rows()
    if not H.ready or not HandyNotesOn() then return {} end
    if not H.walked then StartWalk() end
    local db = DB()
    local here = db.nearMe and C_Map.GetBestMapForUnit("player") or nil
    local out, seen = {}, {}
    for plugin, entries in pairs(H.index) do
        local title = PluginTitle(plugin)
        for i = 1, #entries do
            local e = entries[i]
            local keep = not (db.hideDone and e.done)
            if keep and here then keep = e.mapID == here end
            if keep then
                local key = SpotKey(e)
                if not seen[key] then
                    seen[key] = true
                    out[#out + 1] = { name = e.name, icon = e.icon, mapID = e.mapID, coord = e.coord, plugin = plugin,
                                      searchCommandDesc = sformat(L["FROM_FMT"], ZoneName(e.mapID), title) }
                end
            end
        end
    end
    tsort(out, ByName)
    return out
end

local function Dest(e)
    return { name = e.name, mapID = e.mapID, x = e.x, y = e.y, step = L["STEP_PIN"] }
end

local function Navigate(dest)
    if API.HasAction("gps", "navigate") then
        API.CallAction("gps", "navigate", dest, { popout = true })
    elseif C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(dest.mapID) then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(dest.mapID, dest.x, dest.y))
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    else
        print(sformat(L["NO_PLACE"], dest.name))
    end
end

-- The game's own map pin link, as a pin's "Link to chat" sends it.
local function InsertChatLink(e)
    local link = sformat("|cffffff00|Hworldmap:%d:%d:%d|h[%s]|h|r", e.mapID, e.x * 10000, e.y * 10000, MAP_PIN_HYPERLINK)
    local active = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
    if active and active:IsShown() then
        active:Insert(link)
    elseif not (ChatEdit_InsertLink and ChatEdit_InsertLink(link)) and ChatFrame_OpenChat then
        ChatFrame_OpenChat(link)
    end
end

local function Select(row)
    local e = EntryOf(row)
    if not e then return end
    if IsShiftKeyDown() then return InsertChatLink(e) end
    Navigate(Dest(e))
end

local function Place(row)
    local e = EntryOf(row)
    return e and Dest(e) or nil
end

-- The plugin's own tooltip for the pin when its node renders one, else
-- the name and its note; the place and the plugin under either.
local function Tooltip(row, tt)
    local e = EntryOf(row)
    if not e then return false end
    local render = Field(e.node, "Render")
    if not (type(render) == "function" and pcall(render, e.node, tt, false)) then
        tt:SetText(e.name)
        local note = Field(e.node, "note") or Field(e.node, "desc")
        if type(note) == "string" and note ~= "" then tt:AddLine((Render(note)), 1, 1, 1, true) end
    end
    tt:AddLine(sformat("%s  %.1f, %.1f", ZoneName(e.mapID), e.x * 100, e.y * 100), 0.8, 0.8, 0.8)
    tt:AddLine(PluginTitle(e.plugin), 0.6, 0.6, 0.6)
    return true
end

-- With nothing typed, the scope lists the pins on the player's map.
local function Browse(row)
    local here = C_Map.GetBestMapForUnit("player")
    if here ~= H.hereID then
        H.hereID = here
        local info = here and C_Map.GetMapInfo(here)
        H.hereParent = info and info.parentMapID or nil
    end
    return row.mapID == here or row.mapID == H.hereParent
end

-- ==== registration =========================================================

local events = CreateFrame("Frame")

local function WatchZone()
    if DB().nearMe then events:RegisterEvent("ZONE_CHANGED_NEW_AREA") else events:UnregisterEvent("ZONE_CHANGED_NEW_AREA") end
end

local function Option(key, label, tip)
    return {
        label = label, tooltip = tip,
        get = function() return DB()[key] == true end,
        set = function(on)
            DB()[key] = on or nil
            WatchZone()
            Refresh()
        end,
    }
end

local OPTIONS = {
    Option("hideDone", L["OPT_HIDE_DONE"], L["OPT_HIDE_DONE_TIP"]),
    Option("nearMe", L["OPT_NEAR_ME"], L["OPT_NEAR_ME_TIP"]),
}

API.RegisterExtension({
    id = KEY,
    name = L["EXT_NAME"],
    description = L["EXT_DESC"],
    icon = ICON,
    keywords = { "handynotes", "pin", "pins" },
    scope = KEY,
    settings = function(page, kit)
        local below = kit.Title(page, L["EXT_NAME"], L["SETTINGS_HINT"])
        for i = 1, #OPTIONS do
            local box = kit.Checkbox(page, OPTIONS[i].label, OPTIONS[i].get, OPTIONS[i].set, OPTIONS[i].tooltip)
            box:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, i == 1 and -8 or -4)
            below = box
        end
    end,
})

API.RegisterSearchProvider({
    key = KEY,
    label = L["PROVIDER_LABEL"],
    extension = KEY,
    words = { "pin", "pins", "handynotes" },
    aliases = { "pins", "handynotes", "hn" },
    options = OPTIONS,
    rows = Rows,
    select = Select,
    tooltip = Tooltip,
    hint = { click = L["HINT_GPS"], shift = L["HINT_LINK"] },
    place = Place,
    browse = Browse,
})

events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        events:UnregisterEvent("PLAYER_LOGIN")
        if not Bind() then
            print("|cff66ccff" .. L["EXT_NAME"] .. ":|r " .. L["NOT_READY"])
            return
        end
        H.ready = true
        -- A plugin's pins changed, or HandyNotes redrew everything.
        hooksecurefunc(H.hn, "UpdatePluginMap", function(_, _, plugin) MarkDirty(plugin) end)
        hooksecurefunc(H.hn, "UpdateWorldMap", function() MarkDirty() end)
        WatchZone()
    else
        Refresh()
    end
end)
events:RegisterEvent("PLAYER_LOGIN")
