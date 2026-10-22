local _, ns = ...

-- Every string the player sees. Other locales override keys in files of
-- their own; a missing key falls back to this one.
local L = setmetatable({}, { __index = function(_, k) return k end })
ns.L = L

L["EXT_NAME"] = "HandyNotes"
L["EXT_DESC"] = "HandyNotes' map pins, found by name."
L["PROVIDER_LABEL"] = "Map pins"
L["SETTINGS_HINT"] = "Which pins the search shows. Type a pin's name in EasyFind to find it."

L["OPT_HIDE_DONE"] = "Hide done"
L["OPT_HIDE_DONE_TIP"] = "Leave out pins their plugin marks complete or collected."
L["OPT_NEAR_ME"] = "Near me"
L["OPT_NEAR_ME_TIP"] = "Only pins on the map you are on."

L["HINT_GPS"] = "GPS to the pin"
L["HINT_LINK"] = "Link in chat"
L["STEP_PIN"] = "Travel to the pin"
L["FROM_FMT"] = "%s, %s"

L["NO_PLACE"] = "No known place for %s."
L["NOT_READY"] = "HandyNotes' plugin list is not available in this version, so pin search is off."
