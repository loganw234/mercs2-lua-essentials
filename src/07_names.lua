-- Ess/07_names.lua -- Ess.Names: turn a `0xHASH` back into the human name it was hashed from.
--
-- The engine has almost no strings at runtime: assets, spawn templates, regions, doors, materials -- all of
-- it is addressed by a 32-bit `pandemic_hash_m2` (an FNV-1a variant, `|0x20` case-fold, `^0x2A * prime`
-- finaliser). `Ess.Name(uGuid)` already hands you that value as the string `"0x4000563D"` (Sys.GuidToString),
-- but there's no way back to `refinery_doc_warehouse01` -- the hash is one-way. This namespace is the reverse
-- side of the bridge Plan-03 calls "names on the wire": a lookup TABLE, hash-verified against the retail
-- WADs, that inverts the ~23k names the game actually ships. It is the enrichment layer -- the transport
-- speaks hashes, this speaks meaning.
--
-- API:
--   Ess.Names.of(sHash)     -> sName | nil        reverse one hash. nil on a miss -- NEVER a guessed name.
--   Ess.Names.label(sHash)  -> "name (0xHASH)"    the same, formatted for a log line; falls back to the bare
--                                                 hash when unknown, so it's always safe to concatenate.
--   Ess.Named(uGuid)        -> "name (0xHASH)"    Ess.Name enriched: the guid's hash resolved to its name
--                                                 where we know it. nil only if the guid has no string form.
--   Ess.Names.installed()   -> bool               is the (optional) name table loaded?
--   Ess.Names.count()       -> n                  how many names it holds (0 if not installed)
--   Ess.Names.load(tTable)  -> Ess.Names          adopt a { ["0xHASH"] = "name" } table (see below)
--
-- THE TABLE IS OPTIONAL AND SHIPPED SEPARATELY. At ~23k entries it is far too large to fold into the one
-- merged Ess.lua every user loads, so it rides its own file (scripts/OnLoad/2_EssNames.lua from the release
-- zip) that a user opts into with one lua_loader.ini line. That file just sets the global `__EssNamesDB`;
-- this namespace ADOPTS it lazily on first lookup, so load order between the two does not matter. With the
-- table absent, every call here degrades honestly -- `of` returns nil, `label`/`Named` return the bare hash.
--
-- WHY THE KEY IS A STRING, NOT A NUMBER. This is Lua 5.1 with 32-bit FLOAT numbers (integers exact only to
-- 2^24 -- see CONTRIBUTING's engine rules). A hash like 0xE54047D5 has no exact float representation, so a
-- table keyed by the numeric hash would silently collide high hashes onto each other. The engine already
-- hands the hash to Lua as the STRING `"0x...."` for exactly this reason, and we key on that string. It is
-- the same trap Ess.RNG exists to paper over, showing up in a second place.

local Ess = _G.Ess

Ess.Names = Ess.Names or {}

-- The adopted lookup table, or nil until one is present. Held private so the only ways in are load() and the
-- lazy adopt below -- a caller cannot accidentally half-populate it.
local DB = nil

-- Lazily bind to the separately-loaded global the moment anyone actually asks for a name. Doing it here
-- rather than at file load is what makes the two files order-independent: the data file may run before OR
-- after Ess, and either way the first of() call finds it.
local function db()
    if DB == nil and type(_G.__EssNamesDB) == "table" then DB = _G.__EssNamesDB end
    return DB
end

-- Normalise any spelling of a hash to the table's canonical `"0xAABBCCDD"` (upper-case, 0x, 8 wide).
-- Sys.GuidToString already emits exactly that, but a hash pasted from a doc, a tool, or the field guide may
-- arrive bare ("E54047D5"), lower-case, or short, and a resolver that only matched one spelling would report
-- a false miss on a name it actually holds. Returns nil for anything that isn't a 32-bit hex hash -- an
-- object NAME is not a hash and must not be coerced into one.
local function norm(sHash)
    if type(sHash) ~= "string" then return nil end
    local hex = sHash:match("^0[xX](%x+)$") or sHash:match("^(%x+)$")
    if not hex or #hex == 0 or #hex > 8 then return nil end
    return "0x" .. string.rep("0", 8 - #hex) .. hex:upper()
end

-- Ess.Names.of(sHash) -> sName | nil -- reverse a single hash. A miss returns nil and NEVER a fabricated
-- name: the hash is one-way and only 32 bits, so past a few million candidate strings a "match" is expected
-- to be a collision (field_guide "everything is a name hash", consequence 2). The table holds only names
-- carried by a second, independent witness, so a hit here is real; anything else is honestly unknown.
function Ess.Names.of(sHash)
    local d = db(); if not d then return nil end
    local key = norm(sHash); if not key then return nil end
    return d[key]
end

-- Ess.Names.label(sHash) -> string -- "name (0xHASH)" when known, the tidied bare hash when not. Always a
-- string, so it drops straight into an Ess.Log without a nil guard.
function Ess.Names.label(sHash)
    local key = norm(sHash) or tostring(sHash)
    local name = Ess.Names.of(sHash)
    if name then return name .. " (" .. key .. ")" end
    return key
end

function Ess.Names.installed()
    return db() ~= nil
end

function Ess.Names.count()
    local d = db(); if not d then return 0 end
    local n = 0
    for _ in pairs(d) do n = n + 1 end
    return n
end

-- Ess.Names.load(t) -> Ess.Names -- adopt a { ["0xHASH"] = "name" } table directly. The shipped data file
-- goes through the global instead (so it needs nothing loaded first), but this is the seam a test or a mod
-- with its own custom-asset names uses. Chainable.
function Ess.Names.load(t)
    if type(t) == "table" then DB = t end
    return Ess.Names
end

-- Ess.Named(uGuid) -> string | nil -- Ess.Name with the meaning put back. Where Ess.Name gives you
-- "0x4000563D", this gives "refinery_doc_warehouse01 (0x4000563D)" when the name is known, and the bare hash
-- string when it isn't. nil only when the guid has no string form at all (what Ess.Name itself returns nil
-- for). This is the everyday call -- logging or printing a guid becomes readable with a one-word change.
--
-- ⚠ Reads cleanly for NAMED, placed world objects (regions, doors, buildings, referenced assets), whose guid
-- IS their name hash. A freshly Pg.Spawn'd instance carries a transient runtime handle that was never hashed
-- from a name, so it will simply not be in the table and you get the bare hash back -- correct, not a bug.
function Ess.Named(uGuid)
    local s = Ess.Name(uGuid)
    if not s then return nil end
    return Ess.Names.label(s)
end
