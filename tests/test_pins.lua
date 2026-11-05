-- Pins.lua against a stand-in HandyNotes: the walk over every map, pin
-- names from their text or ids (retail and classic calls), HandyNotes'
-- plugin switch, pins EasyFind lists marking its rows instead of their
-- own, the filters, a click's directions or waypoint, the chat link, the
-- tooltip, the empty scope's list and a plugin's update.
local Harness = require("Harness")
local Eq, True, Coord, Row = Harness.Eq, Harness.True, Harness.Coord, Harness.Row

local T = {}

local DUROTAR, ORGRIMMAR, CLEFT, KALIMDOR, HELLFIRE = 1, 85, 86, 12, 100

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
    Eq(chest.searchCommandDesc, "Pin: Durotar", "what it is and its zone")
    Eq(chest.icon, 1001, "the plugin's icon")
    Eq(ctx.api.asked, 5, "EasyFind asked once per pin")
    Eq(#ctx.errors, 0, "errors")
end

-- 81 plugins (a player's "script ran too long", 2026-11-05: 60 maps of
-- all 81 in one frame): a frame walks until its share of time is spent.
function T.the_walk_stops_each_frame_when_its_time_is_spent()
    local plugins, addons = {}, {}
    for i = 1, 81 do
        plugins["P" .. i] = Treasures()
        addons["HandyNotes_P" .. i] = { Title = "HandyNotes: P" .. i }
    end
    local ctx = Load({ plugins = plugins, addons = addons })
    ctx.msPerRead = 1
    local perFrame = {}
    for _, handler in pairs(plugins) do
        local read = handler.GetNodes2
        function handler:GetNodes2(...)
            perFrame[ctx.ran] = (perFrame[ctx.ran] or 0) + 1
            return read(self, ...)
        end
    end
    local rows = Harness.Rows(ctx)
    local most, frames = 0, 0
    for _, n in pairs(perFrame) do
        most, frames = math.max(most, n), frames + 1
    end
    True(most <= 4, "at most 4 plugin maps a frame, saw " .. most)
    True(frames > 1, "the walk spans frames")
    local chests = 0
    for _, row in ipairs(rows) do
        if row.name == "Sunken Chest" then chests = chests + 1 end
    end
    Eq(chests, 81, "every plugin's pins still found")
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

-- The plugin's name as its row's tooltip names it.
local function PluginLine(ctx, name)
    local tt = Harness.Tooltip()
    ctx.provider.tooltip(Row(Harness.Rows(ctx), name), tt)
    return tt.lines[#tt.lines]
end

function T.plugin_title_from_its_addon_with_prefix_and_colors_dropped()
    Eq(PluginLine(Load(), "Fel Chest"), "HandyNotes: Treasures", "title")
end

function T.plugin_title_is_its_name_in_handynotes_options_first()
    local ctx = Load({ optionNames = { Treasures = "Treasure Hunter" } })
    Eq(PluginLine(ctx, "Fel Chest"), "HandyNotes: Treasure Hunter", "title")
end

function T.plugin_title_survives_options_that_throw()
    local ctx = Load({ optionNames = false })
    Eq(PluginLine(ctx, "Fel Chest"), "HandyNotes: Treasures", "the addon's title")
    Eq(#ctx.errors, 0, "errors")
end

function T.plugin_title_never_asks_a_missing_addon()
    local ctx = Load({ addons = {}, plugins = { HandyNotes_NPCs = Treasures() } })
    Eq(PluginLine(ctx, "Fel Chest"), "HandyNotes: NPCs", "the registered name without its prefix")
    Eq(#ctx.errors, 0, "errors")
end

-- ==== found by what and where ================================================

local ELWYNN = 37

-- Its place's words are EasyFind's (any row with a numeric mapID).
function T.rows_carry_their_plugin_as_words_and_their_map()
    local chest = Row(Harness.Rows(Load()), "Sunken Chest")
    Eq(table.concat(chest.keywords, ", "), "treasures", "words")
    Eq(type(chest.mapID), "number", "a mapID EasyFind places it by")
end

local function DecorVendors()
    return Harness.Plugin({
        [ELWYNN] = { [Coord(0.4, 0.6)] = { title = "Paul North", faction = "alliance" } },
        [DUROTAR] = { [Coord(0.5, 0.4)] = { title = "Gob Hammerhand" } },
        [HELLFIRE] = { [Coord(0.3, 0.3)] = { title = "Fel Seller" } },
    })
end

function T.place_and_plugin_words_narrow_a_search()
    local ctx = Load({ plugins = { HandyNotes_DecorVendors = DecorVendors(), Treasures = Treasures() },
                       optionNames = { HandyNotes_DecorVendors = "Decor Vendors" } })
    local rows = Harness.Rows(ctx)
    Eq(Harness.Find(rows, "decor"), "Fel Seller, Gob Hammerhand, Paul North", "every decor vendor")
    Eq(Harness.Find(rows, "ek decor"), "Paul North", "the Eastern Kingdoms by its initials")
    Eq(Harness.Find(rows, "decor durotar"), "Gob Hammerhand", "a zone")
    Eq(Harness.Find(rows, "kalimdor decor"), "Gob Hammerhand", "a continent")
    Eq(Harness.Find(rows, "durotar"), "Gob Hammerhand, Gruk the Hoarder, Old Crate, Ragefire Cache, Sunken Chest",
        "everything HandyNotes marks in a zone")
end

function T.a_nodes_own_kind_is_a_word()
    local node = { name = "Faruza", category = "primaryProfession", profession = "Herbalism",
                   description = "Apprentice Herbalist", note = "A long note that is no kind at all, past forty letters." }
    local ctx = Load({ plugins = { Pin = Harness.Plugin({ [DUROTAR] = { [Coord(0.5, 0.5)] = node } }) } })
    local row = Row(Harness.Rows(ctx), "Faruza")
    Eq(table.concat(row.keywords, ", "), "pin, primary profession, herbalism, apprentice herbalist",
        "its kinds; the note left out")
    True(Harness.Matches(row, "herbalist durotar"), "found by its kind and zone")
end

-- A rare in the shape of the Forever plugin's: its name in a token with
-- its own text, its loot as ids or tables holding one.
local function Pexmit()
    return { Rares = Harness.Plugin({ [DUROTAR] = { [Coord(0.5, 0.5)] = {
        label = "{npc:266901:Pexmit}", loot = { 251468, { 252877, mount = 1 } } } } }) }
end

function T.a_rare_is_found_by_what_it_drops()
    local ctx = Load({ plugins = Pexmit() })
    ctx.items[251468], ctx.items[252877] = "Plans: Bold Dirk", "Pattern: Tooled Leather Armor"
    local rows = Harness.Rows(ctx)
    Eq(Harness.Find(rows, "bold dirk"), "Pexmit", "an item it drops")
    Eq(Harness.Find(rows, "tooled leather durotar"), "Pexmit", "with its zone")
end

function T.a_rares_tooltip_lists_its_loot()
    local ctx = Load({ plugins = Pexmit() })
    ctx.items[251468], ctx.items[252877] = "Plans: Bold Dirk", "Pattern: Tooled Leather Armor"
    local tt = Harness.Tooltip()
    ctx.provider.tooltip(Row(Harness.Rows(ctx), "Pexmit"), tt)
    Eq(table.concat(tt.lines, " | "),
        "Pexmit | Loot | Plans: Bold Dirk | Pattern: Tooled Leather Armor | Durotar  50.0, 50.0 | HandyNotes: Rares", "lines")
end

function T.loot_named_later_joins_the_words_on_the_next_build()
    local ctx = Load({ plugins = Pexmit() })
    ctx.items[251468] = "Plans: Bold Dirk"
    local rows = Harness.Rows(ctx)
    Eq(Harness.Find(rows, "tooled"), "", "not known yet")
    True(ctx.requested[#ctx.requested] == "item 252877", "asked for")
    ctx.items[252877] = "Pattern: Tooled Leather Armor"
    Eq(Harness.Find(ctx.provider.rows(), "tooled"), "Pexmit", "found once the client knows it")
end

-- ==== pins EasyFind lists ====================================================

-- Faruza by name only (a creature of EasyFind's), Grizzlin by name (a
-- service place), Gruk by its id, Rattlegore in a cellar of Orgrimmar.
local function Townsfolk()
    return Harness.Plugin({
        [DUROTAR] = {
            [Coord(0.6, 0.5)] = { name = "Faruza", description = "Apprentice Herbalist" },
            [Coord(0.7, 0.1)] = { npcID = 3100, name = "Gruk the Hoarder" },
            [Coord(0.2, 0.2)] = { name = "Sunken Chest" },
        },
        [ORGRIMMAR] = { [Coord(0.4, 0.6)] = { name = "Auctioneer Grizzlin", note = "{item:2589:Cloth} buyer" } },
        [CLEFT] = { [Coord(0.5, 0.5)] = { name = "Rattlegore" } },
    })
end

local function Listed(opts)
    opts = opts or {}
    opts.plugins = { NPCs = Townsfolk() }
    local ctx = Load(opts)
    ctx.listed["faruza@1"] = 3200
    ctx.listed["auctioneer grizzlin@85"] = true
    ctx.listed["rattlegore@86"] = true
    ctx.creatures[3100] = true
    return ctx
end

local function Applies(ctx, row)
    return ctx.decorator.applies(row) == true
end

function T.pins_easyfind_lists_are_no_rows_of_ours()
    local ctx = Listed()
    Eq(Names(Harness.Rows(ctx)), "Sunken Chest", "only the pin EasyFind has no row for")
end

function T.easyfinds_rows_for_them_carry_handynotes()
    local ctx = Listed()
    Harness.Rows(ctx)
    True(Applies(ctx, { name = "Faruza", category = "npc", npcID = 3200, mapID = DUROTAR, mapSearchResult = true }),
        "a creature found by name, matched by its id")
    True(Applies(ctx, { name = "Gruk the Hoarder", category = "npc", npcID = 3100, mapID = KALIMDOR }),
        "a creature the pin names by id, wherever EasyFind places it")
    True(Applies(ctx, { name = "Auctioneer Grizzlin", category = "vendor", mapID = ORGRIMMAR, mapSearchResult = true }),
        "a service place by name in its zone")
    True(Applies(ctx, { name = "Rattlegore", category = "vendor", mapID = ORGRIMMAR, mapSearchResult = true }),
        "a pin in a cellar matches the zone above it")
end

function T.easyfinds_other_rows_are_left_alone()
    local ctx = Listed()
    Harness.Rows(ctx)
    True(not Applies(ctx, { name = "Auctioneer Grizzlin", mapID = HELLFIRE, mapSearchResult = true }), "same name, another zone")
    True(not Applies(ctx, { name = "Auctioneer Grizzlin", itemID = 2589 }), "an item row")
    True(not Applies(ctx, { name = "Sunken Chest", mapID = DUROTAR, mapSearchResult = true }), "a pin that is a row of ours")
    True(not Applies(ctx, { name = "Thrall", npcID = 4949, mapID = ORGRIMMAR }), "a creature no pin names")
end

local function DecorLines(ctx, row)
    local tt = Harness.Tooltip()
    ctx.decorator.tooltip(row, nil, tt)
    return table.concat(tt.lines, " | ")
end

-- EasyFind's row already says what and where; it gains only what the
-- pin knows that the row does not.
function T.easyfinds_row_gains_no_tag_and_nothing_it_already_knows()
    local ctx = Listed()
    Harness.Rows(ctx)
    Eq(ctx.decorator.subtext, nil, "no subtext of ours")
    local faruza = { name = "Faruza", category = "npc", npcID = 3200, mapID = DUROTAR, mapSearchResult = true,
                     keywords = { "Apprentice Herbalist", "herbalism" } }
    Eq(DecorLines(ctx, faruza), "", "her title is EasyFind's already: no lines")
end

function T.easyfinds_row_gains_the_pins_loot()
    local ctx = Load({ plugins = Pexmit() })
    ctx.listed["pexmit@1"] = 266901
    ctx.items[251468], ctx.items[252877] = "Plans: Bold Dirk", "Pattern: Tooled Leather Armor"
    Harness.Rows(ctx)
    Eq(DecorLines(ctx, { name = "Pexmit", npcID = 266901, mapID = DUROTAR, mapSearchResult = true }),
        "HandyNotes: Rares | Loot | Plans: Bold Dirk | Pattern: Tooled Leather Armor", "what it drops")
end

function T.easyfinds_row_gains_the_pins_own_note()
    local ctx = Listed()
    Harness.Rows(ctx)
    Eq(DecorLines(ctx, { name = "Faruza", npcID = 3200, mapID = DUROTAR, mapSearchResult = true }),
        "HandyNotes: NPCs | Apprentice Herbalist", "a note the row lacks, under the plugin's name")
    Eq(DecorLines(ctx, { name = "Auctioneer Grizzlin", mapID = ORGRIMMAR, mapSearchResult = true }),
        "HandyNotes: NPCs | Cloth buyer", "a note's tokens rendered")
end

function T.the_first_row_painted_starts_the_walk_and_repaints_after()
    local ctx = Listed()
    local row = { name = "Faruza", npcID = 3200, mapID = DUROTAR, mapSearchResult = true }
    True(not Applies(ctx, row), "nothing known before the walk")
    local before = ctx.api.repaints
    ctx.Advance(0)
    True(ctx.api.repaints > before, "EasyFind's rows repainted once the walk is done")
    True(Applies(ctx, row), "the row carries HandyNotes then")
end

-- @hn lists EasyFind's rows the decorator takes beside our own: EasyFind
-- finds them by these fields before asking applies.
function T.the_decorator_names_the_rows_it_takes_by_id_and_name()
    local ctx = Listed()
    Harness.Rows(ctx)
    local c = ctx.decorator.candidates()
    True(c.npcID[3200] and c.npcID[3100], "creatures by id")
    True(c.name["faruza"][DUROTAR], "a creature by name on its map")
    True(c.name["auctioneer grizzlin"][ORGRIMMAR], "a service place by name, no id")
    True(c.name["rattlegore"][CLEFT], "on the cellar's own map; EasyFind matches its zone")
    Eq(c.name["sunken chest"], nil, "a pin of ours is no candidate")
end

-- "decor" finds the decor vendors EasyFind lists: the pins' words on the
-- rows they mark, a creature by id, a place by name@map.
function T.easyfinds_rows_take_the_pins_words()
    local ctx = Listed({ optionNames = { NPCs = "Townsfolk" } })
    Harness.Rows(ctx)
    local w = ctx.decorator.words()
    Eq(table.concat(w.npc[3200], ", "), "townsfolk, apprentice herbalist", "Faruza by her id")
    Eq(table.concat(w.npc[3100], ", "), "townsfolk", "Gruk by his")
    Eq(table.concat(w.name["auctioneer grizzlin@85"], ", "), "townsfolk", "a place by name on its map")
    True(w.name["rattlegore@86"] ~= nil, "on its own map; EasyFind matches the zone")
    Eq(w.name["sunken chest@1"], nil, "a pin of ours keeps its words on its own row")
    local faruza = { name = "Faruza", npcID = 3200, mapID = DUROTAR, keywords = w.npc[3200] }
    True(Harness.Matches(faruza, "townsfolk durotar"), "found by the plugin and her zone")
end

-- A rare pin with only its creature's id (the client may never send our
-- tooltip scan its name): EasyFind's row has the name, so it marks it.
function T.a_pin_of_only_a_creature_id_marks_easyfinds_row_without_a_name()
    local ctx = Load({ plugins = { Rares = Harness.Plugin({ [DUROTAR] = { [Coord(0.4, 0.4)] = { npc = 9999 } } }) } })
    ctx.creatures[9999] = true
    Eq(#Harness.Rows(ctx), 0, "no row of ours")
    ctx.Advance(10)
    True(Applies(ctx, { name = "Grizzleback", npcID = 9999, mapID = DUROTAR }), "EasyFind's row marked")
    True(ctx.decorator.candidates().npcID[9999], "named for @hn")
    Eq(table.concat(ctx.decorator.words().npc[9999], ", "), "rares", "its words")
    Eq(#ctx.provider.rows(), 0, "still no row of ours once the tries are done")
end

function T.the_empty_scope_lists_easyfinds_rows_on_the_players_map()
    local ctx = Listed()
    ctx.world.map = ORGRIMMAR
    Harness.Rows(ctx)
    True(ctx.decorator.browse({ name = "Auctioneer Grizzlin", mapID = ORGRIMMAR }), "here")
    True(not ctx.decorator.browse({ name = "Fel Seller", mapID = HELLFIRE }), "elsewhere")
end

function T.pins_are_walked_soon_after_login_before_any_search()
    local ctx = Listed()
    ctx.Advance(3)
    True(Applies(ctx, { name = "Faruza", npcID = 3200, mapID = DUROTAR, mapSearchResult = true }), "EasyFind's row marked")
    local walked = ctx.hn.plugins.NPCs.calls
    True(walked > 0, "walked")
    Eq(Names(ctx.provider.rows()), "Sunken Chest", "the first search has the rows")
    ctx.Advance(10)
    Eq(ctx.hn.plugins.NPCs.calls, walked, "no second walk")
end

function T.a_plugins_update_moves_its_pins_out_of_easyfinds_rows()
    local ctx = Listed()
    local row = { name = "Faruza", npcID = 3200, mapID = DUROTAR, mapSearchResult = true }
    Harness.Rows(ctx)
    True(Applies(ctx, row), "before")
    ctx.hn.plugins.NPCs.nodes[DUROTAR][Coord(0.6, 0.5)] = nil
    ctx.hn:UpdatePluginMap("HandyNotes_NotifyUpdate", "NPCs")
    ctx.Advance(3)
    True(not Applies(ctx, row), "the removed pin marks nothing")
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

function T.a_pins_art_cut_from_a_sheet_keeps_its_coords()
    local cut = { icon = 2002, tCoordLeft = 0.25, tCoordRight = 0.5, tCoordTop = 0, tCoordBottom = 0.25 }
    local ctx = Load({ gps = true, plugins = OnePin({ label = "Cut", icon = cut }) })
    local row = Row(Harness.Rows(ctx), "Cut")
    Eq(row.icon.file, 2002, "the sheet")
    Eq(table.concat(row.icon.coords, ","), "0.25,0.5,0,0.25", "its cut")
    ctx.provider.select(row)
    Eq(ctx.api.actions[1].dest.icon, nil, "no whole sheet at the route's end")
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
    Eq(table.concat(tt.lines, " | "), "Sunken Chest | Under the pier. | Durotar  50.0, 50.0 | HandyNotes: Treasures", "lines")
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
