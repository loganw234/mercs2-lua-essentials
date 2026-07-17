local KEYVAL = "f7"  -- must be in the first 10 lines (loader auto-binds this key)

-- =====================================================================
-- MissionForge - an in-game mission AUTHORING tool (optional companion to ForgeCam).
--
-- WHAT IT IS
--   A player-driven placement editor for building a whole custom contract in-game, then dumping a
--   paste-ready chunk to the log for the MissionForge web tool (which turns it into a
--   Contract.Register{} block + lets you fill in the text/reward details offline).
--
-- THE MODEL (drop-at-your-feet - deliberately lightweight, no live preview)
--   * Runs in the LIVE, UNPAUSED world. You just WALK your merc around; the drop point is ALWAYS
--     the character's feet. A cheap cursor - a ring + a floating marker ANCHORED TO THE PLAYER (so
--     the marker system follows you for free) - shows where the next placement lands.
--   * There is NO following ghost/preview and NO forward reticle. That preview (respawning a unit and
--     repositioning it every frame) was the performance hit; this design removes it entirely, so the
--     per-tick work is just draining the keyboard.
--   * We never spawn the real unit (unpaused, it would move/shoot/start a firefight). Each placement
--     leaves an INERT marker and RECORDS the real template you picked:
--         - infantry  -> a faction-matched "Supply Drop (...)" crate + faction-coloured blip
--         - vehicles  -> the EMPTY variant of the chosen vehicle (crew suffix stripped)
--         - props     -> the prop itself
--         - objectives-> a ground ring + objective marker (radar/PDA/world) on a TinyGeometry anchor
--       ...but the export still carries the REAL template (e.g. "HMMWV (Softtop) (Full)").
--       Set SPAWN_PHYSICAL_MARKER=false below to use inert TinyGeometry markers for units too (even
--       lighter) if the crates/vehicles ever cost too much.
--   * Facing: a placed unit records the direction your character was facing at drop time.
--   * Heartbeat is a self-re-arming Event.TimerRelative (works because we're unpaused; a generation
--     counter self-terminates it on toggle-off). It only drains the keyboard + eases the panel now.
--
-- CONTROLS (unpaused; keep the PDA CLOSED)
--   F7             toggle MissionForge on/off
--   walk around    the drop point is your character's feet (the ring + marker show it)
--   Up / Down      menu up / down          Left / Right   back / open (into a faction or OBJECTIVES)
--   P or Enter     place at your feet      Backspace      undo the last placement
--   Delete         remove nearest to you   End            dump the export to the log
--   , / .          objective zone radius - / +            T   cycle GROUP tag
--   The menu also has an EXPORT node. Highlighting a leaf makes it the active "brush".
--   (There is intentionally NO wipe-all key - Backspace undoes one at a time.)
--
--   GROUP TAG: units, objectives AND AI orders placed while a group is active share that tag, so the
--   web tool knows which units a "Destroy/Verify/Protect/Escort" objective refers to - and which units
--   an AI order commands. Bump the group (T) when you start a new cluster; leave it to keep adding to
--   the current one. To order a group: cycle to its letter (T), pick an AI ORDER, drop the point(s).
--
-- WHAT IT EXPORTS  (one evaluable Lua table, printed to lua_loader_printf.log)
--   MISSIONFORGE_EXPORT = {
--     name = "forge_<t>", anchor = { x=, y=, z= },
--     spawns = { { x=, y=, z=, yaw= }, ... },   -- optional player teleport point(s); co-op = 1 per hero
--     units = { { faction=, kind=, spawn=, placeholder=, x=, y=, z=, yaw=, group= }, ... },
--     objectives = { { type=, x=, y=, z=, radius=, yaw=, group= }, ... },
--     support = { { effect=, x=, y=, z=, radius=, group= }, ... },     -- artillery/flyby/heli/reinforce zones
--     triggers = { { x=, y=, z=, radius=, group= }, ... },             -- generic trigger zones
--     orders = { { behavior=, x=, y=, z=, radius=, group= }, ... },    -- AI orders (move/patrol/defend/attack/hold/face)
--   }
--   (the web tool fills the rest: owner / ammo / spawns / trigger mode / relations / trigger.fires)
--
-- KEY CONFLICTS: because we're unpaused, these keys are read by the lua-bridge AND may also be bound
--   to game actions on PC (arrows/Enter are usually free with WASD movement). Remap freely in KEYMAP.
--   Input drains the bridge key ring (Loader.PopKeyEvents) once per tick: every press since the last
--   tick fires in order, focus-gated (alt-tabbed keystrokes are dropped), and no tap can slip between
--   ticks because edges are sampled C-side at ~60Hz. Held radius keys read one GetKeyboardState snapshot.
--
-- DEPLOY: this file in scripts/OnKey/ (F7 auto-binds); reuses the SAME forge.gfx already injected
--   for ForgeCam - nothing new to inject.
-- =====================================================================

import("MrxUtil")   -- MrxUtil.GetPrimaryObjectiveRgb (objective colour); everything else routes through Ess

-- =====================================================================
-- Essentials dependency. MissionForge is now a CONSUMER of the Ess framework (spawn / markers / input /
-- heartbeat / widget / timing all go through Ess.* instead of hand-rolled natives) rather than a fully
-- standalone script. Ess must be deployed as an OnLoad script (dist/Ess.lua as e.g. 1_Ess.lua) so it's
-- loaded before this OnKey runs. If it isn't, bail loudly instead of erroring deep in a handler.
-- =====================================================================
local Ess = _G.Ess
if not Ess then
    if Loader and Loader.Printf then
        Loader.Printf("MissionForge: ERROR - the Ess (Essentials) framework is not loaded. Deploy dist/Ess.lua "
            .. "as an OnLoad script (e.g. scripts/OnLoad/1_Ess.lua) before using MissionForge.")
    end
    return
end

-- =====================================================================
-- Persistent state (survives the OnKey re-run on each keypress).
-- =====================================================================
_G.MissionForge = _G.MissionForge or {}
local F = _G.MissionForge
F.active   = F.active or false
F.items    = F.items or {}      -- committed placements: { cat="unit"|"obj", u, ... }
F.brush    = F.brush or nil     -- active template: { real/kind/faction/placeholder, or obj }
F.cursor   = F.cursor or nil    -- foot ring + marker anchored to the player character
F.stack    = F.stack or nil     -- menu nav stack, rebuilt on activate
F.radius   = F.radius or 15     -- current objective zone radius
F.group    = F.group or "A"
F.now      = F.now or 0
F.panelCur = F.panelCur or 100
F.panelTgt = F.panelTgt or 100

-- =====================================================================
-- 1. CATALOG  (faction rosters + an OBJECTIVES branch + EXPORT).
--    Unit leaves are stamped with faction+kind by prepare_catalog() (kind decides the placeholder:
--    infantry->crate, vehicle->empty variant, prop->the prop). Objective leaves carry obj="<type>".
--    Each faction also gets a SQUADS branch (built from SQUAD_ROLES x SQUAD_TYPES): one drop places a
--    whole preset squad (3..24 units) in a grid formation at your feet, all in the current group; a
--    single Backspace undoes the entire squad (units share a `sq` id).
-- =====================================================================
local function L(s) return { label = s, id = s } end   -- leaf whose label == spawn template
local CATALOG = {
    { label = "GUERILLA", children = {
        { label = "INFANTRY", children = {
            L("Guerilla Heavy (Light MG)"), L("Guerilla Heavy (RPG)"), L("Guerilla Boss"),
            L("Guerilla Elite Soldier"), L("Guerilla Heavy"), L("Guerilla Officer"),
            L("Guerilla Officer (Female)"), L("Guerilla Prisoner"), L("Guerilla Soldier"),
            L("Guerilla Soldier (Female)"), L("Guerilla Soldier B"),
            L("Guerilla Soldier B (Female)"), L("Guerilla Tank Commander"), L("Guerilla Worker"),
        }},
        { label = "VEHICLES", children = {
            L("M551"), L("M551 (Full)"),                                    -- Cavalera Light Tank
            L("M151 (MG) (GR)"), L("M151 (MG) (GR) (DriverGunner)"),        -- Corales MG
            L("M113 (GR)"), L("M113 (GR) (Full)"),                          -- Martinez APC
            L("M113 AA (GR)"), L("M113 AA (GR) (Full)"),                    -- Martinez AA
            L("M35 (Cargo) (GR)"), L("M35 (Cargo) (GR) (Full)"),            -- Bolivar Truck
            L("M35 (Guntruck) (GR)"), L("M35 (Guntruck) (GR) (Full)"),      -- Bolivar Guntruck
            L("M35 (AA) (GR)"), L("M35 (AA) (GR) (Full)"),                  -- Bolivar AA
        }},
        { label = "HELICOPTERS", children = {
            L("UH1 Transport (GR)"), L("UH1 Transport (GR) (Full)"),        -- Castro Transport
            L("UH1 Attack"), L("UH1 Superiority"), L("UH1 Elite"),          -- Castro / Castro-V / Castro-II
        }},
        { label = "BOATS", children = {
            L("Piranha"), L("Piranha (Full)"),                              -- Prestes Patrol Boat
            L("Turbosquid (GR)"), L("Turbosquid (GR) (Full)"),             -- Cardenas Scout Boat
        }},
    }},
    { label = "ALLIED", children = {
        { label = "INFANTRY", children = {
            L("Allied Airborne (Light MG)"), L("Allied Heavy (Light MG)"), L("Allied Sailor (Light MG)"),
            L("Allied Airborne"), L("Allied Airborne (AT)"), L("Allied Boss"),
            L("Allied Heavy (AA)"), L("Allied Heavy (AT Rocket)"), L("Allied Medic"), L("Allied Officer"),
            L("Allied Paratrooper"), L("Allied Pilot"), L("Allied Prisoner"),
            L("Allied Sailor"), L("Allied Sailor (AA)"), L("Allied Soldier"), L("Allied Worker"),
        }},
        { label = "HELICOPTERS", children = {
            L("AH1Z"), L("AH1Z (Driver)"), L("AH1Z (Full)"),                -- Ambassador Attack Copter
            L("MH53J"), L("MH53J (Full)"),                                  -- Liberator Cargo Copter
        }},
        { label = "VEHICLES", children = {
            L("M1A2"), L("M1A2 (Full)"),                                    -- Diplomat Heavy Tank
            L("M2A3"), L("M2A3 (Driver)"),                                  -- Statesman IFV
            L("HMMWV (Armored) (50Cal)"), L("HMMWV (Armored) (50Cal) (Full)"),
            L("HMMWV (Armored) (GL)"), L("HMMWV (Armored) (GL) (Full)"),
            L("HMMWV (Armored) (TOW)"), L("HMMWV (Armored) (TOW) (Full)"),
            L("HMMWV (Avenger)"), L("HMMWV (Avenger) (Full)"), L("HMMWV (Softtop)"),
            L("HMMWV (Softtop) (Full)"),
            L("LAVIII (25mm)"), L("LAVIII (25mm) (Full)"), L("LAVIII (AT)"), L("LAVIII (AT) (Full)"),
            L("LAVIII (Minigun)"), L("LAVIII (Minigun) (Full)"),
            L("LAVIII (AD)"), L("LAVIII (AD) (Full)"),                      -- Guardian AA
        }},
        { label = "BOATS", children = {
            L("LCUR"), L("LCUR (heavy)"), L("LCUR (light)"), L("LCUR (medium)"),
            L("MarkV"), L("MarkV (Full)"),                                  -- Freedom Patrol Boat
            L("Omen"), L("Omen (Full)"),                                    -- Warhorse Patrol Boat
        }},
        { label = "EMPLACEMENTS", children = {
            L("Emplaced Recoiless Rifle (Allied)"), L("Emplaced MG3 (Allied)"), L("Emplaced TOW (Allied)"),
        }},
    }},
    { label = "CHINA", children = {
        { label = "INFANTRY", children = {
            L("Chinese Airborne (Light MG)"), L("Chinese Heavy (Light MG)"), L("Chinese Heavy (RPG)"),
            L("Chinese Airborne"), L("Chinese Airborne (AT)"), L("Chinese Boss"),
            L("Chinese Elite Soldier"), L("Chinese Heavy (AA)"), L("Chinese Medic"), L("Chinese Officer"),
            L("Chinese Paratrooper"), L("Chinese Sailor"), L("Chinese Sniper"), L("Chinese Soldier"),
            L("Chinese Tank Commander"), L("Chinese VIP"), L("Chinese Worker"),
        }},
        { label = "VEHICLES", children = {
            L("ZTZ98"), L("ZTZ98 (Full)"),                                  -- Iron Mountain Heavy Tank
            L("ZTZ63a"), L("ZTZ63a (Full)"),                                -- Dragon Lance Light Tank
            L("NGLV (MG)"), L("NGLV (MG) (Full)"),                          -- Leaping Fox
            L("NGLV (GL)"), L("NGLV (GL) (Full)"),                          -- Leaping Fox GL
            L("WZ551"), L("WZ551 (Full)"),                                  -- Salamander APC
            L("PLZ45"), L("PLZ45 (Full)"),                                  -- Tempered Hammer Tank
            L("ZBD2000"), L("ZBD2000 (Full)"),                              -- Sundered Dragonfly IFV
            L("SX2150 (MLRS)"), L("SX2150 (MLRS) (Full)"),                  -- Armored Tiger MLRS
            L("PGZ95"), L("PGZ95 (Driver)"),                                -- Iron Dove AA Tank
        }},
        { label = "HELICOPTERS", children = {
            L("WZ10"), L("WZ10 (Full)"),                                    -- Warsong Attack Helicopter
            L("Ka29b"), L("Ka29b (Full)"),                                  -- Locust Assault Helicopter
            L("Mi26 (CH)"), L("Mi26 (CH) (Driver)"),                        -- Jade Wind Heavy Transport
        }},
        { label = "BOATS", children = {
            L("Huangfeng"), L("Huangfeng (Driver)"),                        -- Bladesong Missile Boat
        }},
    }},
    { label = "OC (OIL)", children = {
        { label = "INFANTRY", children = {
            L("OC Heavy (Light MG)"), L("OC Heavy (RPG)"), L("OC Heavy (Grenade Launcher)"),
            L("OC Boss"), L("OC Defender (AA)"), L("OC Defender (AT)"), L("OC Defender (MG)"),
            L("OC Defender (Rifle)"), L("OC Defender (Sniper)"), L("OC Elite"), L("OC Executive"),
            L("OC Officer"), L("OC Pilot"), L("OC Prisoner"), L("OC Sniper"), L("OC Soldier"),
            L("OC Tank Commander"), L("OC Worker"),
        }},
        { label = "VEHICLES", children = {
            L("Stingray II"), L("Stingray II (Full)"),                      -- Mantis Light Tank
            L("EXT"), L("EXT (Full)"),                                      -- Raven
            L("EXT (GL)"), L("EXT (GL) (Full)"),                            -- Raven GL
            L("EXT (TOW)"), L("EXT (TOW) (Full)"),                          -- Raven AT
            L("Guntruck (OC)"), L("Guntruck (OC) (Full)"),                  -- Archer Guntruck
        }},
        { label = "HELICOPTERS", children = {
            L("Coanda Gunship"), L("Coanda Gunship (Full)"),                -- Rogue Assassin
            L("Coanda Superiority"), L("Coanda Superiority (Full)"),        -- Rogue AT
            L("Coanda Attack"), L("Coanda Attack (Full)"),                  -- Rogue Combat
        }},
        { label = "BOATS", children = {
            L("Turbosquid (OC)"), L("Turbosquid (OC) (Full)"),             -- UP Inflatable Scout Boat
        }},
    }},
    { label = "PIRATE", children = {
        { label = "INFANTRY", children = {
            L("Pirate Officer (RPG)"), L("Pirate Thug (RPG)"), L("Pirate Officer"), L("Pirate Pilot"),
            L("Pirate Prisoner"), L("Pirate Sailor"), L("Pirate Thug"),
            L("Pirate Thug (AA)"), L("Pirate Thug (Female)"), L("Pirate Thug (Shotgun)"), L("Pirate Worker"),
        }},
        { label = "VEHICLES", children = { L("T300 (M60)") }},
        { label = "HELICOPTERS", children = {
            L("Alouette3 Attack (PR)"), L("Alouette3 Attack (PR) (Full)"),  -- Pirate gunship
            L("Alouette3 Transport (PR)"), L("Alouette3 Transport (PR) (Full)"),
        }},
        { label = "BOATS", children = {
            L("Cutter (PR)"), L("Cutter (PR) (Full)"),                      -- Culican Cutter
        }},
    }},
    { label = "VZ", children = {
        { label = "INFANTRY", children = {
            L("VZ Heavy (Light MG)"), L("VZ Heavy (RPG)"), L("VZ Heavy (AA Missile)"),
            L("VZ Heavy (Heavy MG)"), L("VZ Captain"), L("VZ Deathsquad"), L("VZ Defender (AA)"),
            L("VZ Defender (AT)"), L("VZ Defender (MG)"), L("VZ Defender (Rifle)"),
            L("VZ Defender (Sniper)"), L("VZ Elite"), L("VZ HVT01"), L("VZ HVT02"), L("VZ HVT03"),
            L("VZ Officer"), L("VZ Sniper"), L("VZ Soldier"), L("VZ Tank Commander"),
        }},
        { label = "VEHICLES", children = {
            L("AMX30 Elite"), L("AMX30 Elite (Full)"),                      -- Jaguar Heavy Tank
            L("AMX30 AA"), L("AMX30 AA (Driver)"),                          -- Mosquito Tank
            L("Scorpion90"), L("Scorpion90 (Full)"),                        -- Puma Light Tank
            L("M151 .50Cal (VZ)"), L("M151 .50Cal (VZ) (Full)"),           -- Iguana MG
            L("M113 (VZ)"), L("M113 (VZ) (Full)"),                          -- Armadillo APC
            L("M113 AA (VZ)"), L("M113 AA (VZ) (Full)"),                    -- Armadillo AA
            L("M35 (Guntruck) (VZ)"), L("M35 (Guntruck) (VZ) (Full)"),      -- Capuchin Guntruck
            L("M35 (AA) (VZ)"), L("M35 (AA) (VZ) (Full)"),                  -- Capuchin AA
        }},
        { label = "HELICOPTERS", children = {
            L("Mi35"), L("Mi35 (Full)"),                                    -- Anaconda
            L("Mi35 (AA)"),                                                 -- Anaconda AA (empty; crew via web tool)
            L("Alouette3 Elite"), L("Alouette3 Elite (Full)"),              -- Kestrel Tank Hunter
            L("Mi26 (VZ)"), L("Mi26 (VZ) (Driver)"),                        -- Condor Cargo Helicopter
        }},
        { label = "BOATS", children = {
            L("Patrol Boat (VZ)"), L("Patrol Boat (VZ) (Full)"),           -- Piranha Patrol Boat
            L("Type 14310"), L("Type 14310 (Full)"),                        -- Crocodile Gunboat
        }},
    }},
    { label = "PROPS / MISC", children = {
        L("Veyron"), L("Supply Drop (Blueprints)"), L("Supply Drop (Treasure)"),
        L("Cover (Barrel)"), L("Cover (Box)"), L("Cover (Sandbag)"),
    }},
    -- COMMUNITY SPAWN STRINGS (contributed): PMC heroes/vehicles, civilians, weapon pickups, and
    -- support aircraft. WEAPONS spawn as pickups (prop); SUPPORT AIRCRAFT + all vehicles are empty-variant.
    { label = "PMC", children = {
        { label = "INFANTRY", children = {
            L("Mattias"),
            L("MattiasV2"),
            L("MattiasV3"),
            L("MattiasChickensuit"),
            L("Chris"),
            L("ChrisV2"),
            L("ChrisV3"),
            L("ChrisChickensuit"),
            L("Jen"),
            L("JenV2"),
            L("JenV3"),
            L("JenV4"),
            L("JenV5"),
            L("JenChickensuit"),
            L("Fiona"),
            L("Fiona Tayor"),
            L("UnlockableFiona"),
            L("Recruit Ewen Garret"),
            L("Recruit Ewen Garret (Invincible)"),
            L("UnlockableEwan"),
            L("Recruit Eva Navarro"),
            L("Eva"),
            L("UnlockableEva"),
            L("Recruit Misha Milanich"),
            L("UnlockableMisha"),
            L("UnlockableAbel"),
            L("UnlockableBlanco"),
            L("UnlockableCarlos"),
            L("UnlockableDiablo"),
            L("UnlockableFire"),
            L("UnlockableGauge"),
            L("UnlockableGhost"),
            L("UnlockableHoang"),
            L("UnlockableVasquez"),
            L("UnlockableWingman"),
        }},
        { label = "VEHICLES", children = {
            L("Veyron (Assault)"),
            L("Veyron (Cannon)"),
            L("Veyron (Assault) (Driver)"),
        }},
        { label = "HELICOPTERS", children = {
            L("UH1 Attack (PMC)"),
            L("UH1 Transport (PMC)"),
            L("Mi26 (PMC)"),
            L("UH1 Attack (PMC) (Driver)"),
            L("UH1 Attack (PMC) (Driver) (Railshooter)"),
            L("UH1 Transport (PMC) (Driver)"),
            L("UH1 Transport (PMC) (Extraction)"),
            L("UH1 Transport (PMC) (Ghost)"),
            L("Mi26 (PMC) (Driver)"),
        }},
        { label = "BOATS", children = {
            L("Patrol Boat (PMC)"),
            L("Patrol Boat (PMC) (Driver)"),
        }},
    }},
    { label = "CIVILIANS", children = {
        { label = "INFANTRY", children = {
            L("Civ Beach A (Female)"),
            L("Civ Beach B (Female)"),
            L("Civ Beach C (Female)"),
            L("Civ Beach D (Female)"),
            L("Civ Business (male)"),
            L("Civ Business B (male)"),
            L("Civ Casual (female)"),
            L("Civ Casual with hat (female)"),
            L("Civ Casual (male)"),
            L("Civ Cowboy (male)"),
        }},
        { label = "VEHICLES", children = {
            L("Austin (Civ)"),
            L("Austin (Civ) (Full)"),
        }},
    }},
    { label = "WEAPONS", children = {
        { label = "Pistols", children = {
            L("pistol"),
            L("Covert Pistol"),
            L("Pistol (silver)"),
            L("Hunting Pistol"),
        }},
        { label = "Machine Pistols", children = {
            L("Machine Pistol (Uzi)"),
            L("Machine Pistol (TMP)"),
            L("machine pistol"),
            L("Machine Pistol (PP2000)"),
        }},
        { label = "Assault Rifles", children = {
            L("assault rifle"),
            L("assault rifle (vz)"),
            L("Bullpup Rifle"),
            L("combat rifle"),
            L("carbine"),
        }},
        { label = "Automatic Rifles", children = {
            L("Light MG"),
            L("Automatic Rifle"),
            L("Automatic Rifle (Chinese)"),
        }},
        { label = "SMGs", children = {
            L("sMG"),
            L("Covert SMG"),
        }},
        { label = "Sniper Rifles", children = {
            L("Sniper Rifle (SVD)"),
            L("Sniper Rifle"),
            L("Anti-Material Rifle"),
            L("Anti-Material Rifle (KSVK)"),
        }},
        { label = "Heavy", children = {
            L("AT Rocket"),
            L("Stinger"),
            L("RPG"),
            L("Fuel-Air RPG"),
            L("Grenade Launcher"),
            L("Grenade Launcher PEP"),
        }},
        { label = "Special", children = {
            L("Minigun"),
            L("Minigun 900"),
            L("minigun 1800"),
            L("minigun 1000"),
            L("Riot Gun"),
            L("Coilgun"),
            L("Cheat RPG"),
        }},
        { label = "EMPLACEMENTS", children = {
            L("Emplaced MG"),
            L("Emplaced MG (AL)"),
            L("Emplaced MG (CH)"),
            L("Emplaced MG (OC)"),
            L("Emplaced MG (Guerilla)"),
            L("Emplaced MG (PR)"),
            L("Emplaced MG (VZ)"),
            L("Emplaced MG (NO Physics)"),
            L("Emplaced MG DB"),
            L("Emplaced MG3 (OC)"),
            L("Emplaced GL"),
            L("Emplaced GL (NO Physics)"),
            L("Emplaced TOW"),
            L("Emplaced Recoiless Rifle"),
            L("Emplaced Recoiless Rifle (China)"),
            L("Emplaced Recoiless Rifle (OC)"),
            L("Emplaced Recoiless Rifle (GR)"),
            L("Emplaced Recoiless Rifle (VZ)"),
            L("Emplaced Quad50 (Driver)"),
            L("Emplaced Quad50 (GR)"),
            L("Emplaced M101A1 (Base)"),
            L("Emplaced M101A1 (GR)"),
            L("Emplaced M101A1 (VZ)"),
            L("Emplaced Tripod Weapon"),
            L("Emplaced Weapon"),
            L("Emplaced ZU23"),
        }},
    }},
    { label = "SUPPORT AIRCRAFT", children = {
            L("Support Vehicle (Mig27)"),
            L("Support Vehicle (Mig27) low altitude"),
            L("Support Vehicle (OV10)"),
            L("Support Vehicle (OV10) low altitude"),
            L("Support Vehicle (A10)"),
            L("Support Vehicle (A10) low altitude"),
            L("Support Vehicle (F35)"),
            L("Support Vehicle (F35) low altitude"),
            L("Support Vehicle (AC130)"),
            L("Support Vehicle (C130)"),
            L("Support Vehicle (C130) low altitude"),
            L("Support Vehicle (F117)"),
            L("Support Vehicle (F117) low altitude"),
            L("Support Vehicle (B2)"),
            L("Support Vehicle (B2) low altitude"),
            L("Support Vehicle (Q5)"),
            L("Support Vehicle (Q5) low altitude"),
            L("Support Vehicle (Tucano)"),
            L("Support Vehicle (Tucano) low altitude"),
            L("Support Vehicle (Cessna)"),
            L("Support Vehicle (Cessna) low altitude"),
            L("Support Vehicle (727)"),
            L("Support Vehicle (727) low altitude"),
    }},

    { label = "OBJECTIVES", children = {
        { label = "Player Spawn",        obj = "spawn" },
        { label = "Destroy (mark area)", obj = "destroy" },
        { label = "Reach / Go To",       obj = "reach" },
        { label = "Defend Area",         obj = "defend" },
        { label = "Collect Item",        obj = "collect" },
        { label = "Escort Destination",  obj = "escort" },
        { label = "Hold Position",       obj = "hold" },
        { label = "Interact Point",      obj = "interact" },
        { label = "Verify HVT",          obj = "verify" },
        { label = "Extraction Zone",     obj = "extract" },
        { label = "Race Checkpoint",     obj = "checkpoint" },
        { label = "Survive / Hold Out",  obj = "survive" },
        { label = "Chase / Intercept",   obj = "chase" },
    }},
    { label = "SUPPORT / TRIGGERS", children = {
        { label = "Artillery Zone",  obj = "support_artillery" },
        { label = "Airstrike Flyby", obj = "support_flyby" },
        { label = "Bombing Run",     obj = "support_bombingrun" },
        { label = "Heli Wave",       obj = "support_heli" },
        { label = "Reinforcement",   obj = "support_reinforce" },
        { label = "Music Cue",       obj = "support_music" },
        { label = "Explosion / VFX", obj = "support_vfx" },
        { label = "Scripted Damage", obj = "support_damage" },
        { label = "Voice-over",      obj = "support_vo" },
        { label = "Trigger Zone",    obj = "trigger" },
    }},
    -- AI orders command the CURRENT group's units (cycle the group with T first). Drop several
    -- "Patrol Point"s to build a route; the other orders take the single point you drop.
    { label = "AI ORDERS (per group)", children = {
        { label = "Move To",         obj = "order_move" },
        { label = "Patrol Point",    obj = "order_patrol" },
        { label = "Defend Area",     obj = "order_defend" },
        { label = "Attack / Hunt",   obj = "order_attack" },
        { label = "Hold Ground",     obj = "order_hold" },
        { label = "Face Point",      obj = "order_face" },
    }},
    -- CINEMATIC: author the intro cutscene by FLYING. "Give Helicopter" drops you an invincible heli (and
    -- makes you invincible) so you can fly to a vantage and drop camera points IN THE AIR. A "Loading
    -- Preview" is the establishing bird's-eye the mission opens on while the scene spawns + settles; "Camera
    -- Shot"s are the cutscene's vantages (position + the way you're facing); "Look-at Point"s are what a
    -- shot frames. Each captures your position + yaw at drop time -- so aim the camera by facing it.
    { label = "CINEMATIC", children = {
        { label = "Give Helicopter (fly)", action = "give_heli" },
        { label = "Loading Preview",       obj = "cine_preview" },
        { label = "Camera Shot",           obj = "cine_shot" },
        { label = "Look-at Point",         obj = "cine_look" },
    }},
    { label = "EXPORT PLACEMENTS", action = "export" },
}
local SORT_ITEMS = true

-- =====================================================================
-- 2. CONFIG (all the swappable content - forge.gfx never changes)
-- =====================================================================
local SPAWN_PHYSICAL_MARKER = true   -- true: spawn the faction crate / empty vehicle at each unit
                                     -- false: use an inert TinyGeometry + blip (even lighter)

-- Faction -> the crate template used to mark an infantry placement (faction-styled).
local FACTION_CRATE = {
    ["GUERILLA"] = "Supply Drop (Guerilla)",
    ["ALLIED"]   = "Supply Drop (Allied)",
    ["CHINA"]    = "Supply Drop (Chinese)",
    ["OC (OIL)"] = "Supply Drop (OC)",
    ["PIRATE"]   = "Supply Drop (Pirate)",
    ["VZ"]       = "Supply Drop (VZ)",
}
local DEFAULT_CRATE = "Supply Drop (Base)"

-- Faction -> blip/ring colour (for at-a-glance reading of who's where while authoring).
local FACTION_RGB = {
    ["GUERILLA"] = { 80, 220, 80 },
    ["ALLIED"]   = { 80, 160, 255 },
    ["CHINA"]    = { 255, 80, 80 },
    ["OC (OIL)"] = { 255, 180, 40 },
    ["PIRATE"]   = { 200, 120, 255 },
    ["VZ"]       = { 235, 235, 235 },
    ["PMC"]      = { 60, 210, 255 },      -- the player's own faction (bright cyan)
    ["CIVILIANS"]= { 230, 220, 120 },     -- civilians (pale yellow)
    ["WEAPON"]   = { 255, 90, 160 },      -- weapon pickups (pink)
    ["AIRCRAFT"] = { 150, 190, 255 },     -- support aircraft (pale blue)
}
local DEFAULT_RGB = { 200, 200, 200 }
local SPAWN_RGB   = { 0, 230, 200 }   -- player-spawn marker colour (teal, distinct from objectives)
local SUPPORT_RGB = { 255, 140, 58 }  -- support call-in zones (orange)
local TRIGGER_RGB = { 200, 120, 255 } -- generic trigger zones (purple)
local ORDER_RGB   = { 180, 230, 60 }  -- AI order waypoints (lime; "these units go here")
local CINE_RGB    = { 120, 200, 255 } -- cinematic camera / look points (sky blue)

-- Crew suffixes: a vehicle's EMPTY (placeholder) name is the chosen name with one of these removed.
local CREW_SUFFIXES = {
    " (Full RPG)", " (DriverGunner)", " (Driver)", " (Full)", " (Gunner)", " (Ewan)",
}

-- Objective type -> icon pair (radar / world), from the shipped MrxTaskObjective subclasses.
local OBJ_ICON = {
    destroy    = { rdr = "objective_destroy",     wld = "HUD_objective_destroy" },
    verify     = { rdr = "objective_verify",      wld = "HUD_objective_verify" },
    defend     = { rdr = "objective_defend",      wld = "HUD_objective_defend" },
    hold       = { rdr = "objective_defend",      wld = "HUD_objective_defend" },
    survive    = { rdr = "objective_defend",      wld = "HUD_objective_defend" },
    chase      = { rdr = "objective_destroy",     wld = "HUD_objective_destroy" },
    collect    = { rdr = "objective_action",      wld = "HUD_objective_action" },
    interact   = { rdr = "objective_action",      wld = "HUD_objective_action" },
    reach      = { rdr = "objective_deliverable", wld = "HUD_objective_deliverable" },
    escort     = { rdr = "objective_deliverable", wld = "HUD_objective_deliverable" },
    extract    = { rdr = "objective_deliverable", wld = "HUD_objective_deliverable" },
    checkpoint = { rdr = "objective_deliverable", wld = "HUD_objective_deliverable" },
}

-- 3. LAYOUT CONSTANTS (must match forge.gfx - same as ForgeCam)
local VISIBLE   = 12
local ROW_PITCH = 26
local TRACK_Y   = 88
local TRACK_H   = 316
local PANEL_H   = 324

-- 4. KEYMAP (Windows VK codes; unpaused = arrow keys are free again, no PDA lock)
local K_MENU_UP   = 0x26  -- Up arrow     menu up
local K_MENU_DOWN = 0x28  -- Down arrow   menu down
local K_MENU_OPEN = 0x27  -- Right arrow  open / into
local K_MENU_BACK = 0x25  -- Left arrow   back / out
local K_DROP      = 0x50  -- P            place at your feet
local K_DROP2     = 0x0D  -- Enter        place (alternate)
local K_UNDO      = 0x08  -- Backspace    remove the LAST placement (undo)
local K_REMOVE    = 0x2E  -- Delete       remove the nearest placement to you
local K_EXPORT    = 0x23  -- End          dump the export to the log
local K_GROUP     = 0x54  -- T            cycle group tag
local K_RAD_DN    = 0xBC  -- ,            objective radius -
local K_RAD_UP    = 0xBE  -- .            objective radius +

local TICK              = 0.05   -- heartbeat interval (s); ~10Hz (PERF TEST: halved from 0.05/20Hz)
local RAD_SPEED        = 20      -- objective radius units/sec while , . held
local CURSOR_UNIT_RADIUS = 2.5   -- foot-ring size when a unit is the active brush

-- =====================================================================
-- small helpers
-- =====================================================================
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi else return v end end

-- =====================================================================
-- Catalog prep: stamp faction+kind onto unit leaves so Place knows the placeholder to use.
-- =====================================================================
local function emptyVariant(name)
    for _, sfx in ipairs(CREW_SUFFIXES) do
        if string.sub(name, -string.len(sfx)) == sfx then
            return string.sub(name, 1, string.len(name) - string.len(sfx))
        end
    end
    return name   -- already the base/empty variant
end
-- =====================================================================
-- SQUADS: preset groups of units. A "role -> template" map per faction + a set of archetype squad
-- shapes are combined into one SQUADS menu branch per faction (built in prepare_catalog). Placing a
-- squad drops every unit in a formation at your feet, all sharing the current group (so one AI order
-- commands the whole squad). Missing roles are skipped, so squad sizes vary a little by faction.
-- =====================================================================
local SQUAD_ROLES = {
    ["GUERILLA"] = { off="Guerilla Officer", rifle="Guerilla Soldier", rifle2="Guerilla Soldier B",
        mg="Guerilla Heavy (Light MG)", at="Guerilla Heavy (RPG)", heavy="Guerilla Heavy",
        elite="Guerilla Elite Soldier", boss="Guerilla Boss", tank="M551 (Full)", apc="M113 (GR) (Full)",
        truck="M151 (MG) (GR)", heli="UH1 Attack" },
    ["ALLIED"] = { off="Allied Officer", rifle="Allied Soldier", mg="Allied Heavy (Light MG)",
        at="Allied Heavy (AT Rocket)", aa="Allied Heavy (AA)", medic="Allied Medic", elite="Allied Airborne",
        boss="Allied Boss", tank="M1A2 (Full)", apc="LAVIII (25mm) (Full)", truck="HMMWV (Armored) (50Cal) (Full)", heli="AH1Z (Full)" },
    ["CHINA"] = { off="Chinese Officer", rifle="Chinese Soldier", mg="Chinese Heavy (Light MG)",
        at="Chinese Heavy (RPG)", aa="Chinese Heavy (AA)", sniper="Chinese Sniper", elite="Chinese Elite Soldier",
        boss="Chinese Boss", tank="ZTZ98 (Full)", apc="WZ551 (Full)", truck="NGLV (MG) (Full)", heli="WZ10 (Full)" },
    ["OC (OIL)"] = { off="OC Officer", rifle="OC Soldier", mg="OC Heavy (Light MG)", at="OC Heavy (RPG)",
        aa="OC Defender (AA)", sniper="OC Sniper", elite="OC Elite", boss="OC Boss", tank="Stingray II (Full)",
        apc="EXT (Full)", truck="Guntruck (OC) (Full)", heli="Coanda Gunship (Full)" },
    ["PIRATE"] = { off="Pirate Officer", rifle="Pirate Thug", at="Pirate Thug (RPG)", aa="Pirate Thug (AA)",
        elite="Pirate Officer (RPG)", boss="Pirate Officer (RPG)", truck="T300 (M60)", heli="Alouette3 Attack (PR) (Full)" },
    ["VZ"] = { off="VZ Officer", rifle="VZ Soldier", mg="VZ Heavy (Light MG)", at="VZ Heavy (RPG)",
        aa="VZ Heavy (AA Missile)", sniper="VZ Sniper", elite="VZ Elite", boss="VZ Captain", tank="AMX30 Elite (Full)",
        apc="M113 (VZ) (Full)", truck="M151 .50Cal (VZ) (Full)", heli="Mi35 (Full)" },
}
local SQUAD_VEH = { tank=true, apc=true, truck=true, heli=true }   -- which roles spawn as an EMPTY vehicle
local SQUAD_TYPES = {                                              -- archetypes; sizes shown are with all roles present
    { name="Scout Team",      roles={ {"off",1},{"rifle",2},{"sniper",1} } },                              -- ~4
    { name="Fire Team",       roles={ {"rifle",2},{"mg",1},{"at",1} } },                                    -- 4
    { name="Rifle Squad",     roles={ {"off",1},{"rifle",5},{"mg",1},{"at",1} } },                          -- 8
    { name="Weapons Team",    roles={ {"off",1},{"mg",2},{"at",2},{"aa",1} } },                             -- 6
    { name="Recon Patrol",    roles={ {"off",1},{"rifle",3},{"sniper",1},{"mg",1} } },                      -- 6
    { name="Mech Section",    roles={ {"apc",1},{"off",1},{"rifle",4},{"at",1} } },                         -- 7
    { name="Armor Platoon",   roles={ {"tank",3} } },                                                       -- 3
    { name="Motor Patrol",    roles={ {"truck",1},{"off",1},{"rifle",4} } },                                -- 6
    { name="Assault Platoon", roles={ {"off",1},{"rifle",6},{"mg",2},{"at",2},{"elite",1} } },              -- 12
    { name="Garrison",        roles={ {"off",1},{"rifle",8},{"mg",3},{"at",2},{"aa",2} } },                 -- 16
    { name="Air Assault",     roles={ {"heli",1},{"off",1},{"rifle",5},{"mg",1},{"at",1} } },               -- 9
    { name="Battle Group",    roles={ {"boss",1},{"off",2},{"rifle",12},{"mg",4},{"at",3},{"elite",2} } },  -- 24
    { name="HVT Detail",      roles={ {"boss",1},{"elite",2},{"off",1},{"rifle",2} } },                     -- 6
}
local function buildSquads(fac)
    local roles = SQUAD_ROLES[fac]; if not roles then return nil end
    local out = {}
    for _, sq in ipairs(SQUAD_TYPES) do
        local list = {}
        for _, rc in ipairs(sq.roles) do
            local tmpl = roles[rc[1]]
            if tmpl then for _ = 1, rc[2] do list[#list + 1] = { tmpl = tmpl, veh = SQUAD_VEH[rc[1]] or false } end end
        end
        if #list > 0 then out[#out + 1] = { label = sq.name .. " (" .. #list .. ")", squad = list } end
    end
    return out
end

local function kindForBranch(label, inherited)
    if label == "VEHICLES" or label == "HELICOPTERS" or label == "BOATS" or label == "EMPLACEMENTS" then
        return "vehicle"
    elseif label == "INFANTRY" then
        return "infantry"
    end
    return inherited
end
local function stampNode(node, faction, kind)
    for _, c in ipairs(node.children) do
        if c.children then
            stampNode(c, faction, kindForBranch(c.label, kind))
        elseif c.squad then
            c.faction = faction
            c.kind = "squad"
        elseif c.id then
            c.faction = faction
            c.kind = kind
        end
    end
end
local function prepare_catalog()
    for _, top in ipairs(CATALOG) do                                  -- inject a SQUADS branch per faction from its roster
        if top.children and SQUAD_ROLES[top.label] then
            local has = false
            for _, c in ipairs(top.children) do if c.label == "SQUADS" then has = true; break end end
            if not has then local sq = buildSquads(top.label); if sq and #sq > 0 then table.insert(top.children, { label = "SQUADS", children = sq }) end end
        end
    end
    for _, top in ipairs(CATALOG) do
        if top.children and top.label ~= "OBJECTIVES" then
            if top.label == "PROPS / MISC" then
                stampNode(top, "PROP", "prop")
            elseif top.label == "WEAPONS" then
                stampNode(top, "WEAPON", "prop")            -- weapon pickups spawn as the item itself
            elseif top.label == "SUPPORT AIRCRAFT" then
                stampNode(top, "AIRCRAFT", "vehicle")       -- jets/planes = empty-variant vehicles
            else
                stampNode(top, top.label, "infantry")       -- factions (incl. PMC / CIVILIANS)
            end
        end
    end
    if not SORT_ITEMS then return end
    local function sortkids(list)
        table.sort(list, function(a, b) return tostring(a.label) < tostring(b.label) end)
        for _, c in ipairs(list) do if c.children then sortkids(c.children) end end
    end
    for _, top in ipairs(CATALOG) do
        if top.children and top.label ~= "OBJECTIVES" then sortkids(top.children) end
    end
end

-- =====================================================================
-- Marker helpers -- built on Ess.Mark (ONE combined handle per placement, covering every surface it uses)
-- instead of hand-rolling Marker.AddDisc/AddBlip + Hud.Radar:AddObjective + Pda.Map:AddBlip and tracking
-- three separate remove-handles. Colours / icon choices / radii stay MissionForge's own authoring policy;
-- only the surface calls + teardown route through Ess. The floating-icon-AND-ground-ring-on-one-anchor
-- combination MissionForge needs is exactly what the Ess.Mark `icon`/`size`/`dist` opts were added for.
-- =====================================================================
local function objRgb()
    local ok, r, g, b = pcall(MrxUtil.GetPrimaryObjectiveRgb)
    if ok and r then return r, g, b end
    return 255, 200, 0
end

-- MissionForge's objective types collapse onto Ess.Mark's 5 canonical icon "kinds"
-- (destroy/verify/defend/action/destination -- the base game's own MrxTaskObjective icon families).
local OBJ_KIND = {
    destroy = "destroy", chase = "destroy",
    verify  = "verify",
    defend  = "defend",  hold = "defend", survive = "defend",
    collect = "action",  interact = "action",
    reach   = "destination", escort = "destination", extract = "destination", checkpoint = "destination",
}

-- A ZONE placement: Ess.Mark.zone spawns its own TinyGeometry anchor and marks ground ring + floating icon
-- + radar + PDA in one call, and OWNS the anchor (Ess.Mark.clear removes the prop for us). Returns
-- (anchorGuid, markHandle) -- the anchor doubles as the entry's guid for position reads on export.
local function placeZone(x, y, z, radius, kind, rgb, discAlpha)
    local h = Ess.Mark.zone(x, y, z, radius, {
        kind = kind, rgb = rgb, icon = true, world = true, radar = true, pda = true,
        discAlpha = discAlpha or 0.15, size = 32, dist = 200,
    })
    if not h then return nil end
    return h.anchor, h
end

-- A UNIT placement marks the physical crate/vehicle MissionForge already spawned -- just the floating,
-- faction-coloured icon (no ring/radar/PDA). The guid is OURS (Ess.Mark.object doesn't own it), so unmark
-- removes it separately.
local function markUnit(u, rgb)
    return Ess.Mark.object(u, { radar = false, pda = false, world = true, kind = "action",
        rgb = rgb or DEFAULT_RGB, size = 24, dist = 200 })
end

-- Tear down a placement: clear its Ess.Mark handle (removes every marker surface, plus the anchor prop for
-- zone entries, which Ess.Mark.zone owns). For unit entries WE own the crate/vehicle guid, so remove it too.
local function unmarkEntry(entry)
    if entry.mark then Ess.Mark.clear(entry.mark); entry.mark = nil end
    if entry.ownGuid and entry.u then Ess.Object.remove(entry.u) end
end

-- =====================================================================
-- Cursor: a ring + floating marker ANCHORED TO THE PLAYER CHARACTER, so it follows you with zero
-- per-tick work. Re-created only when the brush (colour/radius) changes - never every frame.
-- =====================================================================
local function hideCursor()
    if F.cursor then
        if F.cursor.disc then Ess.Raw.Mark.removeWorld(F.cursor.disc) end
        if F.cursor.blip then Ess.Raw.Mark.removeWorld(F.cursor.blip) end
        F.cursor = nil
    end
end
local function showCursor(rgb, radius, icon)
    hideCursor()
    if not F.uChar then return end
    local c = { rgb = rgb, radius = radius }
    c.disc = Ess.Raw.Mark.worldDisc(F.uChar, radius, rgb, 0.25)
    c.blip = Ess.Raw.Mark.world(F.uChar, icon or "HUD_objective_action", rgb, 28, 220)
    F.cursor = c
end
-- The ground ring doesn't track a moving anchor, so re-snapshot just the disc on the player ~1/sec
-- (the blip DOES follow, so we leave it alone). Cheap: one Remove + one worldDisc per second.
local function refreshCursorDisc()
    local c = F.cursor
    if not (c and c.disc and c.rgb and F.uChar) then return end
    Ess.Raw.Mark.removeWorld(c.disc)
    c.disc = Ess.Raw.Mark.worldDisc(F.uChar, c.radius, c.rgb, 0.25)
end
local function cursorForBrush()
    local b = F.brush
    if not b then hideCursor(); return end
    if b.obj == "spawn" then
        showCursor(SPAWN_RGB, CURSOR_UNIT_RADIUS, "HUD_objective_deliverable")
    elseif b.obj == "trigger" then
        showCursor(TRIGGER_RGB, F.radius, "HUD_objective_action")
    elseif b.obj and string.sub(b.obj, 1, 8) == "support_" then
        showCursor(SUPPORT_RGB, F.radius, "HUD_objective_action")
    elseif b.obj and string.sub(b.obj, 1, 6) == "order_" then
        showCursor(ORDER_RGB, F.radius, "HUD_objective_deliverable")
    elseif b.obj then
        local r, g, bl = objRgb()
        showCursor({ r, g, bl }, F.radius, (OBJ_ICON[b.obj] or OBJ_ICON.reach).wld)
    elseif b.squad then
        showCursor(FACTION_RGB[b.faction] or DEFAULT_RGB, 7, "HUD_objective_action")
    else
        showCursor(FACTION_RGB[b.faction] or DEFAULT_RGB, CURSOR_UNIT_RADIUS, "HUD_objective_action")
    end
end

-- =====================================================================
-- Menu view + navigation (folded from ForgeCam; the movie is display-only)
-- =====================================================================
local function call(fn, args)
    if F.w then Ess.Gfx.call(F.w, fn, args) end
end
local function cur() return F.stack[#F.stack] end
local function label_for(node) if node.children then return node.label .. "  >" end return node.label end

-- forward declares (defined below, used by menu handlers)
local Drop, Export

local function makeBrush(it)
    if it.obj then
        return { obj = it.obj, label = it.label }
    elseif it.squad then
        return { squad = it.squad, faction = it.faction, label = it.label }
    elseif it.id then
        local kind = it.kind or "infantry"
        local placeholder
        if kind == "infantry" then
            placeholder = FACTION_CRATE[it.faction] or DEFAULT_CRATE
        elseif kind == "vehicle" then
            placeholder = emptyVariant(it.id)
        else
            placeholder = it.id   -- prop: place the actual prop
        end
        return { real = it.id, kind = kind, faction = it.faction, placeholder = placeholder, label = it.label }
    end
end
local function SetBrushFromSelection()
    local lv = cur()
    local it = lv.node.children[lv.sel + 1]
    if not it or (not it.id and not it.obj and not it.squad) then return end
    local key = it.obj or it.id or it.label
    if not F.brush or (F.brush.real or F.brush.obj or F.brush.label) ~= key then
        F.brush = makeBrush(it)
        Ess.Log("MissionForge: brush = " .. tostring(it.label))
        cursorForBrush()
    end
end

local function refresh(instant)
    local lv   = cur()
    local list = lv.node.children
    local n    = #list
    if lv.sel > n - 1 then lv.sel = n - 1 end
    if lv.sel < 0 then lv.sel = 0 end
    if lv.off > lv.sel then lv.off = lv.sel end
    if lv.sel > lv.off + VISIBLE - 1 then lv.off = lv.sel - VISIBLE + 1 end
    if lv.off < 0 then lv.off = 0 end

    for i = 0, VISIBLE - 1 do
        local it = list[lv.off + i + 1]
        if it then call("SetRow", { i, label_for(it) }) else call("SetRow", { i, "" }) end
    end

    local crumb = "MISSIONFORGE"
    for i = 2, #F.stack do crumb = crumb .. " > " .. F.stack[i].node.label end
    call("SetCrumb", { crumb })

    local hint = "GRP " .. tostring(F.group) .. "   O/L SEL"
    local it = list[lv.sel + 1]
    if it then
        if it.children then hint = hint .. "  K OPEN"
        elseif it.action then hint = hint .. "  K RUN"
        else hint = hint .. "  P PLACE@FEET" end
    end
    if #F.stack > 1 then hint = hint .. "  J BACK" end
    if F.brush then hint = hint .. "  [" .. tostring(F.brush.label) .. "]" end
    call("SetHint", { hint })

    if n == 0 then call("SetSelected", { -1 }) else call("SetSelected", { lv.sel - lv.off }) end

    if n > VISIBLE then
        local th = TRACK_H * VISIBLE / n
        if th < 18 then th = 18 end
        local ty = TRACK_Y + (TRACK_H - th) * lv.off / (n - VISIBLE)
        call("SetScroll", { math.floor(ty), math.floor(th) })
    else
        call("SetScroll", { 0, 0 })
    end

    local shown = n
    if shown > VISIBLE then shown = VISIBLE end
    if shown < 1 then shown = 1 end
    F.panelTgt = 100 * (shown * ROW_PITCH + 12) / PANEL_H
    if instant then F.panelCur = F.panelTgt; call("SetPanel", { F.panelCur }) end

    SetBrushFromSelection()
end

local function menu_move(d)
    local lv = cur()
    local n = #lv.node.children
    if n == 0 then return end
    local s = clamp(lv.sel + d, 0, n - 1)
    if s ~= lv.sel then lv.sel = s; refresh() end
end
-- Give the author a helicopter + make them AND it invincible, so you can fly around dropping camera points
-- in the air without dying or wrecking. (An authoring convenience -- the invincibility persists until the
-- level reloads; it never touches the exported mission.)
local function GiveHeli()
    local char = Ess.Player.character(0)
    local heli = Ess.Easy.Vehicle.summon("UH1 Transport")
    if not heli then heli = Ess.Object.vehicleOf(char) end
    if heli then
        Ess.Object.setInvincible(heli, true, "MissionForge"); F.cineHeli = heli
        -- hold SHIFT to boost forward. Ess.Input.held reads the keyboard WITHOUT draining the edge buffer,
        -- so it never eats the arrow/P presses this menu's own key handler needs each tick.
        Ess.Loop.start("MissionForge.heliBoost", 0.05, function()
            local h = F.cineHeli
            if not h or not F.active then return false end
            if Ess.Input.held(0x10) then Ess.Easy.Impulse.speedBoost(h, 1.5) end
            return true
        end)
    end
    if char then Ess.Object.setInvincible(char, true, "MissionForge") end
    Ess.Log("MissionForge: gave a cinematic heli (invincible, hold SHIFT to boost)")
    call("SetHint", { heli and "HELI READY (invincible, SHIFT=boost) -- fly + drop camera points" or "HELI FAILED" })
end

local function menu_activate()
    local lv = cur()
    local it = lv.node.children[lv.sel + 1]
    if not it then return end
    if it.children then
        F.stack[#F.stack + 1] = { node = it, sel = 0, off = 0 }
        refresh()
    elseif it.action == "export" then
        Export()
    elseif it.action == "give_heli" then
        GiveHeli()
    elseif it.id or it.obj then
        F.brush = makeBrush(it)
        cursorForBrush()
        Drop()
    end
end
local function menu_back()
    if #F.stack > 1 then F.stack[#F.stack] = nil; refresh() end
end
local function cycleGroup()
    local c = (string.byte(F.group) or 65) - 64
    c = c + 1; if c > 26 then c = 1 end
    F.group = string.char(64 + c)
    call("SetHint", { "GROUP = " .. F.group })
    Ess.Log("MissionForge: group -> " .. F.group)
end

-- =====================================================================
-- Placement (always at the player's feet)
-- =====================================================================
-- Spawn a unit brush's placeholder (empty vehicle / faction crate / prop). Falls back to the faction
-- crate if the primary template won't spawn. Returns guid, placeholder.
local function spawnUnitPlaceholder(b, x, y, z)
    local u = Ess.Object.spawn(b.placeholder, x, y, z)   -- Ess.Object.spawn carries the blank-template crash guard
    if u then return u, b.placeholder end
    local crate = FACTION_CRATE[b.faction] or DEFAULT_CRATE
    if crate ~= b.placeholder then
        local u2 = Ess.Object.spawn(crate, x, y, z)
        if u2 then return u2, crate end
    end
    return nil, b.placeholder
end

local function playerPose()
    -- Ess.Player.pose(0) = the local hero's world position + facing (Object.GetPosition/GetYaw, pcall'd).
    local px, py, pz, yaw = Ess.Player.pose(0)
    if not px then return nil end
    return px, py, pz, yaw
end

Drop = function()
    local b = F.brush
    if not b then call("SetHint", { "SELECT A UNIT OR OBJECTIVE FIRST" }); return end
    local px, py, pz, yaw = playerPose()
    if not px then call("SetHint", { "NO PLAYER POSITION" }); return end

    if b.obj == "spawn" then
        -- player-spawn point: teal marker on its own anchor (small ring, brighter fill)
        local u, mark = placeZone(px, py, pz, 3, "destination", SPAWN_RGB, 0.2)
        if not u then call("SetHint", { "SPAWN ANCHOR FAILED" }); Ess.Log("MissionForge: spawn-point anchor failed"); return end
        local entry = { cat = "spawn", u = u, mark = mark, x = px, y = py, z = pz, yaw = yaw, group = F.group }
        table.insert(F.items, entry)
        Ess.Log(string.format("MissionForge: PLAYER SPAWN #%d  @ %.2f,%.2f,%.2f  yaw=%.3f", #F.items, px, py, pz, yaw))
        call("SetHint", { "PLAYER SPAWN SET (#" .. #F.items .. ")" })
    elseif b.obj == "trigger" or (b.obj and string.sub(b.obj, 1, 8) == "support_") then
        local entry
        if b.obj == "trigger" then
            local u, mark = placeZone(px, py, pz, F.radius, "action", TRIGGER_RGB)
            if not u then call("SetHint", { "ZONE ANCHOR FAILED" }); Ess.Log("MissionForge: trigger anchor failed"); return end
            entry = { cat = "trigger", u = u, mark = mark, x = px, y = py, z = pz, radius = F.radius, group = F.group }
        else
            local u, mark = placeZone(px, py, pz, F.radius, "action", SUPPORT_RGB)
            if not u then call("SetHint", { "ZONE ANCHOR FAILED" }); Ess.Log("MissionForge: support anchor failed"); return end
            entry = { cat = "support", u = u, mark = mark, effect = string.sub(b.obj, 9), x = px, y = py, z = pz, radius = F.radius, group = F.group }
        end
        table.insert(F.items, entry)
        Ess.Log(string.format("MissionForge: %s #%d  @ %.2f,%.2f,%.2f  r=%.1f  grp=%s",
            (b.obj == "trigger") and "TRIGGER" or ("SUPPORT " .. entry.effect), #F.items, px, py, pz, F.radius, F.group))
        call("SetHint", { "PLACED " .. tostring(b.label) .. " (#" .. #F.items .. ")" })
    elseif b.obj and string.sub(b.obj, 1, 6) == "order_" then
        local u, mark = placeZone(px, py, pz, F.radius, "destination", ORDER_RGB)
        if not u then call("SetHint", { "ORDER ANCHOR FAILED" }); Ess.Log("MissionForge: order anchor failed"); return end
        local entry = { cat = "order", u = u, mark = mark, behavior = string.sub(b.obj, 7),
            x = px, y = py, z = pz, yaw = yaw, radius = F.radius, group = F.group }
        table.insert(F.items, entry)
        Ess.Log(string.format("MissionForge: ORDER #%d  %s  grp=%s  @ %.2f,%.2f,%.2f  r=%.1f",
            #F.items, entry.behavior, tostring(F.group), px, py, pz, F.radius))
        call("SetHint", { "ORDER " .. string.upper(entry.behavior) .. " -> GRP " .. tostring(F.group) .. " (#" .. #F.items .. ")" })
    elseif b.obj and string.sub(b.obj, 1, 5) == "cine_" then
        -- a cinematic camera / look point -- captures your position + facing (so aim it by facing that way).
        -- Placed while flying = an aerial camera point. Small sky-blue marker; NOT grouped.
        local kind = string.sub(b.obj, 6)   -- preview / shot / look
        local u, mark = placeZone(px, py, pz, 3, "action", CINE_RGB)
        if not u then call("SetHint", { "CINE ANCHOR FAILED" }); Ess.Log("MissionForge: cine anchor failed"); return end
        local entry = { cat = "cine", u = u, mark = mark, kind = kind, x = px, y = py, z = pz, yaw = yaw }
        table.insert(F.items, entry)
        Ess.Log(string.format("MissionForge: CINE %s #%d  @ %.2f,%.2f,%.2f  yaw=%.3f", kind, #F.items, px, py, pz, yaw))
        call("SetHint", { "CAMERA " .. string.upper(kind) .. " (#" .. #F.items .. ")" })
    elseif b.obj then
        local u, mark = placeZone(px, py, pz, F.radius, OBJ_KIND[b.obj] or "destination", { objRgb() })
        if not u then call("SetHint", { "OBJ ANCHOR FAILED" }); Ess.Log("MissionForge: objective anchor failed"); return end
        local entry = { cat = "obj", u = u, mark = mark, type = b.obj, x = px, y = py, z = pz, yaw = yaw, radius = F.radius, group = F.group }
        table.insert(F.items, entry)
        Ess.Log(string.format("MissionForge: OBJ #%d  %s  @ %.2f,%.2f,%.2f  r=%.1f  grp=%s",
            #F.items, b.obj, px, py, pz, F.radius, F.group))
        call("SetHint", { "PLACED " .. tostring(b.obj) .. " (#" .. #F.items .. ")" })
    elseif b.squad then
        -- drop the whole squad in a grid formation at your feet (rotated to your facing), all one group
        local list = b.squad
        local cols = math.max(1, math.min(5, math.ceil(math.sqrt(#list))))
        local SP = 5
        local yr = math.rad(yaw); local cyaw, syaw = math.cos(yr), math.sin(yr)
        F.squadSeq = (F.squadSeq or 0) + 1; local sqId = F.squadSeq
        local placed = 0
        for idx, item in ipairs(list) do
            local i0 = idx - 1
            local col = i0 % cols; local row = math.floor(i0 / cols)
            local lx = (col - (cols - 1) / 2) * SP; local lz = row * SP
            local wx = px + lx * cyaw - lz * syaw
            local wz = pz + lx * syaw + lz * cyaw
            local ph = item.veh and emptyVariant(item.tmpl) or (FACTION_CRATE[b.faction] or DEFAULT_CRATE)
            local mini = { real = item.tmpl, placeholder = ph, kind = item.veh and "vehicle" or "infantry", faction = b.faction }
            local u, php
            if SPAWN_PHYSICAL_MARKER then u, php = spawnUnitPlaceholder(mini, wx, py, wz)
            else php = ph; u = Ess.Object.spawn("TinyGeometry", wx, py, wz) end
            if u then
                Ess.Object.setYaw(u, yaw)
                Ess.Object.setInvincible(u, true, "MissionForge")
                local entry = { cat = "unit", u = u, ownGuid = true, real = item.tmpl, placeholder = php, kind = mini.kind,
                    faction = b.faction, x = wx, y = py, z = wz, yaw = yaw, group = F.group, sq = sqId }
                entry.mark = markUnit(u, FACTION_RGB[b.faction] or DEFAULT_RGB)
                table.insert(F.items, entry)
                placed = placed + 1
            end
        end
        Ess.Log(string.format("MissionForge: SQUAD %s -> %d units  grp=%s", tostring(b.label), placed, tostring(F.group)))
        call("SetHint", { "SQUAD " .. tostring(b.label) .. ": " .. placed .. " units, grp " .. tostring(F.group) })
    else
        local u, ph
        if SPAWN_PHYSICAL_MARKER then
            u, ph = spawnUnitPlaceholder(b, px, py, pz)
        else
            ph = b.placeholder
            u = Ess.Object.spawn("TinyGeometry", px, py, pz)
        end
        if not u then call("SetHint", { "DROP FAILED (bad placeholder?)" }); Ess.Log("MissionForge: drop failed " .. tostring(b.placeholder)); return end
        Ess.Object.setYaw(u, yaw)
        Ess.Object.setInvincible(u, true, "MissionForge")
        local entry = { cat = "unit", u = u, ownGuid = true, real = b.real, placeholder = ph,
            kind = b.kind, faction = b.faction, x = px, y = py, z = pz, yaw = yaw, group = F.group }
        entry.mark = markUnit(u, FACTION_RGB[b.faction] or DEFAULT_RGB)
        table.insert(F.items, entry)
        Ess.Log(string.format("MissionForge: UNIT #%d  %s  [%s]  @ %.2f,%.2f,%.2f  grp=%s",
            #F.items, tostring(b.real), tostring(ph), px, py, pz, F.group))
        call("SetHint", { "PLACED " .. tostring(b.label) .. " (#" .. #F.items .. ")" })
    end
end

local function NearestIndex()
    local px, py, pz = playerPose()
    if not px then return nil end
    local nBest, iBest
    for i, e in ipairs(F.items) do
        local x, y, z = e.x, e.y, e.z
        local lx, ly, lz = Ess.Object.pos(e.u)
        if lx then x, y, z = lx, ly, lz end
        local dx, dy, dz = x - px, y - py, z - pz
        local d = dx * dx + dy * dy + dz * dz
        if not nBest or d < nBest then nBest, iBest = d, i end
    end
    return iBest, nBest
end
-- Defensive: rebuild F.items as a DENSE sequence so ipairs/# can never truncate at a nil hole. This was a
-- real MissionForge bug (a trailing-nil pop left a hole that made Export silently drop everything past it);
-- Ess.Table.compact is that exact fix promoted into the framework -- it mutates F.items in place and also
-- RECOVERS any items already stranded past a hole from an earlier pop.
local function compact()
    Ess.Table.compact(F.items)
end
local function RemoveNearest()
    compact()
    local iBest, nBest = NearestIndex()
    local nMax = 30
    if iBest and nBest <= nMax * nMax then
        local e = F.items[iBest]
        unmarkEntry(e)
        table.remove(F.items, iBest)
        Ess.Log("MissionForge: REMOVED " .. tostring(e.real or e.type or e.cat) .. " (" .. #F.items .. " left)")
        call("SetHint", { "REMOVED (" .. #F.items .. " left)" })
    else
        call("SetHint", { "NOTHING TO REMOVE NEAR YOU" })
    end
end
local function RemoveLast()   -- undo: drop the most recently placed item (or the whole last squad at once)
    compact()
    local n = #F.items
    if n == 0 then call("SetHint", { "NOTHING TO UNDO" }); return end
    local e = F.items[n]
    if e.sq then                                   -- squad units share a `sq` id -> undo the entire squad
        local removed = 0
        while #F.items > 0 and F.items[#F.items].sq == e.sq do
            unmarkEntry(F.items[#F.items]); table.remove(F.items); removed = removed + 1
        end
        Ess.Log("MissionForge: UNDO squad (-" .. removed .. ", " .. #F.items .. " left)")
        call("SetHint", { "UNDO SQUAD (-" .. removed .. ", " .. #F.items .. " left)" })
        return
    end
    unmarkEntry(e)
    table.remove(F.items)     -- proper pop of the (now dense) last element - never leaves a hole
    Ess.Log("MissionForge: UNDO " .. tostring(e.real or e.type or e.cat) .. " (" .. #F.items .. " left)")
    call("SetHint", { "UNDO (" .. #F.items .. " left)" })
end
local function ClearAll()   -- kept for reference; intentionally NOT bound to a key (too easy to nuke progress)
    local n = #F.items
    for i = n, 1, -1 do unmarkEntry(F.items[i]); F.items[i] = nil end
    Ess.Log("MissionForge: CLEARED " .. n .. " placement(s)")
    call("SetHint", { "CLEARED " .. n })
end

-- Paste-ready MissionForge export table -> lua_loader_printf.log (parsed by the web tool).
Export = function()
    compact()   -- rebuild dense first, so a stray nil hole can't truncate the export (also recovers stranded items)
    local n = #F.items
    if n == 0 then Loader.Printf("MissionForge: nothing to export"); call("SetHint", { "NOTHING TO EXPORT" }); return end
    local cx, cy, cz, cnt = 0, 0, 0, 0
    local units, objs, spawns, support, triggers, orders, cinematic = {}, {}, {}, {}, {}, {}, {}
    for _, e in ipairs(F.items) do
        local x, y, z = e.x, e.y, e.z
        local lx, ly, lz = Ess.Object.pos(e.u)
        if lx then x, y, z = lx, ly, lz end
        cx, cy, cz, cnt = cx + x, cy + y, cz + z, cnt + 1
        if e.cat == "spawn" then
            table.insert(spawns, string.format(
                "    { x=%.2f, y=%.2f, z=%.2f, yaw=%.3f },", x, y, z, e.yaw or 0))
        elseif e.cat == "support" then
            table.insert(support, string.format(
                "    { effect=%q, x=%.2f, y=%.2f, z=%.2f, radius=%.1f, group=%q },",
                tostring(e.effect), x, y, z, e.radius or 0, tostring(e.group)))
        elseif e.cat == "trigger" then
            table.insert(triggers, string.format(
                "    { x=%.2f, y=%.2f, z=%.2f, radius=%.1f, group=%q },",
                x, y, z, e.radius or 0, tostring(e.group)))
        elseif e.cat == "order" then
            table.insert(orders, string.format(
                "    { behavior=%q, x=%.2f, y=%.2f, z=%.2f, radius=%.1f, group=%q },",
                tostring(e.behavior), x, y, z, e.radius or 0, tostring(e.group)))
        elseif e.cat == "cine" then
            table.insert(cinematic, string.format(
                "    { kind=%q, x=%.2f, y=%.2f, z=%.2f, yaw=%.3f },", tostring(e.kind), x, y, z, e.yaw or 0))
        elseif e.cat == "obj" then
            table.insert(objs, string.format(
                "    { type=%q, x=%.2f, y=%.2f, z=%.2f, radius=%.1f, yaw=%.3f, group=%q },",
                e.type, x, y, z, e.radius or 0, e.yaw or 0, tostring(e.group)))
        else
            table.insert(units, string.format(
                "    { faction=%q, kind=%q, spawn=%q, placeholder=%q, x=%.2f, y=%.2f, z=%.2f, yaw=%.3f, group=%q },",
                tostring(e.faction), tostring(e.kind), tostring(e.real), tostring(e.placeholder),
                x, y, z, e.yaw or 0, tostring(e.group)))
        end
    end
    if cnt > 0 then cx, cy, cz = cx / cnt, cy / cnt, cz / cnt end
    Loader.Printf("MissionForge: ===== EXPORT (" .. #units .. " units, " .. #objs .. " objectives, " .. #spawns
        .. " spawn, " .. #support .. " support, " .. #triggers .. " triggers, " .. #orders .. " orders, "
        .. #cinematic .. " cinematic) =====")
    Loader.Printf("MISSIONFORGE_EXPORT = {")
    Loader.Printf(string.format("  name = %q,", "forge_" .. math.floor(F.now)))
    Loader.Printf(string.format("  anchor = { x=%.2f, y=%.2f, z=%.2f },", cx, cy, cz))
    if #spawns > 0 then
        Loader.Printf("  spawns = {")
        for _, r in ipairs(spawns) do Loader.Printf(r) end
        Loader.Printf("  },")
    end
    Loader.Printf("  units = {")
    for _, r in ipairs(units) do Loader.Printf(r) end
    Loader.Printf("  },")
    Loader.Printf("  objectives = {")
    for _, r in ipairs(objs) do Loader.Printf(r) end
    Loader.Printf("  },")
    if #support > 0 then
        Loader.Printf("  support = {")
        for _, r in ipairs(support) do Loader.Printf(r) end
        Loader.Printf("  },")
    end
    if #triggers > 0 then
        Loader.Printf("  triggers = {")
        for _, r in ipairs(triggers) do Loader.Printf(r) end
        Loader.Printf("  },")
    end
    if #orders > 0 then
        Loader.Printf("  orders = {")
        for _, r in ipairs(orders) do Loader.Printf(r) end
        Loader.Printf("  },")
    end
    if #cinematic > 0 then
        Loader.Printf("  cinematic = {")
        for _, r in ipairs(cinematic) do Loader.Printf(r) end
        Loader.Printf("  },")
    end
    Loader.Printf("}")
    Loader.Printf("MissionForge: ===== END EXPORT =====")
    call("SetHint", { "EXPORTED " .. n .. " TO LOG" })
end

-- =====================================================================
-- Keyboard (now a true ring-buffer drain: ONE PopKeyEvents per tick returns every up->down edge
-- since the last tick, in press order, focus-gated by the bridge. Edges are sampled C-side at ~60Hz,
-- so no tap can fall between ticks no matter what TICK is. Held keys (radius) come from ONE
-- GetKeyboardState snapshot instead of per-key IsKeyDown calls. Bridge calls/tick: 14 -> 2.)
-- =====================================================================
-- VK -> action. Built once per file run; by this point Drop/Export and the menu handlers are all
-- assigned, so direct references are safe. Both drop keys map to the same action.
local KEY_ACTIONS = {
    [K_MENU_UP]   = function() menu_move(-1) end,
    [K_MENU_DOWN] = function() menu_move(1) end,
    [K_MENU_OPEN] = menu_activate,
    [K_MENU_BACK] = menu_back,
    [K_DROP]      = Drop,
    [K_DROP2]     = Drop,
    [K_UNDO]      = RemoveLast,
    [K_REMOVE]    = RemoveNearest,
    [K_EXPORT]    = Export,
    [K_GROUP]     = cycleGroup,
}

local function HandleKeys(dt)
    -- Ess.Input.poll() = the one correct shape: ONE PopKeyEvents (an edge-triggered ring buffer of every VK
    -- pressed since the last tick, in press order) for discrete keys + ONE GetKeyboardState snapshot exposed
    -- as down(vk) for held keys. Never a per-key IsKeyDown loop -- that's the framerate footgun this project
    -- has hit and re-fixed several times (Ess.Input's own doc comment is the canonical writeup).
    local input = Ess.Input.poll()
    for _, vk in ipairs(input.pressed) do          -- discrete keys, in press order
        local fn = KEY_ACTIONS[vk]
        if fn then fn() end
    end
    -- held keys (objective zone radius) resize the foot-ring live
    if input.down(K_RAD_DN) then F.radius = clamp(F.radius - RAD_SPEED * dt, 3, 100); F.cursorDirty = true end
    if input.down(K_RAD_UP) then F.radius = clamp(F.radius + RAD_SPEED * dt, 3, 100); F.cursorDirty = true end
end

local function EasePanel()
    if F.panelCur and F.panelTgt then
        local d = F.panelTgt - F.panelCur
        if d > 0.5 or d < -0.5 then F.panelCur = F.panelCur + d * 0.35; call("SetPanel", { F.panelCur })
        elseif F.panelCur ~= F.panelTgt then F.panelCur = F.panelTgt; call("SetPanel", { F.panelCur }) end
    end
end

-- =====================================================================
-- Per-tick update: drain keys, resize the objective ring if it changed, ease the panel. Cheap.
-- =====================================================================
local function Update(dt)
    F.now = (F.now or 0) + dt
    HandleKeys(dt)
    if F.cursorDirty then
        if F.brush and F.brush.obj then cursorForBrush() end   -- redraw ring at the new radius
        F.cursorDirty = false
    end
    -- keep the foot-ring roughly under the player: re-snapshot the disc ~once/sec (the disc anchor
    -- doesn't track movement; the blip does). 1s cadence = visible follow with no perf cost.
    F.ringClock = (F.ringClock or 0) + dt
    if F.ringClock >= 1.0 then F.ringClock = 0; refreshCursorDisc() end
    EasePanel()
end

-- Heartbeat via Ess.Loop -- the ONE shared, reload-safe, self-rescheduling timer (Event.TimerRelative
-- works here because MissionForge runs UNPAUSED). Ess.Loop's own generation counter makes toggling off/on
-- safe: start() with the same id supersedes any prior loop and stop() ends it, so MissionForge no longer
-- hand-rolls the F.gen guard it used to. Per-frame dt (clamped, and it survives a pause/hitch because it
-- reads the real-world clock) comes from Ess.Time.clock. Ess.Loop already pcall-wraps the tick and logs
-- any error itself, so there's no local pcall/ERROR line here anymore.
local function startTick()
    F.clock = Ess.Time.clock(0.25)
    Ess.Loop.start("MissionForge", TICK, function()
        if not F.active then return false end
        Update(F.clock:delta())
        return true
    end)
end

-- =====================================================================
-- Widget plumbing (same forge.gfx as ForgeCam; HUD overlay, renders unpaused)
-- =====================================================================
local function BuildMenu()
    if F.w then return end
    -- Ess.Gfx.widget builds + owns + registers the FlashWidget from forge.gfx (the SAME movie ForgeCam uses;
    -- still injected in the wad patch). It takes (file, x, y, W, H) and does the SetLocation(x,y,x+W,y+H)
    -- corner-coordinate math internally -- so it also fixes the (x,y,w,h)-vs-corners footgun for free. The
    -- original SetLocation(40,80,380,420) is that same rectangle: corners (40,80)-(380,420) == W=340,H=340.
    F.w = Ess.Gfx.widget("forge.gfx", 40, 80, 340, 340)
    Ess.Gfx.setVisible(F.w, true)
end

-- =====================================================================
-- Toggle
-- =====================================================================
local uChar = Ess.Player.character(0)   -- local hero (single-player-safe); Ess.Gfx owns the widget's player

if uChar then
    F.active = not F.active

    if F.active then
        F.uChar = uChar
        F.now = 0
        F.cursorDirty = false
        F.ringClock = 0
        hideCursor()
        Ess.Input.clear()   -- drop the F7 press + anything buffered before activate

        -- menu: prep, build once, reset nav to root
        prepare_catalog()
        F.stack = { { node = { label = "MISSIONFORGE", children = CATALOG }, sel = 0, off = 0 } }
        F.panelCur, F.panelTgt = 100, 100
        BuildMenu()
        Ess.Gfx.setVisible(F.w, true)
        refresh(true)
        cursorForBrush()   -- show the foot cursor if a brush carried over

        startTick()         -- Ess.Loop heartbeat (auto-supersedes any prior loop under this id)

        Ess.Log("MissionForge: ACTIVE (grp " .. F.group .. "). Walk to the spot; P/Enter places at your feet. "
            .. "Arrows=nav  Backspace=undo  Delete=remove-nearest  , .=obj radius  T=group  End=export")
    else
        Ess.Loop.stop("MissionForge")   -- end the heartbeat
        hideCursor()
        if F.w then Ess.Gfx.setVisible(F.w, false) end
        Ess.Log("MissionForge: exited (" .. #F.items .. " placement(s) still in world)")
    end
end