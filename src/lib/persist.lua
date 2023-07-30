local log = require("lib.logging")

local Persist = {}

local EMPTY = {}

function Persist:new()
  log:trace("Persist:new()")
  local properties = {
    _persist = {},
  }
  setmetatable(properties, self)
  self.__index = self
  return properties
end

function Persist:get(key, default, encrypted)
  log:trace("Persist:get(%s, %s, %s)", key, default, encrypted)
  if default == nil then
    default = EMPTY
  end
  local value = self._persist[key]

  if value == nil then
    value = Deserialize(PersistGetValue(key, encrypted))
    if value == nil then
      value = default
    end
    self._persist[key] = value
  end

  if value == EMPTY or value == nil then
    return default
  elseif type(value) == "table" then
    return TableDeepCopy(value)
  else
    return value
  end
end

function Persist:set(key, value, encrypted)
  log:trace("Persist:set(%s, %s, %s)", key, value, encrypted)
  if value == nil then
    self._persist[key] = EMPTY
    PersistDeleteValue(key)
  else
    if type(value) == "table" then
      self._persist[key] = TableDeepCopy(value)
    else
      self._persist[key] = value
    end
    PersistSetValue(key, Serialize(self._persist[key]), encrypted)
  end
end

function Persist:delete(key)
  log:trace("Persist:delete(%s)", key)
  self:set(key, nil)
end

return Persist:new()
