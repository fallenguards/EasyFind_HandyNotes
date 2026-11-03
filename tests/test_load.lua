-- The addon loaded offline: what it registers with EasyFind's API (MINOR 6),
-- and that it stays silent or says why when EasyFind or HandyNotes is
-- missing, too old or incomplete.
local Harness = require("Harness")
local Eq, True = Harness.Eq, Harness.True

local T = {}

function T.toc_loads_beside_handynotes_and_requires_only_easyfind()
    local fields = Harness.Toc()
    Eq(fields.Dependencies, "EasyFind", "Dependencies")
    Eq(fields.OptionalDeps, "HandyNotes", "OptionalDeps")
    Eq(fields.LoadWith, nil, "LoadWith")
    Eq(fields.RequiredDeps, nil, "RequiredDeps")
end

-- HandyNotes' own clients: retail, Mists, TBC Anniversary, WoW Forever
-- (from HandyNotes 1.6.32), Era.
function T.toc_lists_every_client_handynotes_runs_on()
    local fields = Harness.Toc()
    local listed = {}
    for n in fields.Interface:gmatch("%d+") do listed[tonumber(n)] = true end
    for _, n in ipairs({ 120105, 50504, 20506, 16001, 11509 }) do True(listed[n], "Interface lists " .. n) end
end

function T.toc_files_all_exist()
    local _, files = Harness.Toc()
    True(#files >= 2, "the toc lists its files")
    for _, file in ipairs(files) do True(io.open(Harness.ROOT .. "/" .. file) ~= nil, file .. " exists") end
end

function T.registers_the_extension_with_known_fields()
    local ctx = Harness.Load()
    local ext = ctx.extension
    True(ext ~= nil, "the extension is registered")
    Eq(Harness.FieldErrors(ext, Harness.EXTENSION_FIELDS), "", "extension fields")
    Eq(ext.id, "handynotes", "id")
    True(type(ext.name) == "string" and ext.icon ~= nil, "name and icon")
    Eq(ext.scope, "handynotes", "its surface is its scope")
end

function T.registers_the_provider_with_known_fields()
    local ctx = Harness.Load()
    local p = ctx.provider
    True(p ~= nil, "the provider is registered")
    Eq(Harness.FieldErrors(p, Harness.PROVIDER_FIELDS), "", "provider fields")
    Eq(p.key, "handynotes", "key")
    Eq(p.extension, "handynotes", "under its extension")
    True(type(p.label) == "string", "label")
    for _, fn in ipairs({ "rows", "select", "tooltip", "place", "browse" }) do
        Eq(type(p[fn]), "function", fn)
    end
    for _, o in ipairs(p.options) do
        True(type(o.label) == "string" and type(o.get) == "function" and type(o.set) == "function", "option " .. tostring(o.label))
    end
end

-- A pin is found by typing its name: never only behind @hn, a pin word or
-- the filter.
function T.pins_are_searched_from_the_first_keystroke()
    local p = Harness.Load().provider
    Eq(p.eager, true, "eager")
    Eq(p.lazy, nil, "lazy")
end

function T.registers_the_row_decorator_with_known_fields()
    local ctx = Harness.Load()
    local d = ctx.decorator
    True(d ~= nil, "the decorator is registered")
    Eq(Harness.FieldErrors(d, Harness.DECORATOR_FIELDS), "", "decorator fields")
    Eq(d.id, "handynotes", "under its extension")
    for _, fn in ipairs({ "applies", "tooltip" }) do Eq(type(d[fn]), "function", fn) end
end

function T.an_easyfind_without_hasrow_registers_nothing_and_says_why()
    local ctx = Harness.Load({ apiMinor = 5 })
    Eq(ctx.extension, nil, "extension")
    Eq(ctx.provider, nil, "provider")
    Eq(ctx.decorator, nil, "decorator")
    Eq(#ctx.printed, 1, "lines in chat")
    True(ctx.printed[1]:find(ctx.L["NEEDS_NEWER"], 1, true) ~= nil, "says EasyFind needs an update")
    ctx.Fire("PLAYER_LOGIN")
    Eq(#ctx.printed, 1, "once")
end

function T.no_easyfind_loads_nothing_and_says_nothing()
    local ctx = Harness.Load({ easyfind = false })
    Eq(ctx.extension, nil, "extension")
    Eq(#ctx.printed, 0, "lines in chat")
end

function T.another_api_version_loads_nothing()
    local ctx = Harness.Load({ apiVersion = 2 })
    Eq(ctx.extension, nil, "extension")
    Eq(ctx.provider, nil, "provider")
end

function T.no_handynotes_loads_nothing_and_says_nothing()
    local ctx = Harness.Load({ handynotes = false })
    Eq(ctx.extension, nil, "extension")
    Eq(ctx.provider, nil, "provider")
    Eq(#ctx.printed, 0, "lines in chat")
    Eq(#ctx.frames, 1, "frames made (the game's world map only)")
end

function T.handynotes_without_its_plugin_list_says_so_once()
    local ctx = Harness.Load({ bare = true })
    Eq(#ctx.printed, 1, "lines in chat")
    True(ctx.printed[1]:find(ctx.L["NOT_READY"], 1, true) ~= nil, "says pin search is off")
    Eq(#ctx.provider.rows(), 0, "no rows")
    ctx.Advance(10)
    Eq(#ctx.errors, 0, "errors")
end

function T.rows_wait_for_login()
    local ctx = Harness.Load({ login = false, plugins = { Treasures = Harness.Plugin({ [1] = { [Harness.Coord(0.5, 0.5)] = { label = "Chest" } } }) } })
    Eq(#ctx.provider.rows(), 0, "no rows before login")
    ctx.Fire("PLAYER_LOGIN")
    Eq(#Harness.Rows(ctx), 1, "rows after login")
end

function T.settings_page_builds_with_the_kit()
    local ctx = Harness.Load()
    local made = {}
    local function Control()
        return { SetPoint = function(self, ...) self.point = { ... } end }
    end
    local kit = {
        Title = function(_, title) made[#made + 1] = "title " .. title return Control() end,
        Checkbox = function(_, label, get, set, tooltip)
            True(type(get) == "function" and type(set) == "function" and type(tooltip) == "string", "checkbox " .. label)
            made[#made + 1] = "check " .. label
            return Control()
        end,
    }
    ctx.extension.settings({}, kit)
    Eq(#made, 1 + #ctx.provider.options, "a title and one switch per option")
end

function T.reset_to_default_clears_the_settings()
    local ctx = Harness.Load({ db = { hideDone = true, nearMe = true } })
    True(ctx.provider.options[1].get(), "Hide done starts on")
    ctx.extension.resetSettings()
    for _, o in ipairs(ctx.provider.options) do Eq(o.get(), false, o.label .. " after reset") end
    Eq(next(ctx.env.EasyFindHandyNotesDB), nil, "nothing saved")
end

-- Every key a string the addon reads is in the English locale.
function T.every_locale_key_used_is_defined()
    local ctx = Harness.Load()
    local text = Harness.Read("Pins.lua")
    local L = ctx.L
    for key in text:gmatch('L%["([%w_]+)"%]') do
        True(rawget(L, key) ~= nil, "L." .. key .. " is defined")
    end
end

return T
