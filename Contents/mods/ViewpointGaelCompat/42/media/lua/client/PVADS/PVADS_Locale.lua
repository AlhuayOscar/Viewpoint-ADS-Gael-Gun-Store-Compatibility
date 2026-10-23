-- Small UI-localization helper. The language marker comes from the mod's UI translations,
-- so text follows Project Zomboid's selected language without relying on platform locale.
PVADS = PVADS or {}

local spanish = false
if getText then
    local ok, language = pcall(getText, "UI_PVADSGAEL2_Language")
    spanish = ok and language == "es"
end

function PVADS.L(english, spanishText)
    if spanish and spanishText then return spanishText end
    return english
end

