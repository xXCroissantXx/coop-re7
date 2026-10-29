-- coop_saveguard.lua: blocks every save request while testing, so the test copy
-- never writes to the Steam save slots it shares with the real install.
-- Log: <game>/reframework/data/coop_saveguard_log.txt

local BLOCK = {
    "saveFileAutoRequest",
    "saveFileMenuRequest",
    "saveFileSystemDataRequest",
    "saveFileExpansionDataRequest",
    "saveFileBirthdayDataRequest",
    "saveFileUniqueDataRequest",
}

local lines = {}
local function log_line(s)
    lines[#lines + 1] = os.date("%H:%M:%S ") .. s
    fs.write("coop_saveguard_log.txt", table.concat(lines, "\n"))
end

local t = sdk.find_type_definition("app.SaveDataManager")
if t == nil then
    log_line("ERROR app.SaveDataManager not found; guard NOT active")
    return
end

local hooked = 0
for _, name in ipairs(BLOCK) do
    local m = t:get_method(name)
    if m == nil then
        log_line("ERROR method not found: " .. name)
    else
        sdk.hook(m, function(args)
            log_line("blocked " .. name)
            return sdk.PreHookResult.SKIP_ORIGINAL
        end, function(retval) return retval end)
        hooked = hooked + 1
    end
end
log_line(string.format("guard active: %d/%d save entry points hooked", hooked, #BLOCK))

re.on_draw_ui(function()
    imgui.text(string.format("coop_saveguard: %d/%d hooks, saves BLOCKED", hooked, #BLOCK))
end)
