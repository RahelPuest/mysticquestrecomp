-- Serializes a plain Lua value (nested tables/strings/numbers/
-- booleans/nil) into loadable Lua SOURCE TEXT -- the "LuaWriter" half
-- of the generated-cache pipeline `docs/architecture.md` already names
-- as this project's own committed target architecture (gen1recomp's
-- own `RomExtractor`/`LuaWriter`/`ImageWriter` shape, task #34,
-- 2026-08-16: "erstmal nur vormerken" back on 2026-08-11, now enough
-- real normalized game data exists -- 384 real decodable rooms, 201/
-- 256 opcodes, full monster/item/NPC catalogs -- to make caching
-- actually pay for itself).
--
-- Pure Lua, no `love.*`/`io.*` calls -- this module only turns a value
-- into a STRING; actually writing that string to disk is the real
-- I/O's own job (`scripts/extract_rom_cache.lua`, matching
-- `SaveFile.lua`'s own already-established "thin, untested I/O glue
-- around a pure, tested core" split -- see that file's own doc
-- comment for the precedent this mirrors). Round-trip correctness
-- (serialize then `load()` reproduces the exact original value) is
-- what `tests/import/lua_writer_test.lua` actually verifies.
--
-- HONEST SCOPE: handles everything this project's own REAL decoded
-- data actually needs (nested tables -- both array-shaped and map-
-- shaped, strings including real German umlaut/UTF-8 text, integers,
-- floats, booleans, nil-as-absent-key) -- does NOT handle functions,
-- userdata, or cyclic references (this project's own decoded ROM data
-- is always a plain, acyclic tree; a cycle would be a real bug in
-- whatever produced the value, not something to silently paper over).

local LuaWriter = {}

--- Real Lua identifier test (matches `[A-Za-z_][A-Za-z0-9_]*`, and
-- excludes real Lua keywords) -- used to decide whether a string table
-- key can be written as `bareword = value` or needs `["quoted"] =
-- value` instead. Keeping bareword keys where possible is not just
-- cosmetic: it's what makes a generated file diff-reviewable by a
-- human, the same reason `rom_profiles.lua` itself is hand-written
-- this way.
local KEYWORDS = {
  ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true, ["elseif"] = true,
  ["end"] = true, ["false"] = true, ["for"] = true, ["function"] = true, ["goto"] = true,
  ["if"] = true, ["in"] = true, ["local"] = true, ["nil"] = true, ["not"] = true,
  ["or"] = true, ["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
  ["until"] = true, ["while"] = true,
}

local function isBareword(key)
  return type(key) == "string" and key:match("^[A-Za-z_][A-Za-z0-9_]*$") ~= nil and not KEYWORDS[key]
end

--- Real string escaping -- `%q` (Lua's own built-in "quote a string
-- safely" formatter) already handles embedded quotes/backslashes/
-- control bytes correctly, including real UTF-8 umlaut bytes (which
-- `%q` passes through as literal high bytes, exactly matching how
-- this project's own `TextDecoder.lua` already emits raw UTF-8
-- 'ü'/'ä'/'ö'/'ß' -- see that module's own doc comment). Only real
-- difference from bare `string.format("%q", s)`: LuaJIT's own `%q`
-- emits a literal newline as `\` followed by a real newline character
-- (valid Lua, but ugly in a generated file meant to be diffable) --
-- normalized to the standard `\n` escape instead.
local function quoteString(s)
  local q = string.format("%q", s)
  q = q:gsub("\\\n", "\\n")
  return q
end

-- Real, deterministic key ordering for map-shaped tables -- iteration
-- order over a plain Lua table is NOT guaranteed stable across runs,
-- which would make every regenerated cache file a spurious diff even
-- when nothing real changed. Numbers sort numerically (ascending),
-- strings sort alphabetically, and every numeric key sorts before
-- every string key (an arbitrary but fixed, deterministic rule).
local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then
      return ta == "number" -- numbers first
    end
    return a < b
  end)
  return keys
end

--- Real "is this table a plain 1..n array with no gaps and no other
-- keys" test -- arrays get written as `{ v1, v2, ... }` (no explicit
-- indices), matching how a human would write the same literal.
local function isPlainArray(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  if n == 0 then return true end -- an empty table renders as {} either way
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return true
end

local serializeTable -- forward-declared: mutually recursive with serializeValue below

local function serializeValue(v, indent, out)
  local ty = type(v)
  if ty == "nil" then
    out[#out + 1] = "nil"
  elseif ty == "boolean" then
    out[#out + 1] = tostring(v)
  elseif ty == "number" then
    -- `%.17g` round-trips any real double exactly (the shortest
    -- representation that survives a full serialize/load cycle isn't
    -- computed here -- 17 significant digits is simpler and always
    -- correct, matching this module's own "correctness over
    -- prettiness" priority for a machine-generated file); integers
    -- print without a trailing ".0" so e.g. real ROM offsets/bank
    -- numbers stay readable as plain integers.
    if v == math.floor(v) and math.abs(v) < 2^53 then
      out[#out + 1] = string.format("%d", v)
    else
      out[#out + 1] = string.format("%.17g", v)
    end
  elseif ty == "string" then
    out[#out + 1] = quoteString(v)
  elseif ty == "table" then
    serializeTable(v, indent, out)
  else
    error(("LuaWriter.serialize: cannot serialize a real Lua %s value -- " ..
      "this module only handles plain tables/strings/numbers/booleans " ..
      "(functions/userdata/threads are never valid decoded ROM data)"):format(ty))
  end
end

serializeTable = function(t, indent, out)
  local nextIndent = indent .. "  "
  if isPlainArray(t) then
    if #t == 0 then
      out[#out + 1] = "{}"
      return
    end
    out[#out + 1] = "{\n"
    for i = 1, #t do
      out[#out + 1] = nextIndent
      serializeValue(t[i], nextIndent, out)
      out[#out + 1] = ",\n"
    end
    out[#out + 1] = indent .. "}"
    return
  end

  local keys = sortedKeys(t)
  if #keys == 0 then
    out[#out + 1] = "{}"
    return
  end
  out[#out + 1] = "{\n"
  for _, k in ipairs(keys) do
    out[#out + 1] = nextIndent
    if isBareword(k) then
      out[#out + 1] = k .. " = "
    else
      out[#out + 1] = "["
      serializeValue(k, nextIndent, out)
      out[#out + 1] = "] = "
    end
    serializeValue(t[k], nextIndent, out)
    out[#out + 1] = ",\n"
  end
  out[#out + 1] = indent .. "}"
end

--- Serializes `value` into a complete, loadable Lua source string:
-- an optional `header` (a real, human-readable comment block --
-- typically "generated by scripts/extract_rom_cache.lua, do not edit
-- by hand" plus the real ROM SHA-1 this cache was generated from, see
-- `RomExtractor.lua`'s own manifest) followed by `return <value>`.
-- `loadstring(LuaWriter.serialize(v))()` (or `load()` on modern Lua)
-- reproduces `v` exactly for any value this module accepts -- the
-- real property `tests/import/lua_writer_test.lua` verifies.
function LuaWriter.serialize(value, header)
  local out = {}
  if header then
    out[#out + 1] = header
    if header:sub(-1) ~= "\n" then out[#out + 1] = "\n" end
  end
  out[#out + 1] = "return "
  serializeValue(value, "", out)
  out[#out + 1] = "\n"
  return table.concat(out)
end

return LuaWriter
