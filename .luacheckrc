std = "lua51"
max_line_length = false

-- Standard WoW addon patterns, not real issues.
ignore = {
    "431",  -- shadowing upvalue
    "432",  -- shadowing upvalue argument
}

-- Globals this addon sets
globals = {
    "EasyFindHandyNotesDB",
}

-- WoW API and the addons it reads (read-only)
read_globals = {
    "EasyFind",
    "C_AddOns", "C_CurrencyInfo", "C_Item", "C_Map", "C_PetJournal", "C_QuestLog", "C_Reputation", "C_Spell",
    "C_SuperTrack", "C_Timer", "C_TooltipInfo", "IsAddOnLoaded",
    "ChatEdit_GetActiveWindow", "ChatEdit_InsertLink", "ChatFrame_OpenChat",
    "CreateFrame", "CreateVector2D", "Enum", "LibStub", "UiMapPoint", "WorldFrame", "WorldMapFrame",
    "GetAchievementCriteriaInfo", "GetAchievementCriteriaInfoByID", "GetAchievementInfo", "GetFactionInfoByID",
    "GetTime", "IsShiftKeyDown", "issecretvalue",
    "MAP_PIN_HYPERLINK", "UNKNOWNOBJECT",
    "debugprofilestop", "debugstack", "geterrorhandler", "hooksecurefunc", "wipe",
}

-- WoW callbacks have fixed signatures; unused args are normal
unused_args = false
self = false

-- The tests run on the lua in PATH (5.4) and stand in for the game's globals.
files["tests"] = { std = "max", ignore = { "111", "112", "113", "121", "122", "143" } }
