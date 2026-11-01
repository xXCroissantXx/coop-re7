-- coop_world.lua: shared doors and items.
-- Events go through coop_enemies.lua's reliable channel (coop_send_event) and come back
-- through coop_world_on_event.
--   unlock <door id> <chapter>  a door was unlocked (key, one-way door, story)
--   open <door id> <chapter>    a door swung open
--   took <item id> <chapter> <item name>  a supply was picked up
-- Doors (app.DoorPush) and items (app.Item) carry SaveGUID, saved in the level, so the id
-- is the same on both PCs. Supplies (ammo, healing, materials, weapons) picked up by one
-- player vanish for the other (Item.disableFromScene); key items, files and maps stay in
-- both worlds so nobody gets stuck. A pickup for an area the other player hasn't loaded
-- yet is remembered and applied when it loads.

world_sync = {
    doors = {},        -- id -> { d = DoorPush, locked, open }
    doors_t = -100, poll_t = 0, items_t = -100,
    items = {},        -- id -> { it = Item, go }
    pending_took = {}, -- id -> chapter
    applying = {},     -- id -> clock: changes we made on the friend's word (not sent back)
    sent = 0, applied = 0, msg = "-", msg_t = -100,
}
local ws = world_sync

local function log(s)
    local f = fs.read("coop_world_log.txt") or ""
    if #f > 200000 then f = f:sub(-100000) end
    fs.write("coop_world_log.txt", f .. os.date("%H:%M:%S ") .. s .. "\n")
end

local function safe(f, ...)
    local ok, r = pcall(f, ...)
    if ok then return r end
    return nil
end

local function chapter()
    local gm = sdk.get_managed_singleton("app.GameManager")
    return tonumber(gm and safe(gm.get_field, gm, "_CurrentChapter") or 0) or 0
end

local function note(msg)
    ws.msg, ws.msg_t = msg, os.clock()
    log(msg)
end

local function guid_text(g)
    local b = {}
    for i = 0, 7 do b[#b + 1] = string.format("%02x", (g:get_field("mData4_" .. i) or 0) & 0xFF) end
    return string.format("%08x-%04x-%04x-%s", (g:get_field("mData1") or 0) & 0xFFFFFFFF,
        (g:get_field("mData2") or 0) & 0xFFFF, (g:get_field("mData3") or 0) & 0xFFFF, table.concat(b))
end

local function id_of(comp)
    local g = safe(comp.get_field, comp, "SaveGUID")
    local t = g and safe(guid_text, g)
    if t == nil or t == "00000000-0000-0000-0000000000000000" then return nil end
    return t
end

local function send(text)
    if coop_send_event then coop_send_event(text) ws.sent = ws.sent + 1 log("sent: " .. text) end
end

local function scene()
    return sdk.call_native_func(sdk.get_native_singleton("via.SceneManager"),
        sdk.find_type_definition("via.SceneManager"), "get_CurrentScene")
end

-- Supplies are shared; keys, files and maps (ItemCategoryType 4, 5, 6, 9, 10) are not.
local KEYISH = { [4] = true, [5] = true, [6] = true, [9] = true, [10] = true }
local function is_supply(it)
    local d = safe(it.call, it, "get_ItemData")
    local cat = d and safe(d.get_field, d, "Category")
    return cat ~= nil and not KEYISH[cat]
end

-- Doors ------------------------------------------------------------------------------
-- doorState: 0 closed, 1 locked, 2 little open (creaks ajar as you approach), 3 pushed,
-- 4 auto-opening, 5 opened, 6 auto-closing. Only 3-5 count as "opened by someone".
local function is_open(state) return state ~= nil and state >= 3 and state <= 5 end

local function refresh_doors()
    local sc = scene()
    local arr = sc and safe(sc.call, sc, "findComponents(System.Type)", sdk.typeof("app.DoorPush"))
    local seen = {}
    for _, d in ipairs(arr and arr:get_elements() or {}) do
        local id = id_of(d)
        if id then
            seen[id] = true
            if ws.doors[id] == nil or ws.doors[id].d ~= d then
                ws.doors[id] = { d = d, locked = d:call("get_isLocked") == true,
                    open = is_open(d:call("get_doorState")) }
            end
        end
    end
    for id in pairs(ws.doors) do if not seen[id] then ws.doors[id] = nil end end
end

local function poll_doors(now)
    for id, s in pairs(ws.doors) do
        local d = s.d
        local locked = safe(d.call, d, "get_isLocked") == true
        local state = safe(d.call, d, "get_doorState") or 0
        local open = is_open(state)
        local ours = ws.applying[id] and now - ws.applying[id] < 3
        if s.locked and not locked and not ours then send(string.format("unlock %s %d", id, chapter())) end
        if open and not s.open and not ours then send(string.format("open %s %d", id, chapter())) end
        s.locked, s.open = locked, open
    end
end

local function apply_door(kind, id, ch)
    if ch ~= chapter() then return end
    local s = ws.doors[id]
    if s == nil then log("door not loaded here: " .. kind .. " " .. id) return end
    ws.applying[id] = os.clock()
    if kind == "unlock" then
        if s.d:call("get_isLocked") then
            pcall(s.d.call, s.d, "unlockDoor")
            note("your friend unlocked a door")
        end
    elseif kind == "open" then
        if not is_open(s.d:call("get_doorState")) and not s.d:call("get_isLocked") then
            pcall(s.d.call, s.d, "requestAutoOpen(app.DoorPush.OpenSide)", 2)
        end
    end
    ws.applied = ws.applied + 1
end

-- Items ------------------------------------------------------------------------------
local function refresh_items()
    local sc = scene()
    local arr = sc and safe(sc.call, sc, "findComponents(System.Type)", sdk.typeof("app.Item"))
    local seen = {}
    for _, it in ipairs(arr and arr:get_elements() or {}) do
        local id = id_of(it)
        if id then
            seen[id] = true
            if ws.items[id] == nil then
                ws.items[id] = { it = it, go = it:call("get_GameObject"), state = safe(it.call, it, "getItemState") }
            end
            ws.items[id].it = it
        end
    end
    for id in pairs(ws.items) do if not seen[id] then ws.items[id] = nil end end
    -- Pickups the friend made before this area was loaded here.
    for id, ch in pairs(ws.pending_took) do
        local e = ws.items[id]
        if e and ch == chapter() and safe(e.go.call, e.go, "get_Draw") then
            ws.pending_took[id] = nil
            ws.applying[id] = os.clock()
            pcall(e.it.call, e.it, "disableFromScene")
            note("your friend already took " .. tostring(e.it:get_field("ItemDataID")) .. " here")
        end
    end
end

local function apply_took(id, ch, name)
    if ch ~= chapter() then return end
    local e = ws.items[id]
    if e and safe(e.go.call, e.go, "get_Draw") then
        ws.applying[id] = os.clock()
        pcall(e.it.call, e.it, "disableFromScene")
        ws.applied = ws.applied + 1
        note("your friend took " .. name)
    else
        ws.pending_took[id] = ch   -- not loaded (or not shown) yet: when it is
        log("remembered pickup: " .. name .. " " .. id)
    end
end

-- Our pickups. A pickup doesn't go through Item.changeStateInventoryIn (a hook there never
-- fired): the game hides the item lying in the world (getItemState 0 -> 6, as
-- disableFromScene does) and makes a separate inventory Item. So watch world items for
-- 0 -> 6, except the ones we hid on the friend's word.
local ITEM_IN_SCENE, ITEM_GONE = 0, 6
local function poll_items(now)
    for id, e in pairs(ws.items) do
        local st = safe(e.it.call, e.it, "getItemState")
        if e.state == ITEM_IN_SCENE and st == ITEM_GONE then
            local ours = ws.applying[id] and now - ws.applying[id] < 3
            if not ours and is_supply(e.it) then
                send(string.format("took %s %d %s", id, chapter(), tostring(e.it:get_field("ItemDataID"))))
            end
        end
        e.state = st
    end
end

-- Incoming events (called by coop_enemies.lua). Returns true if it was ours.
function coop_world_on_event(text)
    local kind, id, ch = text:match("^(unlock) (%S+) (%-?%d+)")
    if not kind then kind, id, ch = text:match("^(open) (%S+) (%-?%d+)") end
    if kind then pcall(apply_door, kind, id, tonumber(ch)) return true end
    local tid, tch, tname = text:match("^took (%S+) (%-?%d+) (%S+)")
    if tid then pcall(apply_took, tid, tonumber(tch), tname) return true end
    return false
end

re.on_frame(function()
    local now = os.clock()
    if now - ws.doors_t > 3 then
        ws.doors_t = now
        local ok, err = pcall(refresh_doors)
        if not ok and not ws.door_err then ws.door_err = true log("doors ERR " .. tostring(err)) end
    end
    if now - ws.items_t > 2 then
        ws.items_t = now
        local ok, err = pcall(refresh_items)
        if not ok and not ws.item_err then ws.item_err = true log("items ERR " .. tostring(err)) end
    end
    if now - ws.poll_t > 0.25 then
        ws.poll_t = now
        local ok, err = pcall(poll_doors, now)
        if not ok and not ws.poll_err then ws.poll_err = true log("door poll ERR " .. tostring(err)) end
        local iok, ierr = pcall(poll_items, now)
        if not iok and not ws.ipoll_err then ws.ipoll_err = true log("item poll ERR " .. tostring(ierr)) end
    end
end)

-- On-screen line (coop_dummy shows it).
function world_sync_hud()
    if os.clock() - ws.msg_t < 6 then return "World: " .. ws.msg end
    return nil
end

function world_sync_status()
    local doors, locked, items, pend = 0, 0, 0, 0
    for _, s in pairs(ws.doors) do doors = doors + 1 if s.locked then locked = locked + 1 end end
    for _ in pairs(ws.items) do items = items + 1 end
    for _ in pairs(ws.pending_took) do pend = pend + 1 end
    return string.format("Doors and items: %d doors (%d locked), %d items here; sent %d, applied %d, remembered %d",
        doors, locked, items, ws.sent, ws.applied, pend)
end

-- Testing: the bot "opens" / "unlocks" the nearest door, or "takes" the nearest supply.
local function nearest(list, pick)
    local player = sdk.get_managed_singleton("app.ObjectManager"):get_field("PlayerObj")
    if player == nil then return nil end
    local pp = player:call("get_Transform"):call("get_Position")
    local best, best_id, best_d
    for id, e in pairs(list) do
        if pick(e) then
            local go = e.go or e.d:call("get_GameObject")
            local p = go:call("get_Transform"):call("get_Position")
            local dd = (p.x - pp.x) ^ 2 + (p.y - pp.y) ^ 2 + (p.z - pp.z) ^ 2
            if best_d == nil or dd < best_d then best, best_id, best_d = e, id, dd end
        end
    end
    return best, best_id
end

function world_sync_bot(kind)
    if kind == "unlock" or kind == "open" then
        local _, id = nearest(ws.doors, function(s)
            if kind == "unlock" then return s.locked end
            return not s.locked and not s.open
        end)
        if id == nil then return "no suitable door nearby" end
        fs.write("coopnet_command.txt", string.format("botevent %s %s %d", kind, id, chapter()))
        return "the bot will " .. kind .. " the nearest door"
    elseif kind == "took" then
        local e, id = nearest(ws.items, function(e) return safe(e.go.call, e.go, "get_Draw") and is_supply(e.it) end)
        if id == nil then return "no supply nearby" end
        local name = tostring(e.it:get_field("ItemDataID"))
        fs.write("coopnet_command.txt", string.format("botevent took %s %d %s", id, chapter(), name))
        return "the bot will take " .. name
    end
end

log("coop_world loaded")
