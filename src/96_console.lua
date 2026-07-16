-- Ess/96_console.lua -- Ess.Easy.Console: an in-game, browsable, searchable reference for every
-- Ess.Easy.* call (plus a handful of standout one-line Core helpers) -- so a brand-new modder can open
-- one window and see exactly what they can call, instead of needing FEATURE_SHEET.md open in another tab.
-- Loads LAST (highest file number) since it catalogs everything else in the framework.
--
-- Built on Ess.UI.Board (list + detail pane, reusing the contracts.gfx movie -- category/objectives/
-- rewards fields repurposed below to show a usage signature + wrapped description, not real contract
-- data) for browsing, and Ess.TextConsole (the plain no-gfx-asset console built earlier this session) for
-- the search box -- both existing pieces composed together rather than a third UI built from scratch.
--
-- Ess.Easy.Console.open()    -- browse everything, grouped by namespace
-- Ess.Easy.Console.search()  -- opens a TextConsole prompt; on submit, filters the registry and reopens
--                                the board with matches (also reachable from inside the board itself, via
--                                the pinned "[ Search... ]" row at the top of the list)
-- Ess.Easy.Console.close()

local Ess = _G.Ess
Ess.Easy = Ess.Easy or {}
Ess.Easy.Console = Ess.Easy.Console or {}

-- The registry. Grouped in display order; each entry is { ns=, usage=, desc= }. Kept to genuinely
-- one-line-callable functions -- this is a quick-reference cheat sheet, not an exhaustive API dump (see
-- FEATURE_SHEET.md for the full namespace catalog).
local REGISTRY = {
    { ns = "Ess.Easy.Mark", usage = "Ess.Easy.Mark.enemy(uGuid)",
      desc = "Radar+PDA marker for a hostile unit (no world icon, matches WaveDefense's convention)." },
    { ns = "Ess.Easy.Mark", usage = "Ess.Easy.Mark.objective(uGuid)",
      desc = "Radar+PDA+world marker for a real mission objective." },
    { ns = "Ess.Easy.Mark", usage = "Ess.Easy.Mark.zone(x, y, z, r)",
      desc = "World-only ring marker for a 'go here' zone, no radar/PDA clutter." },

    { ns = "Ess.Easy.AIOrders", usage = "Ess.Easy.AIOrders.attack(guids, target)",
      desc = "Order a group of spawned units to attack a target guid." },
    { ns = "Ess.Easy.AIOrders", usage = "Ess.Easy.AIOrders.patrol(guids, points)",
      desc = "Order a group to patrol a list of {x,y,z} points." },
    { ns = "Ess.Easy.AIOrders", usage = "Ess.Easy.AIOrders.guard(guids, at)",
      desc = "Order a group to hold and defend a position." },
    { ns = "Ess.Raw.AIOrders", usage = "Ess.Raw.AIOrders.priorityTarget(g)",
      desc = "Makes hostile AI focus fire on this one guid -- boss fights, escort-defense." },
    { ns = "Ess.Raw.AIOrders", usage = "Ess.Raw.AIOrders.enable(g, bOn)",
      desc = "Freezes/unfreezes AI control of a subject -- hold it still for a scripted moment." },

    { ns = "Ess.Easy.Relations", usage = "Ess.Easy.Relations.makeHostile(factionList)",
      desc = "Every faction in the list becomes hostile to PMC." },
    { ns = "Ess.Easy.Relations", usage = "Ess.Easy.Relations.makeAllies(factionList)",
      desc = "Every pair within the list becomes mutually allied." },
    { ns = "Ess.Easy.Relations", usage = "Ess.Easy.Relations.restore()",
      desc = "Undo the last Easy.Relations change." },
    { ns = "Ess.Relations", usage = "Ess.Relations.setFeeling(uGuidA, uGuidB, n)",
      desc = "Sets how one specific character feels about another (not the whole faction)." },

    { ns = "Ess.Easy.Triggers", usage = "Ess.Easy.Triggers.onPlayerNear(x, y, z, r, fn)",
      desc = "Calls fn() once the player gets within r of a point." },
    { ns = "Ess.Easy.Triggers", usage = "Ess.Easy.Triggers.onDeath(uGuid, fn)",
      desc = "Calls fn() when a specific object dies." },
    { ns = "Ess.Easy.Triggers", usage = "Ess.Easy.Triggers.after(seconds, fn)",
      desc = "Calls fn() once, after a delay." },

    { ns = "Ess.Easy.Sandbox", usage = "Ess.Easy.Sandbox.arena(id, opts)",
      desc = "Isolates layers+economy+supports+relations for an ephemeral arena/minigame." },
    { ns = "Ess.Easy.Sandbox", usage = "Ess.Easy.Sandbox.done(id)",
      desc = "Restores everything an Easy.Sandbox.arena isolated." },

    { ns = "Ess.Easy (UI)", usage = "Ess.Easy.Toast(msg)",
      desc = "Shows a transient on-screen notification." },
    { ns = "Ess.Easy (UI)", usage = "Ess.Easy.Confirm(text, onYes, onNo)",
      desc = "Pops a yes/no dialog; onNo is optional." },
    { ns = "Ess.Easy (UI)", usage = "Ess.Easy.Menu(title, entries)",
      desc = "Opens a flat one-level menu from { {label,fn}, ... } or { [label]=fn }." },

    { ns = "Ess.Player", usage = "Ess.Player.character(i)",
      desc = "Local (0) or co-op partner (1) character guid; nils safely outside co-op." },
    { ns = "Ess.Player", usage = "Ess.Player.giveCash(n)",
      desc = "Gives cash from this machine's own wallet, routed through the call that refreshes the HUD." },
    { ns = "Ess.Player", usage = "Ess.Player.giveFuel(n)",
      desc = "Gives fuel from this machine's own wallet, routed through the call that refreshes the HUD." },
    { ns = "Ess.Player", usage = "Ess.Player.pose(i)",
      desc = "Returns x, y, z, yaw, char, player for player i." },
    { ns = "Ess.Player", usage = "Ess.Player.targetUnderReticle(i)",
      desc = "What player i is aiming at right now: uGuid, x, y, z (uGuid nil if nothing's targeted)." },
    { ns = "Ess.Player", usage = "Ess.Player.rumble(i, fLength)",
      desc = "Controller haptic feedback for player i -- a quick damage/impact/pickup buzz." },
    { ns = "Ess.Player", usage = "Ess.Player.removeBoundaries()",
      desc = "Lifts every active out-of-bounds volume, for every connected player at once." },
    { ns = "Ess.Player", usage = "Ess.Player.teleport(x, y, z, yaw)",
      desc = "Warps the player(s) to a world spot (the safe MrxUtil idiom, not raw SetPosition)." },
    { ns = "Ess.Easy (World)", usage = "Ess.Easy.World.removeMapBoundary()",
      desc = "Drops the invisible walls fencing you into the story-unlocked map -- roam the whole thing." },

    { ns = "Ess.Raw.Mark", usage = "Ess.Raw.Mark.pulse(uGuid, rgb)",
      desc = "Flashes an object's existing marker in a color -- draw attention to it." },

    { ns = "Ess.Track", usage = "Ess.Track.new()",
      desc = "A cleanup tracker: t:event(h)/:guid(u)/:marker(h)/:qualityRef(u,n)/:disposer(u,cat), then t:closeAll()." },

    { ns = "Ess.Easy (Vehicle)", usage = "Ess.Easy.Vehicle.summon(sTemplate)",
      desc = "Spawns a vehicle in front of you and puts you in the driver seat -- e.g. \"UH1 Transport\"." },
    { ns = "Ess.Object", usage = "Ess.Object.spawn(sTemplate, x, y, z, yaw)",
      desc = "Spawns a template at a spot and returns its guid (blank-template crash guard built in)." },
    { ns = "Ess.Object", usage = "Ess.Object.spawnAhead(sTemplate, nDist, nHeight)",
      desc = "Spawns a template in front of the player -- hides the 'in front of me' yaw/trig math." },
    { ns = "Ess.Object", usage = "Ess.Object.pos(uGuid) / .setPos(uGuid, x, y, z)",
      desc = "Read or set an object's world position." },
    { ns = "Ess.Object", usage = "Ess.Object.health(uGuid) / .setHealth(uGuid, n) / .heal(uGuid)",
      desc = "Read/set health, or heal to full." },
    { ns = "Ess.Object", usage = "Ess.Object.damage(uGuid, nAmount)",
      desc = "Deal damage (kills outright if it would drop to <= 0) -- there's no native damage call." },
    { ns = "Ess.Object", usage = "Ess.Object.kill(uGuid) / .remove(uGuid) / .alive(uGuid)",
      desc = "Kill (leaves a wreck), remove (deletes outright), or check if still alive." },
    { ns = "Ess.Object", usage = "Ess.Object.impulse(uGuid, x, y, z, bLocal)",
      desc = "Applies a physics impulse -- launch or knock an object around (scale by its mass)." },
    { ns = "Ess.Object", usage = "Ess.Object.setVisible(uGuid, bOn) / .hasLabel(uGuid, s)",
      desc = "Show/hide an object, or test a label like \"PMC\"." },
    { ns = "Ess.Object", usage = "Ess.Object.distance(uGuidA, uGuidBOrX, y, z)",
      desc = "Distance to another object OR to raw x,y,z coordinates -- one call either way." },

    { ns = "Ess.Sound", usage = "Ess.Sound.cue(uGuidOrNil, sCueName)",
      desc = "Plays a sound effect; nil guid = a plain UI/HUD one-shot with no world position." },
    { ns = "Ess.Sound", usage = "Ess.Sound.ambience(sStreamName)",
      desc = "Starts an ambience loop stream (pair with Ess.Sound.stopAmbience)." },
    { ns = "Ess.Easy (Sound)", usage = "Ess.Easy.Sound.play(sCueName)",
      desc = "Plays a plain UI sound effect, no guid to think about." },

    { ns = "Ess.Human", usage = "Ess.Human.doAction(uChar, sActionName)",
      desc = "Plays a scripted action/pose on a character, e.g. \"Cower\", \"Stand\"." },
    { ns = "Ess.Human", usage = "Ess.Human.equipWeapon(uChar, uWeapon)",
      desc = "Swaps a character's held weapon for a weapon guid (from primaryWeapon/secondaryWeapon)." },
    { ns = "Ess.Human", usage = "Ess.Human.refillAmmo(uWeapon)",
      desc = "Tops up a weapon's reserve ammo to its max." },
    { ns = "Ess.Human", usage = "Ess.Human.setInfiniteAmmo(uChar, bOn)",
      desc = "Keeps reserve ammo maxed forever (the current magazine still needs reloading)." },
    { ns = "Ess.Human", usage = "Ess.Human.knockdown(uChar, nDuration)",
      desc = "Knocks a character down for nDuration seconds." },
    { ns = "Ess.Easy (Human)", usage = "Ess.Easy.Human.giveWeapon(uChar, sTemplateName)",
      desc = "Gives a character a weapon by template name, e.g. \"Grenade Launcher\" -- no spawning needed." },

    { ns = "Ess.Vehicle", usage = "Ess.Vehicle.exit(uVeh, uChar)",
      desc = "Gets a character back out of a vehicle." },

    { ns = "Ess.Easy (Contract)", usage = "Ess.Easy.Contract.destroy(title, spawns, opts)",
      desc = "Registers and accepts a one-objective \"kill these\" contract in one call." },
    { ns = "Ess.Easy (Contract)", usage = "Ess.Easy.Contract.reach(title, at, radius, opts)",
      desc = "Registers and accepts a one-objective \"go here\" contract in one call." },

    { ns = "Ess.Hud", usage = "Ess.Hud.hint(sMsg, sId)",
      desc = "Shows the native tutorial-style hint popup (icon+sound) with your own text." },
    { ns = "Ess.Hud", usage = "Ess.Hud.banner(sMsg)",
      desc = "A clean, icon-free, centered text banner across the middle of the screen." },

    { ns = "Ess.Easy (Camera)", usage = "Ess.Easy.Camera.shake(i)",
      desc = "Shakes player i's camera, no preset name/amplitude to think about." },
    { ns = "Ess.Camera", usage = "Ess.Camera.fov(i, nAngle, nDuration)",
      desc = "Blends player i's field-of-view to a new angle over nDuration seconds (a zoom effect)." },
    { ns = "Ess.Easy (Camera)", usage = "Ess.Easy.Camera.fadeOut() / .fadeIn()",
      desc = "Full-screen fade to black / back in -- a mission-start/end or cutscene transition." },
    { ns = "Ess.Raw.Mark", usage = "Ess.Raw.Mark.showPlayerMarkers(bOn)",
      desc = "Global on/off for other players' HUD markers -- hide during a cutscene, restore after." },
    { ns = "Ess.Input", usage = "Ess.Input.usingController()",
      desc = "True if the player's using a gamepad -- branch a HUD prompt's wording on it." },

    { ns = "Ess.Time", usage = "Ess.Time.cooldown(seconds)",
      desc = "Returns a ready() function -- call it anytime, true at most once per `seconds` window." },
    { ns = "Ess.Time", usage = "Ess.Time.elapsed(uStamp)",
      desc = "Seconds since a Ess.Time.stamp() was marked -- polled elapsed-time, no callback needed." },
    { ns = "Ess.Time", usage = "Ess.Time.format(nSeconds, bUseTenths)",
      desc = "Formats a raw seconds value into a display string, e.g. for a HUD timer/countdown." },
    { ns = "Ess.Easy (Time)", usage = "Ess.Easy.Time.slowmo(n, seconds)",
      desc = "Slows the game to speed n (default 0.2) for `seconds`, then auto-restores normal speed." },

    { ns = "Ess", usage = "Ess.Log(msg)",
      desc = "Prints a line to the Lua bridge log (lua_loader_printf.log)." },
    { ns = "Ess.TextConsole", usage = "Ess.TextConsole.open{ onSubmit = fn }",
      desc = "Opens a free-text typed console (Enter submits, Escape cancels)." },
    { ns = "Ess.Contract", usage = "Ess.Contract.Status()",
      desc = "Progress/timeLeft/objectives of the currently active contract, or nil." },
    { ns = "Ess.RNG", usage = "Ess.RNG.new(seed)",
      desc = "An engine-safe random number generator (avoids the 32-bit-float big-LCG trap)." },
}

local S = { board = nil, view = nil }   -- S.view = currently-displayed (possibly filtered) list, nil = full

local function buildRows(list)
    local rows, lastNs = {}, nil
    rows[1] = { label = "[ Search... ]", any = "search" }
    for _, e in ipairs(list) do
        if e.ns ~= lastNs then rows[#rows + 1] = { header = e.ns }; lastNs = e.ns end
        rows[#rows + 1] = { label = e.usage, any = e }
    end
    return rows
end

local function showDetail(board, entry)
    if entry == "search" or not entry then
        board:detail({ category = "Pick a row, or Enter 'Search...' to filter", objectives = {} })
        return
    end
    board:detail({ category = entry.usage, objectives = Ess.UI.wrap(entry.desc, 40), rewards = { entry.ns } })
end

local function openBoard(list)
    S.view = list
    local rows = buildRows(list)
    if not S.board then
        S.board = Ess.UI.Board({
            title = "ESS EASY REFERENCE", hint = "UP/DOWN MOVE   ENTER PICK/LOG   LEFT CLOSE",
            items = rows, focus = true,
            onSelect = function(it) showDetail(S.board, it and it.any) end,
            onChoose = function(it)
                local e = it and it.any
                if e == "search" then
                    Ess.Easy.Console.search()
                elseif e then
                    Ess.Log("USAGE: " .. e.usage .. "  -- " .. e.desc)
                    Ess.UI.Toast("Logged usage -- check the log")
                end
            end,
            onBack = function() Ess.Easy.Console.close() end,
        })
    else
        S.board:items(rows):show():focus()
    end
end

-- Ess.Easy.Console.open() -- browse the full registry, grouped by namespace.
function Ess.Easy.Console.open()
    openBoard(REGISTRY)
end

-- Ess.Easy.Console.search() -- typed substring filter (name/usage/desc, case-insensitive) over the
-- registry; re-opens the board with only the matches. An empty search shows everything again.
function Ess.Easy.Console.search()
    Ess.TextConsole.open({
        prompt = "SEARCH> ",
        lockPlayer = false,
        onSubmit = function(text)
            local q = tostring(text or ""):lower()
            if q == "" then openBoard(REGISTRY); return end
            local matches = {}
            for _, e in ipairs(REGISTRY) do
                local hay = (e.ns .. " " .. e.usage .. " " .. e.desc):lower()
                if hay:find(q, 1, true) then matches[#matches + 1] = e end
            end
            openBoard(matches)
            local msg = #matches .. " match" .. (#matches == 1 and "" or "es") .. " for '" .. text .. "'"
            Ess.UI.Toast(msg)
            Ess.Log("Easy.Console: " .. msg)
        end,
    })
end

function Ess.Easy.Console.close()
    if S.board then S.board:hide():blur() end
    if Ess.TextConsole.isOpen() then Ess.TextConsole.close() end
end
