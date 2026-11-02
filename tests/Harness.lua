-- The extension loaded offline: its toc's files run in a stand-in game
-- (maps, timers, frames, tooltips; retail or classic calls) against a
-- recording EasyFind.API and a stand-in HandyNotes with plugins.
--   local Harness = require("Harness")
--   local ctx = Harness.Load({ client = "classic", gps = true })
local Harness = {}

local source = debug.getinfo(1, "S").source:sub(2)
local ROOT = source:gsub("[/\\]?tests[/\\]Harness%.lua$", "")
if ROOT == "" then ROOT = "." end
Harness.ROOT = ROOT
Harness.TOC = "EasyFind_HandyNotes.toc"

function Harness.Read(path)
    local f = assert(io.open(ROOT .. "/" .. path, "rb"))
    local text = f:read("a")
    f:close()
    return text
end

function Harness.Eq(got, want, label)
    if got ~= want then
        error(string.format("%s: got %s, wanted %s", label or "value", tostring(got), tostring(want)), 2)
    end
end

function Harness.True(ok, label)
    if not ok then error((label or "check") .. " failed", 2) end
end

-- The toc's fields and the Lua files it lists, in order.
function Harness.Toc()
    local text = Harness.Read(Harness.TOC)
    local fields, files = {}, {}
    for line in text:gmatch("[^\r\n]+") do
        local key, value = line:match("^## ([%w%-]+):%s*(.-)%s*$")
        if key then
            fields[key] = value
        elseif not line:match("^#") and line:match("%.lua") then
            files[#files + 1] = line:match("^(%S+)"):gsub("\\", "/")
        end
    end
    return fields, files
end

-- EasyFind's field types (Core/API.lua, MINOR 6): anything else passed is
-- an unknown field, a wrong type a load error there.
Harness.EXTENSION_FIELDS = {
    id = "string", name = "string", description = "string", icon = "texture", iconCoords = "table",
    addon = "string", loadInCombat = "boolean", loadAtLogin = "boolean", open = "function", close = "function",
    isOpen = "function", menu = "function", settings = "function", settingsRows = "function",
    resetSettings = "function", keywords = "table",
    hideFromSearch = "boolean", experimental = "string", scope = "string",
}
Harness.PROVIDER_FIELDS = {
    key = "string", label = "string", category = "string", icon = "texture", iconCoords = "table", iconWell = "boolean",
    words = "table", eager = "boolean", lazy = "boolean", lowResults = "boolean",
    aliases = "table", options = "table", rows = "function", select = "function", tooltip = "function",
    leave = "function", extension = "string", loadOnSearch = "any", hint = "any", browse = "function",
    place = "function", places = "function", link = "table", menu = "function",
}
Harness.DECORATOR_FIELDS = {
    id = "string", extension = "string", slot = "string", label = "string", applies = "function",
    categories = "table", text = "function", tooltip = "function", menu = "function", submenu = "boolean",
    subtext = "function", select = "function", hint = "function", keep = "function", sortKey = "function",
    aliases = "table", browse = "function", candidates = "function",
}

-- Unknown fields and wrong types in a registration, as one string.
function Harness.FieldErrors(def, fields)
    local bad = {}
    for k, v in pairs(def) do
        local want = fields[k]
        if want == nil then
            bad[#bad + 1] = k .. " is no field"
        elseif want == "texture" then
            if type(v) ~= "string" and type(v) ~= "number" then bad[#bad + 1] = k .. " is no texture" end
        elseif want ~= "any" and type(v) ~= want then
            bad[#bad + 1] = k .. " is a " .. type(v)
        end
    end
    table.sort(bad)
    return table.concat(bad, "; ")
end

-- ==== the world ==============================================================

-- Maps: Cosmic over Azeroth over Kalimdor over Durotar and Orgrimmar (its
-- Cleft of Shadow below it), and Outland beside Azeroth. A map's spot in
-- its continent's yards: { continent, left, top, size }; type as the
-- client's (0 cosmic, 1 world, 2 continent, 3 zone, 4 dungeon).
local MAPS = {
    [946] = { name = "Cosmic", type = 0 },
    [947] = { name = "Azeroth", parent = 946, type = 1 },
    [12] = { name = "Kalimdor", parent = 947, type = 2, at = { 1, 0, 0, 10000 } },
    [1] = { name = "Durotar", parent = 12, type = 3, at = { 1, 1000, 1000, 1000 } },
    [85] = { name = "Orgrimmar", parent = 1, type = 3, at = { 1, 1200, 1200, 200 } },
    [86] = { name = "Cleft of Shadow", parent = 85, type = 4 },
    [1945] = { name = "Outland", parent = 946, type = 2, at = { 530, 0, 0, 10000 } },
    [100] = { name = "Hellfire Peninsula", parent = 1945, type = 3, at = { 530, 2000, 2000, 1000 } },
}
Harness.MAPS = MAPS

local function Descendants(id, out)
    for child, info in pairs(MAPS) do
        if info.parent == id then
            out[#out + 1] = { mapID = child }
            Descendants(child, out)
        end
    end
    return out
end

local function Hooksecurefunc(t, name, fn)
    local orig = assert(t[name], name .. " is not a function")
    t[name] = function(...)
        local r = table.pack(orig(...))
        fn(...)
        return table.unpack(r, 1, r.n)
    end
end

-- A frame: scripts, events and shown state; a GameTooltip also reads a
-- creature's name onto its first line, as the scan in Pins.lua expects.
local function NewFrame(ctx, kind, name)
    local f = { scripts = {}, hooks = {}, events = {}, shown = true, lines = 0 }
    function f:SetScript(which, fn) self.scripts[which] = fn end
    function f:HookScript(which, fn)
        self.hooks[which] = self.hooks[which] or {}
        table.insert(self.hooks[which], fn)
    end
    function f:RegisterEvent(e) self.events[e] = true end
    function f:UnregisterEvent(e) self.events[e] = nil end
    function f:IsEventRegistered(e) return self.events[e] == true end
    function f:IsShown() return self.shown end
    function f:Show() self.shown = true end
    function f:Hide()
        local was = self.shown
        self.shown = false
        if was then for _, fn in ipairs(self.hooks.OnHide or {}) do fn(self) end end
    end
    if kind == "GameTooltip" then
        local line = { text = nil }
        function line.GetText() return line.text end
        ctx.env[name .. "TextLeft1"] = line
        function f:SetOwner() self.lines = 0 end
        function f:SetHyperlink(link)
            local id = tonumber(link:match("^unit:Creature%-0%-0%-0%-0%-(%d+)"))
            line.text = id and ctx.npcs[id] or nil
            self.lines = line.text and 1 or 0
            ctx.scans = (ctx.scans or 0) + 1
        end
        function f:NumLines() return self.lines end
    end
    ctx.frames[#ctx.frames + 1] = f
    return f
end

-- The game's globals for the client: "retail" (12.x) or "classic" (Era,
-- TBC Anniversary, Mists: the classic quest and faction calls, no
-- tooltip data, no user waypoints).
local function Game(ctx, client)
    local env, w = ctx.env, ctx.world
    env.C_Timer = { After = function(delay, fn)
        ctx.timers[#ctx.timers + 1] = { at = ctx.now + (delay or 0), fn = fn, seq = #ctx.timers }
    end }
    env.CreateFrame = function(kind, name) return NewFrame(ctx, kind, name) end
    env.CreateVector2D = function(x, y) return { x = x, y = y } end
    env.GetTime = function() return ctx.now end
    env.IsShiftKeyDown = function() return w.shift end
    env.hooksecurefunc = Hooksecurefunc
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    env.debugstack = function() return "" end
    env.geterrorhandler = function() return function(err) ctx.errors[#ctx.errors + 1] = err end end
    env.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
        ctx.printed[#ctx.printed + 1] = table.concat(parts, " ")
    end
    env.UNKNOWNOBJECT = "Unknown"
    env.Enum = { UIMapType = { Zone = 3 } }
    env.WorldFrame = {}
    env.WorldMapFrame = NewFrame(ctx, "Frame", "WorldMapFrame")
    env.WorldMapFrame.shown = false

    env.C_Map = {
        GetMapInfo = function(id)
            local m = MAPS[id]
            return m and { mapID = id, name = m.name, parentMapID = m.parent, mapType = m.type } or nil
        end,
        GetMapChildrenInfo = function(id, _, all)
            if id == 946 and w.noCosmicChildren then return {} end
            assert(all, "the walk asks for every descendant")
            return Descendants(id, {})
        end,
        GetWorldPosFromMapPos = function(id, pos)
            local at = MAPS[id] and MAPS[id].at
            if not at then return nil end
            local x, y = at[2] + pos.x * at[4], at[3] + pos.y * at[4]
            return at[1], { GetXY = function() return x, y end }
        end,
        GetBestMapForUnit = function() return w.map end,
        GetAreaInfo = function(id) return "Area " .. id end,
    }
    env.C_Item = {
        GetItemNameByID = function(id) return ctx.items[id] end,
        RequestLoadItemDataByID = function(id) ctx.requested[#ctx.requested + 1] = "item " .. id end,
    }
    env.C_Spell = {
        GetSpellName = function(id) return ctx.spells[id] end,
        RequestLoadSpellData = function(id) ctx.requested[#ctx.requested + 1] = "spell " .. id end,
    }
    env.C_CurrencyInfo = { GetCurrencyInfo = function(id) return ctx.currencies[id] and { name = ctx.currencies[id] } end }
    env.C_QuestLog = { IsQuestFlaggedCompleted = function(id) return ctx.questsDone[id] == true end }
    env.C_AddOns = {
        IsAddOnLoaded = function(name) return ctx.loaded[name] == true end,
        DoesAddOnExist = function(name) return ctx.addons[name] ~= nil end,
        -- The client answers a name it has no addon for with an error.
        GetAddOnMetadata = function(name, field)
            local meta = ctx.addons[name] or error("no addon named " .. name)
            return meta[field]
        end,
    }
    env.GetAchievementInfo = function(id) return id, ctx.achievements[id] end
    env.GetAchievementCriteriaInfo = function(a, i) return ctx.criteria[a .. "." .. i] end
    env.GetAchievementCriteriaInfoByID = function(a, id) return ctx.criteria[a .. ":" .. id] end
    env.ChatEdit_InsertLink = function(link) ctx.linked[#ctx.linked + 1] = link return true end

    if client == "retail" then
        env.issecretvalue = function() return false end
        env.C_TooltipInfo = { GetHyperlink = function(link)
            local id = tonumber(link:match("^unit:Creature%-0%-0%-0%-0%-(%d+)"))
            local name = id and ctx.npcs[id]
            return name and { lines = { { leftText = name } } } or { lines = {} }
        end }
        env.C_QuestLog.GetTitleForQuestID = function(id) return ctx.quests[id] end
        env.C_QuestLog.RequestLoadQuestByID = function(id) ctx.requested[#ctx.requested + 1] = "quest " .. id end
        env.C_Reputation = { GetFactionDataByID = function(id) return ctx.factions[id] and { name = ctx.factions[id] } end }
        env.C_Map.CanSetUserWaypointOnMap = function(id) return MAPS[id] ~= nil and MAPS[id].at ~= nil end
        env.C_Map.SetUserWaypoint = function(point) ctx.waypoints[#ctx.waypoints + 1] = point end
        env.C_SuperTrack = { SetSuperTrackedUserWaypoint = function(on) ctx.tracked = on end }
        env.UiMapPoint = { CreateFromCoordinates = function(id, x, y) return { mapID = id, x = x, y = y } end }
        env.MAP_PIN_HYPERLINK = "Map Pin Location"
    else
        env.C_QuestLog.GetQuestInfo = function(id) return ctx.quests[id] end
        env.GetFactionInfoByID = function(id) return ctx.factions[id], "", 4 end
    end
end

-- ==== EasyFind and HandyNotes ================================================

-- EasyFind's own rows: ctx.listed["name@mapID"] = npcID or true (its map
-- search's rows), ctx.creatures[npcID] = true (its creature catalog).
local function FakeAPI(ctx, opts)
    local rec = ctx.api
    local API = { VERSION = opts.apiVersion or 1, MINOR = opts.apiMinor or 7 }
    function API.RegisterExtension(def) rec.extension = def return true end
    function API.RegisterSearchProvider(def) rec.provider = def return true end
    function API.RegisterRowDecorator(def) rec.decorator = def return true end
    function API.RefreshSearchProvider(key) rec.refreshes[#rec.refreshes + 1] = key end
    function API.RefreshRowDecorations() rec.repaints = rec.repaints + 1 end
    function API.HasRow(name, mapID)
        rec.asked = rec.asked + 1
        return ctx.listed[name:lower() .. "@" .. mapID] or false
    end
    function API.HasCreature(npcID) return ctx.creatures[npcID] == true end
    function API.HasAction(id, name) return id == "gps" and name == "navigate" and ctx.world.gps end
    function API.CallAction(id, name, dest, o)
        rec.actions[#rec.actions + 1] = { id = id, name = name, dest = dest, opts = o }
        return true
    end
    return API
end

-- A plugin in the shape HandyNotes reads: GetNodes2(map) gives an
-- iterator over coord -> node for that map. A node with `continent` is
-- also shown on that map, handed back with its own map's id. `wrapped`
-- keeps the nodes under a data field, as some plugin cores do.
function Harness.Plugin(nodes, opts)
    opts = opts or {}
    local handler = { nodes = nodes, calls = 0 }
    function handler:GetNodes2(mapID)
        self.calls = self.calls + 1
        local own = nodes[mapID] or {}
        local list = {}
        for coord, node in pairs(own) do list[#list + 1] = { coord = coord, node = node } end
        for zone, zoneNodes in pairs(nodes) do
            for coord, node in pairs(zoneNodes) do
                if node.continent == mapID then list[#list + 1] = { coord = coord, map = zone, node = node } end
            end
        end
        table.sort(list, function(a, b) return a.coord < b.coord end)
        local state = {}
        for _, item in ipairs(list) do
            if not item.map then state[item.coord] = item.node end
        end
        if opts.wrapped then state = { data = state } end
        local i = 0
        local function iter()
            i = i + 1
            local item = list[i]
            if not item then return nil end
            return item.coord, item.map, item.node.icon or opts.icon
        end
        return iter, state, nil
    end
    return handler
end

function Harness.Coord(x, y)
    return math.floor(x * 10000 + 0.5) * 10000 + math.floor(y * 10000 + 0.5)
end

-- HandyNotes' options as AceConfigRegistry hands them out: names maps a
-- plugin to its name there; a names of false makes the fetch throw.
local function FakeLibStub(names)
    local reg = {}
    function reg:GetOptionsTable(app)
        if names == false then error("a plugin's options table is malformed") end
        if app ~= "HandyNotes" then return nil end
        local plugins = {}
        for plugin, name in pairs(names) do plugins[plugin] = { type = "group", name = name } end
        return { args = { plugins = { args = plugins } } }
    end
    return function(lib, silent)
        if lib == "AceConfigRegistry-3.0" then return reg end
        assert(silent, "no library " .. lib)
    end
end

local function FakeHandyNotes(ctx)
    local HN = { plugins = {}, enabled = true, notified = 0 }
    HN.db = { profile = { enabledPlugins = setmetatable({}, { __index = function() return true end }) } }
    function HN:getXY(id) return math.floor(id / 10000) / 10000, (id % 10000) / 10000 end
    function HN:IsEnabled() return self.enabled end
    function HN:UpdatePluginMap(_, pluginName) self.notified = self.notified + 1 return pluginName end
    function HN:UpdateWorldMap() self.notified = self.notified + 1 end
    ctx.loaded.HandyNotes = true
    ctx.addons.HandyNotes = { Title = "HandyNotes" }
    return HN
end

-- ==== loading ================================================================

-- opts: client ("retail" default or "classic"), gps (the GPS extension
-- installed), easyfind = false (no EasyFind), apiVersion, apiMinor,
-- handynotes = false (not loaded), bare = true (loaded without its plugin
-- list), login = false (stop before PLAYER_LOGIN), plugins = { name =
-- handler }, addons = { folder = { Title = ... } }, optionNames = { plugin =
-- its name in HandyNotes' options } (false: the fetch throws), db (saved
-- settings).
function Harness.Load(opts)
    opts = opts or {}
    local ctx = {
        now = 0, timers = {}, frames = {}, printed = {}, errors = {}, linked = {}, waypoints = {}, requested = {},
        api = { refreshes = {}, actions = {}, repaints = 0, asked = 0 }, listed = {}, creatures = {},
        world = { map = 1, shift = false, gps = opts.gps == true },
        npcs = {}, items = {}, spells = {}, quests = {}, questsDone = {}, factions = {}, currencies = {},
        achievements = {}, criteria = {}, loaded = {}, addons = {},
    }
    ctx.Fire = function(event, ...) Harness.Fire(ctx, event, ...) end
    ctx.Advance = function(seconds) Harness.Advance(ctx, seconds) end
    local env = setmetatable({}, { __index = _G })
    env._G = env
    ctx.env = env
    Game(ctx, opts.client or "retail")
    if opts.easyfind ~= false then env.EasyFind = { API = FakeAPI(ctx, opts) } end
    if opts.handynotes ~= false then
        local HN = FakeHandyNotes(ctx)
        if opts.bare then HN.plugins = nil end
        for name, handler in pairs(opts.plugins or {}) do HN.plugins[name] = handler end
        env.HandyNotes = HN
        ctx.hn = HN
    end
    for folder, meta in pairs(opts.addons or {}) do ctx.addons[folder] = meta end
    if opts.optionNames ~= nil then env.LibStub = FakeLibStub(opts.optionNames) end
    env.EasyFindHandyNotesDB = opts.db

    local ns = {}
    local _, files = Harness.Toc()
    for _, file in ipairs(files) do
        local chunk = assert(loadfile(ROOT .. "/" .. file, "t", env))
        chunk("EasyFind_HandyNotes", ns)
    end
    ctx.ns, ctx.L = ns, ns.L
    ctx.extension, ctx.provider, ctx.decorator = ctx.api.extension, ctx.api.provider, ctx.api.decorator
    if opts.login ~= false then ctx.Fire("PLAYER_LOGIN") end
    return ctx
end

-- Every frame's OnEvent hears the event.
function Harness.Fire(ctx, event, ...)
    for _, f in ipairs(ctx.frames) do
        if f.scripts.OnEvent and f.events[event] then f.scripts.OnEvent(f, event, ...) end
    end
end

-- The clock moves on; every timer due by then runs, earliest first,
-- the ones those schedule included.
function Harness.Advance(ctx, seconds)
    ctx.now = ctx.now + (seconds or 0)
    for _ = 1, 100000 do
        local due, best
        for i, t in ipairs(ctx.timers) do
            if t.at <= ctx.now and (not best or t.at < best.at or (t.at == best.at and t.seq < best.seq)) then
                due, best = i, t
            end
        end
        if not due then return end
        table.remove(ctx.timers, due).fn()
    end
    error("timers never settle")
end

-- The rows the search gets once the walk is done.
function Harness.Rows(ctx)
    ctx.provider.rows()
    ctx.Advance(0)
    return ctx.provider.rows()
end

-- The row named so, or nil.
function Harness.Row(rows, name)
    for _, row in ipairs(rows) do if row.name == name then return row end end
    return nil
end

-- A tooltip that keeps its lines.
function Harness.Tooltip()
    local tt = { lines = {} }
    function tt:SetText(text) self.lines = { text } end
    function tt:AddLine(text) self.lines[#self.lines + 1] = text end
    return tt
end

return Harness
