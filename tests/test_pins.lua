-- Pins.lua against a stand-in HandyNotes: the walk over every map, pin
-- names from their text or ids (retail and classic calls), HandyNotes'
-- plugin switch, the filters, a click's directions or waypoint, the chat
-- link, the tooltip, the empty scope's list and a plugin's update.
local Harness = require("Harness")
local Eq, True, Coord, Row = Harness.Eq, Harness.True, Harness.Coord, Harness.Row

local T = {}

local DUROTAR, ORGRIMMAR, KALIMDOR, HELLFIRE = 1, 85, 12, 100

-- Treasures: three pins in Durotar (one also drawn on Kalimdor), one in
-- Orgrimmar, one in Hellfire Peninsula.
local function Treasures(opts)
    return Harness.Plugin({
        [DUROTAR] = {
            [Coord(0.5, 0.5)] = { label = "Sunken Chest", note = "Under the pier.", continent = KALIMDOR, icon = 1001 },
            [Coord(0.2, 0.3)] = { label = "|cffff0000Old|r Crate", quest = 501 },
            [Coord(0.7, 0.1)] = { npc = 3100 },
        },
        [ORGRIMMAR] = { [Coord(0.4, 0.6)] = { label = "Ragefire Cache" } },
        [HELLFIRE] = { [Coord(0.3, 0.3)] = { label = "Fel Chest", icon = "Interface\\Icons\\chest" } },
    }, opts)
end

local function Load(opts)
    opts = opts or {}
    opts.plugins = opts.plugins or { Treasures = Treasures() }
    opts.addons = opts.addons or { HandyNotes_Treasures = { Title = "HandyNotes: |cffffd200Treasures|r" } }
    local ctx = Harness.Load(opts)
    ctx.npcs[3100] = "Gruk the Hoarder"
    return ctx
end

local function Names(rows)
    local out = {}
    for i, row in ipairs(rows) do out[i] = row.name end
    return table.concat(out, ", ")
end

function T.rows_are_every_plugins_pins_by_name()
    local ctx = Load()
    local rows = Harness.Rows(ctx)
    Eq(Names(rows), "Fel Chest, Gruk the Hoarder, Old Crate, Ragefire Cache, Sunken Chest", "rows")
    local chest = Row(rows, "Sunken Chest")
    Eq(chest.mapID, DUROTAR, "a pin's row is on its own map, not the continent's")
    Eq(chest.searchCommandDesc, "Durotar, Treasures", "zone and plugin title, the HandyNotes prefix and colors dropped")
    Eq(chest.icon, 1001, "the plugin's icon")
    Eq(#ctx.errors, 0, "errors")
end

function T.the_walk_reaches_maps_under_azeroth_when_cosmic_lists_none()
    local ctx = Load()
    ctx.world.noCosmicChildren = true
    local rows = Harness.Rows(ctx)
    True(Row(rows, "Sunken Chest") ~= nil, "Durotar walked from Azeroth")
    Eq(Row(rows, "Fel Chest"), nil, "Outland sits under Cosmic only")
end

function T.a_plugin_core_with_wrapped_nodes_is_read_too()
    local ctx = Load({ plugins = { Treasures = Treasures({ wrapped = true }) } })
    Eq(#Harness.Rows(ctx), 5, "rows")
end

function T.the_same_pin_on_two_maps_is_one_row()
    local both = Harness.Plugin({
        [DUROTAR] = { [Coord(0.5, 0.5)] = { label = "Twin Chest" } },
        -- Kalimdor's own copy at the same spot in the world.
        [KALIMDOR] = { [Coord(0.15, 0.15)] = { label = "Twin Chest" } },
    })
    local ctx = Load({ plugins = { Twins = both } })
    Eq(Names(Harness.Rows(ctx)), "Twin Chest", "rows")
end

function T.handynotes_plugin_switch_hides_its_pins()
    local ctx = Load({ plugins = { Treasures = Treasures(), Rares = Harness.Plugin({ [DUROTAR] = { [Coord(0.1, 0.1)] = { label = "Rare" } } }) } })
    ctx.hn.db.profile.enabledPlugins.Treasures = false
    Eq(Names(Harness.Rows(ctx)), "Rare", "only the switched-on plugin")
end

function T.handynotes_turned_off_shows_no_rows()
    local ctx = Load()
    ctx.hn.enabled = false
    Eq(#Harness.Rows(ctx), 0, "rows")
end

function T.plugin_title_never_asks_a_missing_addon()
    local ctx = Load({ addons = {} })
    local rows = Harness.Rows(ctx)
    Eq(Row(rows, "Fel Chest").searchCommandDesc, "Hellfire Peninsula, Treasures", "the plugin's own name")
    Eq(#ctx.errors, 0, "errors")
end

-- ==== names ==================================================================

local function OnePin(node)
    return { Pin = Harness.Plugin({ [DUROTAR] = { [Coord(0.5, 0.5)] = node } }) }
end

function T.label_tokens_become_names_on_retail()
    local ctx = Load({ plugins = OnePin({ label = "{npc:44}: {quest:7}, {faction:72}, {spell:9}, {map:85}" }) })
    ctx.npcs[44], ctx.quests[7], ctx.factions[72], ctx.spells[9] = "Thrall", "Hidden Enemies", "Stormwind", "Hearth"
    Eq(Names(Harness.Rows(ctx)), "Thrall: Hidden Enemies, Stormwind, Hearth, Orgrimmar", "rendered")
end

function T.label_tokens_become_names_on_classic()
    local ctx = Load({ client = "classic", plugins = OnePin({ label = "{npc:44} for {quest:7} ({faction:72})" }) })
    ctx.npcs[44], ctx.quests[7], ctx.factions[72] = "Thrall", "Hidden Enemies", "Stormwind"
    Eq(Names(Harness.Rows(ctx)), "Thrall for Hidden Enemies (Stormwind)", "rendered")
    True((ctx.scans or 0) > 0, "the NPC's name came from the hidden tooltip")
end

function T.an_npc_pin_without_text_is_named_on_classic()
    local ctx = Load({ client = "classic", plugins = OnePin({ npc = 3100 }) })
    Eq(Names(Harness.Rows(ctx)), "Gruk the Hoarder", "rows")
end

function T.a_name_not_yet_sent_arrives_later()
    local ctx = Load({ plugins = OnePin({ label = "Loot: {item:2589}" }) })
    Eq(#Harness.Rows(ctx), 0, "no row while the item's name is unknown")
    True(ctx.requested[1] == "item 2589", "the item's data is asked for")
    ctx.items[2589] = "Linen Cloth"
    local before = #ctx.api.refreshes
    ctx.Advance(2)
    True(#ctx.api.refreshes > before, "the rows are rebuilt")
    Eq(Names(ctx.provider.rows()), "Loot: Linen Cloth", "rows")
end

function T.a_name_never_sent_lists_the_known_part_on_the_last_try()
    local ctx = Load({ plugins = OnePin({ label = "Loot: {item:2589}" }) })
    Harness.Rows(ctx)
    ctx.Advance(2)
    ctx.Advance(2)
    Eq(#ctx.provider.rows(), 0, "still waiting after two tries")
    ctx.Advance(2)
    Eq(Names(ctx.provider.rows()), "Loot:", "listed on the third")
end

function T.a_label_of_only_an_unknown_token_is_no_empty_row()
    local ctx = Load({ plugins = OnePin({ label = "{npc:999}" }) })
    Harness.Rows(ctx)
    ctx.Advance(10)
    Eq(#ctx.provider.rows(), 0, "rows")
end

function T.another_plugins_walk_keeps_a_plugins_waiting_pins()
    local other = { [DUROTAR] = { [Coord(0.3, 0.3)] = { label = "Other" } } }
    local ctx = Load({ plugins = { Pin = OnePin({ label = "Loot: {item:2589}" }).Pin, Other = Harness.Plugin(other) } })
    Harness.Rows(ctx)
    ctx.hn:UpdatePluginMap("HandyNotes_NotifyUpdate", "Other")
    ctx.items[2589] = "Linen Cloth"
    ctx.Advance(3)
    Eq(Names(ctx.provider.rows()), "Loot: Linen Cloth, Other", "rows")
end

function T.token_with_its_own_text_keeps_it_while_unknown()
    local ctx = Load({ plugins = OnePin({ label = "{item:2589:Cloth} and {item:text}" }) })
    Eq(Names(Harness.Rows(ctx)), "Cloth and text", "rows")
end

function T.pins_are_named_from_their_ids()
    local ctx = Load({ plugins = { Pin = Harness.Plugin({ [DUROTAR] = {
        [Coord(0.1, 0.1)] = { achievement = 10, criteria = 2 },
        [Coord(0.2, 0.2)] = { loot = { { id = 2589 } } },
        [Coord(0.3, 0.3)] = { achievement = 11 },
        [Coord(0.4, 0.4)] = { currency = 1220 },
    } }) } })
    ctx.criteria["10.2"], ctx.items[2589], ctx.achievements[11], ctx.currencies[1220] = "Find the egg", "Linen Cloth", "Explorer", "Resources"
    Eq(Names(Harness.Rows(ctx)), "Explorer, Find the egg, Linen Cloth, Resources", "rows")
end

-- ==== filters ================================================================

local function Option(ctx, key)
    return ctx.provider.options[key == "hideDone" and 1 or 2]
end

function T.hide_done_leaves_out_completed_pins()
    local ctx = Load()
    ctx.questsDone[501] = true
    Harness.Rows(ctx)
    Option(ctx, "hideDone").set(true)
    Eq(Row(ctx.provider.rows(), "Old Crate"), nil, "the done crate is gone")
    Option(ctx, "hideDone").set(false)
    True(Row(ctx.provider.rows(), "Old Crate") ~= nil, "back once the switch is off")
end

function T.near_me_keeps_the_players_map_and_watches_the_zone()
    local ctx = Load()
    Harness.Rows(ctx)
    Option(ctx, "nearMe").set(true)
    Eq(Names(ctx.provider.rows()), "Gruk the Hoarder, Old Crate, Sunken Chest", "Durotar's pins")
    local watching = false
    for _, f in ipairs(ctx.frames) do watching = watching or f.events.ZONE_CHANGED_NEW_AREA == true end
    True(watching, "the zone change is heard while Near me is on")
    ctx.world.map = ORGRIMMAR
    local before = #ctx.api.refreshes
    ctx.Fire("ZONE_CHANGED_NEW_AREA")
    Eq(#ctx.api.refreshes, before + 1, "a zone change rebuilds the rows")
    Eq(Names(ctx.provider.rows()), "Ragefire Cache", "Orgrimmar's pins")
end

function T.browse_lists_the_players_map_and_its_parent()
    local ctx = Load()
    ctx.world.map = ORGRIMMAR
    local rows = Harness.Rows(ctx)
    local listed = {}
    for _, row in ipairs(rows) do if ctx.provider.browse(row) then listed[#listed + 1] = row end end
    Eq(Names(listed), "Gruk the Hoarder, Old Crate, Ragefire Cache, Sunken Chest", "Orgrimmar's and Durotar's pins")
end

-- ==== clicks =================================================================

function T.click_asks_the_gps_with_the_pins_icon()
    local ctx = Load({ gps = true })
    ctx.provider.select(Row(Harness.Rows(ctx), "Sunken Chest"))
    local action = ctx.api.actions[1]
    True(action ~= nil and action.id == "gps" and action.name == "navigate", "GPS navigate")
    Eq(action.dest.mapID, DUROTAR, "map")
    Eq(action.dest.x, 0.5, "x")
    Eq(action.dest.icon, 1001, "the pin's icon ends the route")
    Eq(action.dest.step, ctx.L["STEP_PIN"], "the last step's sentence")
    True(action.opts and action.opts.popout, "in the GPS window")
end

function T.place_is_where_the_click_goes()
    local ctx = Load()
    local dest = ctx.provider.place(Row(Harness.Rows(ctx), "Fel Chest"))
    Eq(dest.mapID, HELLFIRE, "map")
    Eq(dest.name, "Fel Chest", "name")
    Eq(dest.icon, "Interface\\Icons\\chest", "icon")
end

function T.without_gps_retail_sets_the_games_waypoint()
    local ctx = Load()
    ctx.provider.select(Row(Harness.Rows(ctx), "Ragefire Cache"))
    Eq(#ctx.waypoints, 1, "waypoints")
    Eq(ctx.waypoints[1].mapID, ORGRIMMAR, "on the pin's map")
    Eq(ctx.tracked, true, "and tracked")
end

function T.without_gps_the_waypoint_waits_for_the_world_map()
    local ctx = Load()
    local map = ctx.env.WorldMapFrame
    map.shown = true
    local rows = Harness.Rows(ctx)
    ctx.provider.select(Row(rows, "Ragefire Cache"))
    ctx.provider.select(Row(rows, "Sunken Chest"))
    Eq(#ctx.waypoints, 0, "nothing set under the open map")
    map:Hide()
    Eq(#ctx.waypoints, 1, "one waypoint once it closes")
    Eq(ctx.waypoints[1].mapID, DUROTAR, "the last pin picked")
    map.shown = true
    map:Hide()
    Eq(#ctx.waypoints, 1, "the wait runs once")
end

function T.without_gps_classic_says_directions_need_it()
    local ctx = Load({ client = "classic" })
    ctx.provider.select(Row(Harness.Rows(ctx), "Ragefire Cache"))
    Eq(#ctx.waypoints, 0, "waypoints")
    True(ctx.printed[1] and ctx.printed[1]:find(ctx.L["NEEDS_GPS"], 1, true), "says the GPS gives directions")
end

function T.shift_click_links_the_map_pin_on_retail()
    local ctx = Load({ gps = true })
    ctx.world.shift = true
    ctx.provider.select(Row(Harness.Rows(ctx), "Old Crate"))
    Eq(ctx.linked[1], "|cffffff00|Hworldmap:1:2000:3000|h[Map Pin Location]|h|r", "the game's map pin link")
    Eq(#ctx.api.actions, 0, "no directions")
    Eq(ctx.provider.hint.shift, ctx.L["HINT_LINK"], "the hint names it")
end

function T.shift_click_on_classic_gives_directions()
    local ctx = Load({ client = "classic", gps = true })
    ctx.world.shift = true
    ctx.provider.select(Row(Harness.Rows(ctx), "Old Crate"))
    Eq(#ctx.linked, 0, "no map pin link where the client reads none")
    Eq(#ctx.api.actions, 1, "directions")
    Eq(ctx.provider.hint.shift, nil, "no Shift in the hint")
end

-- ==== tooltip ================================================================

function T.tooltip_shows_name_note_place_and_plugin()
    local ctx = Load()
    local tt = Harness.Tooltip()
    True(ctx.provider.tooltip(Row(Harness.Rows(ctx), "Sunken Chest"), tt), "shown")
    Eq(table.concat(tt.lines, " | "), "Sunken Chest | Under the pier. | Durotar  50.0, 50.0 | Treasures", "lines")
end

function T.tooltip_uses_the_plugins_own_render()
    local node = { label = "Chest" }
    function node:Render(tt) tt:SetText("Chest (plugin)") end
    local ctx = Load({ plugins = OnePin(node) })
    local tt = Harness.Tooltip()
    ctx.provider.tooltip(Row(Harness.Rows(ctx), "Chest"), tt)
    Eq(tt.lines[1], "Chest (plugin)", "the plugin's lines first")
end

-- ==== updates ================================================================

function T.a_plugins_update_walks_it_again()
    local nodes = { [DUROTAR] = { [Coord(0.1, 0.1)] = { label = "First" } } }
    local ctx = Load({ plugins = { Pin = Harness.Plugin(nodes) } })
    Eq(Names(Harness.Rows(ctx)), "First", "rows")
    nodes[DUROTAR][Coord(0.2, 0.2)] = { label = "Second" }
    ctx.hn:UpdatePluginMap("HandyNotes_NotifyUpdate", "Pin")
    ctx.hn:UpdatePluginMap("HandyNotes_NotifyUpdate", "Pin")
    ctx.Advance(3)
    Eq(Names(ctx.provider.rows()), "First, Second", "the new pin after the wait")
end

function T.handynotes_redrawing_walks_every_plugin_again()
    local nodes = { [DUROTAR] = { [Coord(0.1, 0.1)] = { label = "First" } } }
    local ctx = Load({ plugins = { Pin = Harness.Plugin(nodes) } })
    Harness.Rows(ctx)
    nodes[DUROTAR][Coord(0.1, 0.1)] = nil
    ctx.hn:UpdateWorldMap()
    ctx.Advance(3)
    Eq(#ctx.provider.rows(), 0, "the removed pin is gone")
end

return T
