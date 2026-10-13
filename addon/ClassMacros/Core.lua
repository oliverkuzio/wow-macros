-- ClassMacros: syncs the macros for the player's class into per-character macro slots.
-- Written for Lua 5.0 (1.12-based clients): no '#', '%', select() or varargs.

local MAX_PER_CHARACTER = 18
local DEFAULT_ICON = "INV_Misc_QuestionMark"

local synced = false
local pendingSync = false
local status = {}

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ClassMacros|r: " .. msg)
end

local function Trim(s)
  local _, _, inner = string.find(s, "^%s*(.-)%s*$")
  return inner
end

-- Account macros occupy the low indexes, per-character macros follow them.
local function AccountSlots()
  return MAX_ACCOUNT_MACROS or 36
end

local function IsPerCharacter(index)
  return index > AccountSlots()
end

-- The 1.12 macro API takes icon indexes; later clients take texture names.
local function UsesLegacyMacroAPI()
  local _, _, _, toc = GetBuildInfo()
  return toc == nil or tonumber(toc) < 20000
end

local function FindIconIndex(texture)
  if not GetNumMacroIcons then return 1 end
  local needle = string.lower(texture or DEFAULT_ICON)
  local fallback = 1
  for i = 1, GetNumMacroIcons() do
    local icon = string.lower(GetMacroIconInfo(i) or "")
    if icon == needle then return i end
    if string.find(icon, needle, 1, true) then fallback = i end
  end
  return fallback
end

local function CreateMacroCompat(name, body)
  local legacy = function() return CreateMacro(name, FindIconIndex(DEFAULT_ICON), body, 1, 1) end
  local modern = function() return CreateMacro(name, DEFAULT_ICON, body, 1) end
  local first, second = modern, legacy
  if UsesLegacyMacroAPI() then first, second = legacy, modern end
  local ok, result = pcall(first)
  if ok then return result end
  ok, result = pcall(second)
  if ok then return result end
  Print("could not create '" .. name .. "': " .. tostring(result))
end

local function EditMacroCompat(index, name, body)
  local _, texture = GetMacroInfo(index)
  local legacy = function() return EditMacro(index, name, FindIconIndex(texture), body, 1) end
  local modern = function() return EditMacro(index, name, nil, body) end
  local first, second = modern, legacy
  if UsesLegacyMacroAPI() then first, second = legacy, modern end
  local ok, result = pcall(first)
  if ok then return true end
  ok, result = pcall(second)
  if ok then return true end
  Print("could not update '" .. name .. "': " .. tostring(result))
end

-- Replaces <Key> placeholders with this character's values. Returns the body and
-- a comma-separated list of missing keys (nil when every placeholder is filled).
local function FillPlaceholders(body)
  local missing = nil
  local seen = {}
  local filled = string.gsub(body, "<([^<>\n]*)>", function(key)
    key = Trim(key)
    local value = ClassMacrosDB.placeholders[string.lower(key)]
    if value then return value end
    if not seen[key] then
      seen[key] = true
      if missing then missing = missing .. ", " .. key else missing = key end
    end
    return "<" .. key .. ">"
  end)
  return filled, missing
end

local function EnsureDB()
  ClassMacrosDB = ClassMacrosDB or {}
  ClassMacrosDB.managed = ClassMacrosDB.managed or {}
  ClassMacrosDB.placeholders = ClassMacrosDB.placeholders or {}
end

local function PlayerMacros()
  local _, class = UnitClass("player")
  return class, ClassMacros_Data[class] or {}
end

-- verbose prints the summary even when nothing changed; warn prints macros that could not sync.
local function Sync(verbose, warn)
  EnsureDB()
  if UnitAffectingCombat("player") then
    pendingSync = true
    Print("in combat, will sync when combat ends.")
    return
  end
  pendingSync = false

  local class, macros = PlayerMacros()
  local wanted = {}
  local created, updated = 0, 0
  status = {}

  for i = 1, table.getn(macros) do
    local macro = macros[i]
    wanted[macro.name] = true
    local body, missing = FillPlaceholders(macro.body)
    local index = GetMacroIndexByName(macro.name)

    if missing then
      status[macro.name] = "needs /cm set for: " .. missing
    elseif index > 0 and not IsPerCharacter(index) then
      status[macro.name] = "skipped: an account-wide macro has this name"
    elseif index > 0 then
      local _, _, currentBody = GetMacroInfo(index)
      if currentBody ~= body then
        if EditMacroCompat(index, macro.name, body) then updated = updated + 1 end
      end
      ClassMacrosDB.managed[macro.name] = true
      status[macro.name] = "ok"
    else
      local _, numPerChar = GetNumMacros()
      if numPerChar >= (MAX_CHARACTER_MACROS or MAX_PER_CHARACTER) then
        status[macro.name] = "not created: no free per-character macro slot"
      elseif CreateMacroCompat(macro.name, body) then
        created = created + 1
        ClassMacrosDB.managed[macro.name] = true
        status[macro.name] = "ok"
      else
        status[macro.name] = "not created: error"
      end
    end
  end

  -- Remove macros this addon created earlier that are no longer in the data.
  local removed = 0
  for name in pairs(ClassMacrosDB.managed) do
    if not wanted[name] then
      local index = GetMacroIndexByName(name)
      if index > 0 and IsPerCharacter(index) then
        DeleteMacro(index)
        removed = removed + 1
      end
      ClassMacrosDB.managed[name] = nil
    end
  end

  synced = true
  if verbose or created + updated + removed > 0 then
    Print(string.format("%s: %d created, %d updated, %d removed.", class or "?", created, updated, removed))
  end
  if verbose or warn then
    for name, state in pairs(status) do
      if state ~= "ok" then Print(name .. " - " .. state) end
    end
  end
end

local function Reset()
  if UnitAffectingCombat("player") then
    Print("cannot reset in combat.")
    return
  end
  for name in pairs(ClassMacrosDB.managed) do
    local index = GetMacroIndexByName(name)
    if index > 0 and IsPerCharacter(index) then DeleteMacro(index) end
  end
  ClassMacrosDB.managed = {}
  Print("removed all managed macros. Use /cm sync to recreate them.")
end

-- Parses '"Key With Spaces" Value' or 'Key Value'.
local function ParseKeyValue(rest)
  local _, _, key, value = string.find(rest, '^"([^"]*)"%s*(.*)$')
  if not key then
    _, _, key, value = string.find(rest, "^(%S+)%s*(.*)$")
  end
  if not key then return nil end
  value = Trim(value or "")
  local _, _, unquoted = string.find(value, '^"(.*)"$')
  return Trim(key), unquoted or value
end

local function List()
  local class, macros = PlayerMacros()
  Print((class or "?") .. " macros:")
  for i = 1, table.getn(macros) do
    local name = macros[i].name
    Print("  " .. name .. " - " .. (status[name] or "not synced"))
  end
end

local function Slash(msg)
  EnsureDB()
  local _, _, cmd, rest = string.find(msg or "", "^%s*(%S*)%s*(.*)$")
  cmd = string.lower(cmd or "")
  if cmd == "sync" then
    Sync(true)
  elseif cmd == "list" then
    List()
  elseif cmd == "set" then
    local key, value = ParseKeyValue(rest or "")
    if not key then
      Print('usage: /cm set "<Key>" <value>   (empty value clears it)')
      return
    end
    if value == "" then value = nil end
    ClassMacrosDB.placeholders[string.lower(key)] = value
    Print("<" .. key .. "> = " .. (value or "(cleared)"))
    Sync(false)
  elseif cmd == "get" then
    local _, macros = PlayerMacros()
    local seen = {}
    for i = 1, table.getn(macros) do
      local keys = macros[i].placeholders
      for j = 1, table.getn(keys) do
        local key = keys[j]
        if not seen[key] then
          seen[key] = true
          Print("<" .. key .. "> = " .. (ClassMacrosDB.placeholders[string.lower(key)] or "(not set)"))
        end
      end
    end
  elseif cmd == "reset" then
    Reset()
  else
    Print("/cm sync | list | get | set \"<Key>\" <value> | reset")
  end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(self, evt)
  evt = evt or event
  if evt == "PLAYER_ENTERING_WORLD" then
    if not synced then Sync(false, true) end
  elseif evt == "PLAYER_REGEN_ENABLED" and pendingSync then
    Sync(false)
  end
end)

SLASH_CLASSMACROS1 = "/cm"
SLASH_CLASSMACROS2 = "/classmacros"
SlashCmdList["CLASSMACROS"] = Slash
