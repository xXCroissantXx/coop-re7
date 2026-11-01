-- coop_enemies.lua: enemy sync, step 1 (deaths).
-- When an enemy dies (or Jack is knocked down) in one player's game, the same enemy
-- goes down in the other's. Events travel reliably through CoopNet.cs:
--   us -> coopnet_ev_out.txt   "<id>\t<text>" lines, ids always growing
--   friend -> coopnet_ev_in.txt "<n>\t<text>" lines, each n handled once
-- Event text: "kill <enemy id> <chapter> <name>".
--
-- Enemy id: regular enemies (and Jack) carry app.EnemySave.SaveGUID, saved in the
-- level, so it's the same on both PCs. Others fall back to "folder path/name".
-- Regular enemies stay dead: a kill for one that isn't loaded yet is remembered and
-- applied when it appears. Stalkers and bosses (Jack...) get back up in RE7, so their
-- "kill" is only applied if they're loaded right now.

enemy_sync = {
    enabled = true,
    list_index = nil, list_t = -100,
    tracked = {},          -- id -> { go, dc, name, dead }
    pending = {},          -- id -> chapter: friend's kills of regular enemies not loaded here yet
    applying = {},         -- id -> clock: kills we applied ourselves (don't echo them back)
    ev_seq = math.floor(os.time()) * 1000,
    ev_out = {},           -- last outgoing lines (the file is rewritten whole)
    ev_in_last = -1,
    last_msg = "-", msg_t = -100,
    sent = 0, applied = 0, scan_t = 0, in_t = 0,
}
local es = enemy_sync

local function log(s)
    local f = fs.read("coop_enemies_log.txt") or ""
    if #f > 200000 then f = f:sub(-100000) end
    fs.write("coop_enemies_log.txt", f .. os.date("%H:%M:%S ") .. s .. "\n")
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

-- Molded and other regular enemies die for good; everyone else (Jack Em300x, the
-- Bakers, bosses) only goes down for a while.
local function is_regular(name)
    return name:match("^Em4%d%d%d") ~= nil
end

local function guid_text(g)
    local b = {}
    for i = 0, 7 do b[#b + 1] = string.format("%02x", (g:get_field("mData4_" .. i) or 0) & 0xFF) end
    return string.format("%08x-%04x-%04x-%s", (g:get_field("mData1") or 0) & 0xFFFFFFFF,
        (g:get_field("mData2") or 0) & 0xFFFF, (g:get_field("mData3") or 0) & 0xFFFF, table.concat(b))
end

local function enemy_id(go)
    local save = safe(go.call, go, "getComponent(System.Type)", sdk.typeof("app.EnemySave"))
    local g = save and safe(save.get_field, save, "SaveGUID")
    if g then
        local t = safe(guid_text, g)
        if t and t ~= "00000000-0000-0000-0000000000000000" then return "g:" .. t end
    end
    local folder = safe(go.call, go, "get_Folder")
    local path = folder and safe(folder.call, folder, "get_Path") or "?"
    return "p:" .. path:gsub("%s", "_") .. "/" .. tostring(safe(go.call, go, "get_Name"))
end

local function damage_controller(go)
    local comps = safe(go.call, go, "get_Components")
    for _, c in ipairs(comps and safe(comps.get_elements, comps) or {}) do
        local td = c:get_type_definition()
        if td:is_a("app.DamageController") then return c end
    end
    return nil
end

-- ObjectManager.ManagedObjects is a list of lists; the enemy list is the biggest one
-- made only of "EmNNNN" objects (its index isn't the ListType enum value).
local function enemy_list()
    local om = sdk.get_managed_singleton("app.ObjectManager")
    local lists = om and safe(om.get_field, om, "ManagedObjects")
    if lists == nil then return nil end
    if es.list_index == nil or os.clock() - es.list_t > 5 then
        es.list_t = os.clock()
        local best, best_n = nil, 0
        for i = 0, (safe(lists.call, lists, "get_Count") or 0) - 1 do
            local l = lists:call("get_Item", i)
            local n = l and l:call("get_Count") or 0
            local all_em = n > 0
            for j = 0, n - 1 do
                local go = l:call("get_Item", j)
                local name = go and safe(go.call, go, "get_Name") or ""
                if not name:match("^Em%d%d%d%d$") then all_em = false break end
            end
            if all_em and n > best_n then best, best_n = i, n end
        end
        es.list_index = best
    end
    return es.list_index and lists:call("get_Item", es.list_index)
end

local function send_event(text)
    es.ev_seq = es.ev_seq + 1
    es.ev_out[#es.ev_out + 1] = es.ev_seq .. "\t" .. text
    while #es.ev_out > 30 do table.remove(es.ev_out, 1) end
    fs.write("coopnet_ev_out.txt", table.concat(es.ev_out, "\n") .. "\n")
    es.sent = es.sent + 1
    log("sent: " .. text)
end

-- Shared with coop_world.lua (doors and items): one event file, one id sequence.
function coop_send_event(text) send_event(text) end

local function note(msg)
    es.last_msg, es.msg_t = msg, os.clock()
    log(msg)
end

-- One hit far bigger than its health, credited to our player: plays the real death or
-- knock-down. (Setting health to 0 marks it dead but it keeps walking.) The game scales
-- damage (health + 1000 left Jack on 2300 of 10000), so overkill, and hit again if needed.
local function kill_enemy(e)
    local player = sdk.get_managed_singleton("app.ObjectManager"):get_field("PlayerObj")
    local m = sdk.find_type_definition("app.DamageController"):get_method("newFakeDamageInfo")
    for _ = 1, 3 do
        local hp = e.dc:call("get_health") or 0
        e.dc:call("addManualDamage", m:call(nil, hp * 4 + 1000.0, player, e.go))
        if e.dc:call("get_isDead") == true then return end
    end
end

-- Scan the enemies here: register new ones, notice deaths, apply remembered kills.
local function scan()
    local l = enemy_list()
    if l == nil then return end
    local seen = {}
    for j = 0, l:call("get_Count") - 1 do
        local go = l:call("get_Item", j)
        if go then
            local addr = go:get_address()
            local e = es.tracked[addr]
            if e == nil then
                local dc = damage_controller(go)
                if dc then
                    e = { go = go, dc = dc, id = enemy_id(go), name = go:call("get_Name") }
                    e.dead = dc:call("get_isDead") == true
                    es.tracked[addr] = e
                end
            end
            if e then
                seen[addr] = true
                local active = safe(go.call, go, "get_Update") == true
                local dead = e.dc:call("get_isDead") == true
                if dead and not e.dead then
                    -- Died here. Tell the friend, unless we did it on their word.
                    if es.applying[e.id] and os.clock() - es.applying[e.id] < 5 then
                        es.applying[e.id] = nil
                    else
                        send_event(string.format("kill %s %d %s", e.id, chapter(), e.name))
                    end
                elseif not dead and e.dead then
                    log("back up: " .. e.name .. " " .. e.id)
                end
                -- Damage here (health dropped, still alive): tell the friend how much.
                -- Damage we applied on the friend's word already moved e.hp, so it isn't sent back.
                local hp = e.dc:call("get_health") or 0
                if e.hp and not dead and active and hp < e.hp - 0.5 then
                    send_event(string.format("dmg %s %d %.1f %s", e.id, chapter(), e.hp - hp, e.name))
                end
                e.hp = hp
                e.dead = dead
                if not dead and active and es.pending[e.id] == chapter() then
                    es.pending[e.id] = nil
                    es.applying[e.id] = os.clock()
                    local ok, err = pcall(kill_enemy, e)
                    note(ok and ("your friend already killed " .. e.name .. " here") or ("ERR remembered kill: " .. tostring(err)))
                end
            end
        end
    end
    for addr in pairs(es.tracked) do if not seen[addr] then es.tracked[addr] = nil end end
end

local function find_tracked(id)
    for _, e in pairs(es.tracked) do if e.id == id then return e end end
    return nil
end

-- The friend hurt an enemy: take the same health off ours. setHealth rather than
-- another hit, so the game doesn't scale it a second time. Never to 0 here: setting 0
-- leaves a walking "dead" enemy; the friend's kill event follows and does it properly.
local function on_damage(id, ch, amount, name)
    if ch ~= chapter() then return end
    local e = find_tracked(id)
    if e == nil or e.dead or safe(e.go.call, e.go, "get_Update") ~= true then return end
    local hp = e.dc:call("get_health") or 0
    local new = math.max(hp - amount, 1.0)
    e.dc:call("setHealth(System.Single, System.Single)", new, e.dc:call("get_maxHealth"))
    e.hp = e.dc:call("get_health")
    es.applied_dmg = (es.applied_dmg or 0) + 1
    log(string.format("friend hit %s for %.0f: %.0f -> %.0f", name, amount, hp, e.hp))
end

local function on_event(text)
    -- Doors and items belong to coop_world.lua.
    if coop_world_on_event and coop_world_on_event(text) then return end
    if coop_story_on_event and coop_story_on_event(text) then return end
    if coop_revive_on_event and coop_revive_on_event(text) then return end
    local oid, och, oname = text:match("^own (%S+) (%-?%d+) (%S+)")
    if oid then if enemy_move_on_own then enemy_move_on_own(oid, tonumber(och), oname) end return end
    local did, dch, damt, dname = text:match("^dmg (%S+) (%-?%d+) ([%d%.]+) (%S+)")
    if did then on_damage(did, tonumber(dch), tonumber(damt), dname) return end
    local id, ch, name = text:match("^kill (%S+) (%-?%d+) (%S+)")
    if id == nil then log("ignored event: " .. text) return end
    ch = tonumber(ch)
    if ch ~= chapter() then log("kill in another chapter, ignored: " .. text) return end
    local e = find_tracked(id)
    local active = e and safe(e.go.call, e.go, "get_Update") == true
    if e and active and not e.dead then
        es.applying[id] = os.clock()
        local ok, err = pcall(kill_enemy, e)
        es.applied = es.applied + 1
        note(ok and ("your friend took down " .. name) or ("ERR applying kill: " .. tostring(err)))
    elseif e and e.dead then
        log("already down here: " .. name)
    elseif is_regular(name) then
        es.pending[id] = ch   -- not here or not awake yet: kill it when it is
        note("your friend killed " .. name .. " (here when you get there)")
    else
        log("friend downed " .. name .. ", not active here: ignored")
    end
end

local function read_events()
    local text = fs.read("coopnet_ev_in.txt")
    if text == nil or text == "" then   -- fs.read gives "" for a missing file
        if es.ev_in_last < 0 then es.ev_in_last = 0 end   -- nothing received yet: handle all that comes
        return
    end
    local lines, max_n = {}, -1
    for line in text:gmatch("[^\n]+") do
        local n, body = line:match("^(%d+)\t(.*)$")
        n = tonumber(n)
        if n then
            lines[#lines + 1] = { n, body }
            if n > max_n then max_n = n end
        end
    end
    -- First read after Reset scripts: what's in the file was handled before.
    if es.ev_in_last < 0 then es.ev_in_last = math.max(max_n, 0) return end
    -- CoopNet restarted (it deletes the file and counts from 1 again).
    if max_n < es.ev_in_last then es.ev_in_last = 0 end
    for _, l in ipairs(lines) do
        if l[1] > es.ev_in_last then
            local ok, err = pcall(on_event, l[2])
            if not ok then log("event ERR " .. tostring(err)) end
        end
    end
    if max_n > es.ev_in_last then es.ev_in_last = max_n end
end

-- Enemy movement (step 3) -----------------------------------------------------------
-- One game controls the enemies ("host"); the other game's copies follow it ("puppets").
-- Host: ~10 times a second, coopnet_es_out.txt = "seq <n>" / "t <time> ch <chapter>" and
-- one line per awake enemy: id x y z yaw bank motion frame speed (animation layer 0).
-- CoopNet sends each new seq unreliably; the other side gets it as coopnet_es_in.txt.
-- Guest: for each enemy in the snapshots, switch its own animation brain (MotionFsm) and
-- AI (EnemyOrder.requestThinkOff) off, then place it 0.15 s behind the host's timeline
-- and play the host's clip. An enemy missing from the snapshots for 3 s gets its own AI
-- back. Host = the lower SteamID, so both sides agree without asking.
--
-- Ownership: each enemy is run (real AI) by one game and followed by the other. Enemies
-- only ever target their own game's player (a target set to the ghost is dropped within
-- a second), so an enemy belongs to the game of the player it's near: by default the game
-- where it's awake; if both send it, the host keeps it. The owner hands it over (reliable
-- "own <id> <chapter> <name>") when the other player is 3 m+ closer to it. A game that
-- gets no data for an enemy it gave away takes it back after 3 s (friend gone, or the
-- bot, which can't run enemies).
em_move = {
    role_pref = "auto", role = "host",
    own = {},        -- id -> "me" | "peer"
    own_t = {},      -- id -> when ownership last changed
    handed = {},     -- id -> true: we gave it away and wait for the friend's data
    handoff_t = 0, handoffs = 0, takebacks = 0,
    seq = 0, snap_t = 0, in_t = 0, last_in_seq = nil,
    hist = {},       -- id -> list of { t, x, y, z, yaw, bank, mid, frame, speed }
    puppets = {},    -- id -> e
    offset = nil,    -- local clock - host clock (smallest seen)
    rec = nil, replay = nil,
    msg = "-", sent = 0, recv = 0,
}
local mv = em_move
local MOVE_DELAY = 0.15
local SNAP_EVERY = 0.1

local kv_cache, kv_t = {}, -100
local function net_kv()
    if os.clock() - kv_t > 1 then
        kv_t = os.clock()
        local st = fs.read("coopnet_status.txt")
        if st and st ~= "" then
            kv_cache = {}
            for k, v in st:gmatch("(%w+)=([^\n]*)") do kv_cache[k] = v end
        end
    end
    return kv_cache
end

local function decide_role()
    if mv.replay then return "guest" end
    if mv.role_pref ~= "auto" then return mv.role_pref end
    local kv = net_kv()
    if kv.mode == "steam" then
        local me, peer = kv.steamSelf, (kv.peer or ""):match("^steam:(%d+)$")
        if me and peer and peer ~= "0" then
            local lower = (#me < #peer) or (#me == #peer and me < peer)
            return lower and "host" or "guest"
        end
    end
    return "host"
end

local function layer0(e)
    if e.layer == nil then
        local mot = safe(e.go.call, e.go, "getComponent(System.Type)", sdk.typeof("via.motion.Motion"))
        e.layer = mot and safe(mot.call, mot, "getLayer", 0)
    end
    return e.layer
end

local function yaw_of(q) return 2 * math.atan(q.y, q.w) end

local function enemy_line(e)
    local tr = e.go:call("get_Transform")
    local p, q = tr:call("get_Position"), tr:call("get_Rotation")
    local L = layer0(e)
    if L == nil then return nil end
    return string.format("%s %.3f %.3f %.3f %.4f %d %d %.2f %.3f", e.id, p.x, p.y, p.z, yaw_of(q),
        L:call("get_MotionBankID") or 0, L:call("get_MotionID") or 0, L:call("get_Frame") or 0, L:call("get_Speed") or 1)
end

local function parse_line(line)
    local id, x, y, z, yaw, bank, mid, frame, speed =
        line:match("^(%S+) (%S+) (%S+) (%S+) (%S+) (%-?%d+) (%-?%d+) (%S+) (%S+)$")
    if id == nil then return nil end
    return id, { x = tonumber(x), y = tonumber(y), z = tonumber(z), yaw = tonumber(yaw),
        bank = tonumber(bank), mid = tonumber(mid), frame = tonumber(frame), speed = tonumber(speed) }
end

local function push_hist(id, s, t)
    s.t = t
    local h = mv.hist[id]
    if h == nil then h = {} mv.hist[id] = h end
    h[#h + 1] = s
    while #h > 2 and h[2].t < t - 2 do table.remove(h, 1) end
end

-- Host: write the snapshot of our awake enemies (puppets excluded).
local function write_snapshot(now)
    local lines = { "seq " .. mv.seq, string.format("t %.3f ch %d", now, chapter()) }
    for _, e in pairs(es.tracked) do
        if safe(e.go.call, e.go, "get_Update") == true and not mv.puppets[e.id] and mv.own[e.id] ~= "peer" then
            local l = safe(enemy_line, e)
            if l then lines[#lines + 1] = l end
        end
    end
    mv.seq = mv.seq + 1
    lines[1] = "seq " .. mv.seq
    fs.write("coopnet_es_out.txt", table.concat(lines, "\n") .. "\n")
    mv.sent = mv.sent + 1
end

-- Guest: take a received snapshot into the per-enemy timelines.
local function read_snapshot(now)
    local text = fs.read("coopnet_es_in.txt")
    if text == nil or text == "" then return end
    local seq = text:match("^seq (%d+)")
    if seq == nil or seq == mv.last_in_seq then return end
    mv.last_in_seq = seq
    local t, ch = text:match("\nt (%S+) ch (%-?%d+)")
    t, ch = tonumber(t), tonumber(ch)
    if t == nil or ch ~= chapter() then return end
    local off = now - t
    -- A jump of 5 s+ means the host's clock restarted: start over (see coop_dummy).
    if mv.offset == nil or off < mv.offset or off > mv.offset + 5 then mv.offset = off end
    for line in text:gmatch("[^\n]+") do
        local id, s = parse_line(line)
        if id then
            -- Both games running it: the host keeps it, the other side gives way.
            local take = true
            if mv.own[id] == "me" then
                if mv.role == "host" then take = false
                else mv.own[id], mv.own_t[id] = "peer", now end
            elseif mv.own[id] == nil then
                mv.own[id], mv.own_t[id] = "peer", now
            end
            if take then push_hist(id, s, t + mv.offset) end
        end
    end
    mv.recv = mv.recv + 1
end

local function order_of(e)
    if e.order == nil then
        local comps = safe(e.go.call, e.go, "get_Components")
        for _, c in ipairs(comps and safe(comps.get_elements, comps) or {}) do
            if c:get_type_definition():is_a("app.EnemyOrder") then e.order = c break end
        end
    end
    return e.order
end

local function set_brain(e, on)
    local fsm = safe(e.go.call, e.go, "getComponent(System.Type)", sdk.typeof("via.motion.MotionFsm"))
    if fsm then safe(fsm.call, fsm, "set_Enabled", on) end
    local order = order_of(e)
    if order then
        if mv.owner == nil then
            mv.owner = sdk.create_managed_string("coop-re7")
            if mv.owner and mv.owner.add_ref then mv.owner:add_ref() end
        end
        safe(order.call, order, on and "requestThinkOn" or "requestThinkOff", mv.owner)
    end
end

local function puppetize(e)
    if not safe(e.go.call, e.go, "get_Update") then
        -- Awake in the host's game: wake ours too.
        safe(e.go.call, e.go, "set_UpdateSelf", true)
        safe(e.go.call, e.go, "set_DrawSelf", true)
    end
    set_brain(e, false)
    mv.puppets[e.id] = e
    log("puppet on: " .. e.name .. " " .. e.id)
end

local function release(id)
    local e = mv.puppets[id]
    mv.puppets[id] = nil
    mv.hist[id] = nil
    if e then
        safe(set_brain, e, true)
        e.cur_bank, e.cur_mid = nil, nil
        log("puppet off: " .. e.name .. " " .. id)
    end
end

local function lerp_angle(a, b, k)
    local d = (b - a + math.pi) % (2 * math.pi) - math.pi
    return a + d * k
end

local function drive(e, h, now)
    local t = now - MOVE_DELAY
    local a, b = h[1], h[#h]
    for i = #h - 1, 1, -1 do
        if h[i].t <= t then a, b = h[i], h[i + 1] break end
    end
    local k = (b.t > a.t) and math.max(0, math.min(1, (t - a.t) / (b.t - a.t))) or 1
    local x, y, z = a.x + (b.x - a.x) * k, a.y + (b.y - a.y) * k, a.z + (b.z - a.z) * k
    local yaw = lerp_angle(a.yaw, b.yaw, k)
    local mc = e.mc or safe(e.go.call, e.go, "getComponent(System.Type)", sdk.typeof("app.MovementController"))
    e.mc = mc
    local q = Quaternion.new(math.cos(yaw / 2), 0, math.sin(yaw / 2), 0)
    if mc then safe(mc.call, mc, "warp(via.vec3, via.Quaternion)", Vector3f.new(x, y, z), q) end
    -- Animation: the clip at the newer sample; correct the frame if it drifts.
    local s = (k > 0.5) and b or a
    local L = layer0(e)
    if L == nil then return end
    if e.cur_bank ~= s.bank or e.cur_mid ~= s.mid then
        local m = e.change_motion
        if m == nil then
            for _, mm in ipairs(L:get_type_definition():get_methods()) do
                if mm:get_name() == "changeMotion" and mm:get_num_params() == 6 then m = mm end
            end
            e.change_motion = m
        end
        if m then safe(m.call, m, L, s.bank, s.mid, s.frame, 8.0, 2, 0) end
        e.cur_bank, e.cur_mid = s.bank, s.mid
    else
        local target = a.frame + ((b.mid == a.mid and b.bank == a.bank) and (b.frame - a.frame) * k or 0)
        local f = L:call("get_Frame") or 0
        if math.abs(f - target) > 4 then safe(L.call, L, "set_Frame", target) end
    end
    safe(L.call, L, "set_Speed", s.speed)
end

-- The friend's position, from their Ethan (only while shown, i.e. data is fresh).
local function friend_pos()
    local g = coop_ghost and coop_ghost()
    if g == nil or ghost_hidden then return nil end
    return safe(function() return g:call("get_Transform"):call("get_Position") end)
end

local function hand_off(e, now)
    send_event(string.format("own %s %d %s", e.id, chapter(), e.name))
    mv.own[e.id], mv.own_t[e.id], mv.handed[e.id] = "peer", now, true
    mv.hist[e.id] = nil
    puppetize(e)
    mv.handoffs = mv.handoffs + 1
    mv.msg = "handed " .. e.name .. " to your friend"
    log(mv.msg)
end

local function dist2(a, b) return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2 end

function check_handoffs(now)
    -- The bot can't run enemies: in bot mode only the test button hands one over.
    if net_kv().mode == "bot" then return end
    local g = friend_pos()
    local player = sdk.get_managed_singleton("app.ObjectManager"):get_field("PlayerObj")
    if g == nil or player == nil then return end
    local p = player:call("get_Transform"):call("get_Position")
    for _, e in pairs(es.tracked) do
        if mv.own[e.id] ~= "peer" and not e.dead and not mv.puppets[e.id] and safe(e.go.call, e.go, "get_Update") == true then
            local ep = e.go:call("get_Transform"):call("get_Position")
            -- 3 m of hysteresis so it doesn't bounce between games.
            if math.sqrt(dist2(ep, g)) + 3 < math.sqrt(dist2(ep, p)) then hand_off(e, now) end
        end
    end
end

-- The friend handed us an enemy: run it ourselves from now on.
function enemy_move_on_own(id, ch, name)
    if ch ~= chapter() then return end
    mv.own[id], mv.own_t[id], mv.handed[id] = "me", os.clock(), nil
    if mv.puppets[id] then release(id) end
    mv.hist[id] = nil
    note("your friend handed " .. name .. " to you")
end

local function update_movement(now)
    mv.role = decide_role()
    if mv.role == "host" and now - mv.snap_t >= SNAP_EVERY then
        mv.snap_t = now
        pcall(write_snapshot, now)
    end
    if mv.role == "guest" and not mv.replay and now - mv.in_t >= 1 / 30 then
        mv.in_t = now
        pcall(read_snapshot, now)
    end
    -- Replay test: feed the recording as if the host had sent it.
    local r = mv.replay
    if r then
        while r.i <= #r.frames and r.frames[r.i].rt <= now - r.t0 do
            local f = r.frames[r.i]
            push_hist(r.id, { x = f.x, y = f.y, z = f.z, yaw = f.yaw, bank = f.bank, mid = f.mid, frame = f.frame, speed = f.speed }, now)
            r.i = r.i + 1
        end
        if r.i > #r.frames and now - r.t0 > r.frames[#r.frames].rt + 3.5 then
            mv.replay = nil
            mv.msg = "replay finished"
        end
    end
    -- Drive the enemies the friend runs; take back the ones they went quiet on.
    for _, e in pairs(es.tracked) do
        local id = e.id
        if mv.own[id] == "peer" then
            local h = mv.hist[id]
            local fresh = h ~= nil and #h > 0 and now - h[#h].t <= 3
            if fresh then
                if mv.puppets[id] == nil then puppetize(e) end
                mv.handed[id] = nil
                local ok, err = pcall(drive, e, h, now)
                if not ok and not mv.drive_err then mv.drive_err = true log("drive ERR " .. tostring(err)) end
            elseif now - (mv.own_t[id] or 0) > 3 and (h == nil or #h == 0 or now - h[#h].t > 3) then
                mv.own[id], mv.own_t[id], mv.handed[id] = "me", now, nil
                if mv.puppets[id] then release(id) end
                mv.hist[id] = nil
                mv.takebacks = mv.takebacks + 1
                log("took back " .. e.name .. " " .. id .. " (no data from the friend for 3 s)")
            elseif mv.handed[id] and mv.puppets[id] == nil then
                puppetize(e)   -- just handed over: hold still until their data arrives
            end
        end
    end
    for id in pairs(mv.puppets) do if mv.own[id] ~= "peer" then release(id) end end
    -- Hand enemies to the friend when they're clearly closer to them (every 0.5 s).
    if now - mv.handoff_t >= 0.5 then
        mv.handoff_t = now
        pcall(check_handoffs, now)
    end
    -- Recording (testing): one enemy, 10 times a second.
    local rc = mv.rec
    if rc and now - rc.last >= SNAP_EVERY then
        rc.last = now
        local l = safe(enemy_line, rc.e)
        local s
        if l then _, s = parse_line(l) end
        if s then s.rt = now - rc.t0 rc.frames[#rc.frames + 1] = s end
        if now - rc.t0 >= rc.len then
            mv.rec = nil
            mv.recorded = { id = rc.e.id, e = rc.e, frames = rc.frames }
            mv.msg = string.format("recorded %s: %d samples, ready to replay", rc.e.name, #rc.frames)
            log(mv.msg)
        end
    end
end

re.on_frame(function()
    if not es.enabled then return end
    local now = os.clock()
    local mok, merr = pcall(update_movement, now)
    if not mok and not mv.err then mv.err = true log("movement ERR " .. tostring(merr)) end
    if now - es.in_t >= 0.2 then
        es.in_t = now
        local ok, err = pcall(read_events)
        if not ok and not es.read_err then es.read_err = true log("read ERR " .. tostring(err)) end
    end
    if now - es.scan_t >= 0.25 then
        es.scan_t = now
        local ok, err = pcall(scan)
        if not ok and not es.scan_err then es.scan_err = true log("scan ERR " .. tostring(err)) end
    end
end)

-- For the on-screen status (coop_dummy shows it for 6 s).
function enemy_sync_hud()
    if os.clock() - es.msg_t < 6 then return "Enemies: " .. es.last_msg end
    return nil
end

-- Testing: the bot "kills" (or hurts, with damage_frac) the awake enemy nearest to
-- us, as if the friend had.
function enemy_sync_bot_kill_nearest(damage_frac)
    local player = sdk.get_managed_singleton("app.ObjectManager"):get_field("PlayerObj")
    if player == nil then return "no player" end
    local pp = player:call("get_Transform"):call("get_Position")
    local best, best_d
    for _, e in pairs(es.tracked) do
        if not e.dead and safe(e.go.call, e.go, "get_Update") == true then
            local p = e.go:call("get_Transform"):call("get_Position")
            local d = (p.x - pp.x) ^ 2 + (p.y - pp.y) ^ 2 + (p.z - pp.z) ^ 2
            if best_d == nil or d < best_d then best, best_d = e, d end
        end
    end
    if best == nil then return "no awake enemy nearby" end
    if damage_frac then
        local amount = (best.dc:call("get_maxHealth") or 0) * damage_frac
        fs.write("coopnet_command.txt", string.format("botevent dmg %s %d %.1f %s", best.id, chapter(), amount, best.name))
        log(string.format("bot test: friend hits %s for %.0f", best.name, amount))
        return string.format("the bot will hit %s for %.0f", best.name, amount)
    end
    fs.write("coopnet_command.txt", string.format("botevent kill %s %d %s", best.id, chapter(), best.name))
    log("bot test: friend kills " .. best.name .. " " .. best.id)
    return "the bot will take down " .. best.name
end

-- Testing (one PC): record the nearest awake enemy under its own AI, then put it back
-- where it started and replay the recording through the puppet code with its AI off.
local function nearest_awake()
    local player = sdk.get_managed_singleton("app.ObjectManager"):get_field("PlayerObj")
    if player == nil then return nil end
    local pp = player:call("get_Transform"):call("get_Position")
    local best, best_d
    for _, e in pairs(es.tracked) do
        if not e.dead and safe(e.go.call, e.go, "get_Update") == true and not mv.puppets[e.id] then
            local p = e.go:call("get_Transform"):call("get_Position")
            local d = (p.x - pp.x) ^ 2 + (p.y - pp.y) ^ 2 + (p.z - pp.z) ^ 2
            if best_d == nil or d < best_d then best, best_d = e, d end
        end
    end
    return best
end

function enemy_move_record(seconds)
    local e = nearest_awake()
    if e == nil then mv.msg = "no awake enemy nearby" return mv.msg end
    mv.rec = { e = e, t0 = os.clock(), last = -100, len = seconds or 6, frames = {} }
    mv.msg = "recording " .. e.name .. " for " .. (seconds or 6) .. " s"
    log(mv.msg)
    return mv.msg
end

function enemy_move_replay()
    local r = mv.recorded
    if r == nil or #r.frames < 2 then mv.msg = "record an enemy first" return mv.msg end
    local f = r.frames[1]
    local mc = safe(r.e.go.call, r.e.go, "getComponent(System.Type)", sdk.typeof("app.MovementController"))
    if mc then safe(mc.call, mc, "warp(via.vec3, via.Quaternion)", Vector3f.new(f.x, f.y, f.z),
        Quaternion.new(math.cos(f.yaw / 2), 0, math.sin(f.yaw / 2), 0)) end
    mv.hist[r.id] = nil
    mv.own[r.id], mv.own_t[r.id] = "peer", os.clock()   -- "the friend" (the recording) runs it
    mv.replay = { id = r.id, frames = r.frames, i = 1, t0 = os.clock() }
    mv.msg = "replaying " .. r.e.name .. " with its AI off"
    log(mv.msg)
    return mv.msg
end

-- Testing: hand the nearest awake enemy to "the friend" (the bot never sends it back, so
-- it freezes, and after 3 s we take it back), or have the bot hand it to us.
function enemy_move_test_handoff()
    local e = nearest_awake()
    if e == nil then mv.msg = "no awake enemy nearby" return mv.msg end
    hand_off(e, os.clock())
    return mv.msg .. " (it should freeze, then come back to us after 3 s)"
end

function enemy_move_bot_hands_back()
    for id, o in pairs(mv.own) do
        if o == "peer" then
            local e = find_tracked(id)
            fs.write("coopnet_command.txt", string.format("botevent own %s %d %s", id, chapter(), e and e.name or "?"))
            return "the bot hands " .. (e and e.name or id) .. " back"
        end
    end
    return "the friend runs no enemies right now"
end

function enemy_move_status()
    local mine, theirs = 0, 0
    for _, e in pairs(es.tracked) do
        if safe(e.go.call, e.go, "get_Update") == true then
            if mv.own[e.id] == "peer" then theirs = theirs + 1 else mine = mine + 1 end
        end
    end
    return string.format("Enemy movement: %d run here, %d run by your friend; handed over %d, taken back %d; snapshots sent %d, received %d; %s",
        mine, theirs, mv.handoffs, mv.takebacks, mv.sent, mv.recv, mv.msg)
end

function enemy_sync_status()
    local awake, down = 0, 0
    for _, e in pairs(es.tracked) do
        if e.dead then down = down + 1 elseif safe(e.go.call, e.go, "get_Update") == true then awake = awake + 1 end
    end
    local pending = 0
    for _ in pairs(es.pending) do pending = pending + 1 end
    local near = ""
    for _, e in pairs(es.tracked) do
        if not e.dead and safe(e.go.call, e.go, "get_Update") == true then
            near = string.format("; %s health %.0f/%.0f", e.name, e.hp or 0, e.dc:call("get_maxHealth") or 0)
        end
    end
    return string.format("Enemy sync: %d awake, %d down here; sent %d, applied %d kills %d hits, remembered %d%s",
        awake, down, es.sent, es.applied, es.applied_dmg or 0, pending, near)
end

log("coop_enemies loaded")
