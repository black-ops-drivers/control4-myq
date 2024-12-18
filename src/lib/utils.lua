local deferred = require("vendor.deferred")

local log = require("lib.logging")

function CheckMinimumVersion()
  if not C4.GetDriverConfigInfo or not (VersionCheck(C4:GetDriverConfigInfo("minimum_os_version"))) then
    C4:UpdateProperty(
      "Driver Version",
      table.concat({
        "DRIVER DISABLED - ",
        C4:GetDriverConfigInfo("model"),
        "driver",
        C4:GetDriverConfigInfo("version"),
        "requires at least C4 OS",
        C4:GetDriverConfigInfo("minimum_os_version"),
        ": current C4 OS is",
        C4:GetVersionInfo().version,
      }, " ")
    )
    for p, _ in pairs(Properties) do
      C4:SetPropertyAttribs(p, 1)
    end
    C4:SetPropertyAttribs("Driver Version", 0)
    return false
  end
  return true
end

function GetDriverVersion(filename)
  local basename, _ = filename:match("(.*)%.(.*)")
  C4:FileSetDir("C4Z_ROOT", basename)
  return Select(ParseXml(FileRead("driver.xml")) or {}, "devicedata", "version") or nil
end

local function LogSendTo(func, ...)
  local numArgs = select("#", ...)
  local args = { ... }

  local logArgsFmt = ""
  for i, _ in pairs(args) do
    logArgsFmt = logArgsFmt .. "%s"
    if i ~= numArgs then
      logArgsFmt = logArgsFmt .. ", "
    end
  end
  log:trace("%s(" .. logArgsFmt .. ")", func, unpack(args))
end

function SendToDevice(...)
  LogSendTo("C4:SendToDevice", ...)
  return C4:SendToDevice(...)
end

function SendToProxy(...)
  LogSendTo("C4:SendToProxy", ...)
  return C4:SendToProxy(...)
end

function SendToNetwork(...)
  LogSendTo("C4:SendToNetwork", ...)
  return C4:SendToNetwork(...)
end

function GetDeviceBindings(deviceId, typeFilter, providerFilter, displayNameFilter, classFilter)
  log:trace(
    "GetDeviceBindings(%s, %s, %s, %s, %s)",
    deviceId,
    typeFilter,
    providerFilter,
    displayNameFilter,
    classFilter
  )
  local deviceBindings = Select(C4:GetBindingsByDevice(deviceId), "bindings") or {}
  local matchedBindings = {}
  for _, binding in pairs(deviceBindings) do
    if
      (typeFilter == nil or Select(binding, "type") == typeFilter)
      and (providerFilter == nil or Select(binding, "provider") == providerFilter)
      and (displayNameFilter == nil or Select(binding, "name") == displayNameFilter)
    then
      for _, bindingClass in pairs(Select(binding, "bindingclasses") or {}) do
        local bindingId = tointeger(Select(binding, "bindingid"))
        if bindingId ~= nil and (classFilter == nil or Select(bindingClass, "class") == classFilter) then
          matchedBindings[bindingId] = binding
        end
      end
    end
  end
  return matchedBindings
end

local xml2lua = require("vendor.xml.xml2lua")
local handler = require("vendor.xml.xmlhandler.tree")

function ParseXml(xmlStr)
  if IsEmpty(xmlStr) then
    return {}
  end
  local h = handler:new()
  local parser = xml2lua.parser(h)
  parser:parse(xmlStr)
  return h.root
end

function InRange(n, min, max)
  if n == nil then
    return nil
  end
  if min ~= nil then
    n = math.max(min, n)
  end
  if max ~= nil then
    n = math.min(max, n)
  end
  return n
end

function round(num, numDecimalPlaces)
  local mult = 10 ^ (numDecimalPlaces or 0)
  return math.floor(num * mult + 0.5) / mult
end

function TableLength(t)
  if type(t) ~= "table" then
    return 0
  end
  local n = 0
  for _ in pairs(t) do
    n = n + 1
  end
  return n
end

function TableKeys(t)
  if type(t) ~= "table" then
    return {}
  end
  local keys = {}
  for key, _ in pairs(t) do
    table.insert(keys, key)
  end
  return keys
end

function TableValues(t)
  if type(t) ~= "table" then
    return {}
  end
  local values = {}
  for _, value in pairs(t) do
    table.insert(values, value)
  end
  return values
end

function TableMap(t, func)
  if IsEmpty(t) then
    return {}
  end
  local retValue = {}
  for k, v in pairs(t) do
    retValue[k] = func(v, k)
  end
  return retValue
end

function TableReverse(t)
  local r = {}
  for k, v in pairs(t) do
    r[v] = k
  end
  return r
end

function TableShallowMerge(...)
  local m = {}
  for _, t in pairs({ ... }) do
    if type(t or false) == "table" then
      for k, v in pairs(t or {}) do
        m[k] = v
      end
    end
  end
  return m
end

function TableDeepCopy(t, seen)
  seen = seen or {}
  if t == nil then
    return nil
  end
  if seen[t] then
    return seen[t]
  end

  local copy
  if type(t) == "table" then
    copy = {}
    seen[t] = copy

    for k, v in next, t, nil do
      copy[TableDeepCopy(k, seen)] = TableDeepCopy(v, seen)
    end
    setmetatable(copy, TableDeepCopy(getmetatable(t), seen))
  else -- number, string, boolean, etc
    copy = t
  end
  return copy
end

function UniqueList(t)
  if type(t) ~= "table" then
    return {}
  end
  local seen = {}
  local list = {}

  for _, v in ipairs(t) do
    if not seen[v] then
      table.insert(list, v)
      seen[v] = true
    end
  end
  return list
end

function ConcatLists(...)
  local c = {}
  for _, t in pairs({ ... }) do
    if type(t) == "table" then
      for _, v in ipairs(t) do
        table.insert(c, v)
      end
    end
  end
  return c
end

function SortList(t)
  table.sort(t)
  return t
end

function IsList(t)
  if type(t) ~= "table" then
    return false
  end
  local i = 0
  for _ in pairs(t) do
    i = i + 1
    if t[i] == nil then
      return false
    end
  end
  return true
end

function IsEmpty(v)
  if v == nil then
    return true
  end
  if type(v) == "string" then
    return v == ""
  end
  if type(v) == "table" then
    return next(v) == nil
  end
  if type(v) == "number" then
    return v == 0
  end
  if type(v) == "boolean" then
    return not v
  end
  return false
end

function toboolean(val)
  if
    type(val) == "string"
    and (string.lower(val) == "true" or string.lower(val) == "yes" or val == "1" or string.lower(val) == "on")
  then
    return true
  elseif type(val) == "number" and val ~= 0 then
    return true
  elseif type(val) == "boolean" then
    return val
  end

  return false
end

function tointeger(val)
  local nval = tonumber(val)
  if nval == nil then
    return nil
  end
  return (nval >= 0) and math.floor(nval + 0.5) or math.ceil(nval - 0.5)
end

function delay(ms)
  local d = deferred.new()
  if IsEmpty(ms) or ms <= 0 then
    return d:resolve()
  end

  SetTimer(C4:UUID("Random"), ms, function()
    d:resolve()
  end)
  return d
end

function reject(error)
  return deferred.new():reject(error)
end

function resolve(value)
  return deferred.new():resolve(value)
end

function hex2rgb(hex)
  if type(hex) ~= "string" then
    return nil
  end
  hex = hex:gsub("#", "")
  if hex:len() == 3 then
    return (tonumber("0x" .. hex:sub(1, 1)) * 17)
      .. ","
      .. (tonumber("0x" .. hex:sub(2, 2)) * 17)
      .. ","
      .. (tonumber("0x" .. hex:sub(3, 3)) * 17)
  elseif hex:len() == 6 then
    return tonumber("0x" .. hex:sub(1, 2))
      .. ","
      .. tonumber("0x" .. hex:sub(3, 4))
      .. ","
      .. tonumber("0x" .. hex:sub(5, 6))
  end
  return nil
end

function rgb2hex(rgb)
  local hex = ""
  for color in string.gmatch(rgb, "%d+") do
    hex = hex .. string.format("%02x", color)
  end
  return hex
end
