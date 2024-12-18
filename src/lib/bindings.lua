local log = require("lib.logging")
local persist = require("lib.persist")

local Bindings = {}

local CONNECTION_BINDINGS_PERSIST_KEY = "ConnectionBindings"
local CONTROL_BINDING_START = 10
local CONTROL_BINDING_END = 999
local PROXY_BINDING_START = 5012
local PROXY_BINDING_END = 5999

function Bindings:new()
  log:trace("Binding:new()")
  local properties = {}
  setmetatable(properties, self)
  self.__index = self
  return properties
end

function Bindings:getOrAddDynamicBinding(namespace, key, type, provider, displayName, class)
  log:trace(
    "Binding:getOrAddDynamicBinding(%s, %s, %s, %s, %s, %s)",
    namespace,
    key,
    type,
    provider,
    displayName,
    class
  )
  local bindings = self:_getBindings()
  local binding = Select(bindings, namespace, key)
  if binding == nil then
    local bindingId = self:_getNextBindingId(type)
    if bindingId == nil then
      return nil
    end
    binding = {
      bindingId = bindingId,
      type = type,
      provider = provider,
      displayName = displayName,
      class = class,
    }

    bindings[namespace] = bindings[namespace] or {}
    bindings[namespace][key] = binding
    self:_saveBindings(bindings)
    C4:AddDynamicBinding(bindingId, type, provider, displayName, class, false, false)
  end
  return binding
end

function Bindings:getDynamicBinding(namespace, key)
  log:trace("Binding:getOrAddDynamicBinding(%s, %s)", namespace, key)
  local bindings = self:_getBindings()
  return Select(bindings, namespace, key)
end

function Bindings:getDynamicBindings(namespace)
  log:trace("Binding:getDynamicBindings(%s)", namespace)
  local bindings = self:_getBindings()
  return Select(bindings, namespace) or {}
end

function Bindings:deleteBinding(namespace, key)
  log:trace("Binding:deleteBinding(%s, %s)", namespace, key)
  local bindings = self:_getBindings()
  local bindingId = Select(bindings, namespace, key, "bindingId")
  if type(bindingId) ~= "number" then
    return
  end

  C4:RemoveDynamicBinding(bindingId)
  RFP[bindingId] = nil
  OBC[bindingId] = nil

  bindings[namespace][key] = nil
  if IsEmpty(bindings[namespace]) then
    bindings[namespace] = nil
  end
  if IsEmpty(bindings) then
    bindings = nil
  end

  self:_saveBindings(bindings)
end

function Bindings:restoreBindings()
  log:trace("Binding:restoreBindings()")
  local deviceBindings = GetDeviceBindings(C4:GetDeviceID())
  for _, keys in pairs(self:_getBindings()) do
    for _, binding in pairs(keys) do
      deviceBindings[binding.bindingId] = nil
      C4:AddDynamicBinding(
        binding.bindingId,
        binding.type,
        binding.provider,
        binding.displayName,
        binding.class,
        false,
        false
      )
    end
  end
  for bindingId, _ in pairs(deviceBindings) do
    log:debug("Deleting unknown binding %s", bindingId)
    C4:RemoveDynamicBinding(bindingId)
  end
end

function Bindings:_getNextBindingId(type)
  log:trace("Binding:_getNextBindingId(%s)", type)
  local currentBindings = {}
  for _, keys in pairs(self:_getBindings()) do
    for _, binding in pairs(keys) do
      currentBindings[binding.bindingId] = true
    end
  end
  local nextId, maxId = CONTROL_BINDING_START, CONTROL_BINDING_END
  if type == "PROXY" then
    nextId, maxId = PROXY_BINDING_START, PROXY_BINDING_END
  end
  while currentBindings[nextId] ~= nil and nextId <= maxId do
    nextId = nextId + 1
  end
  if nextId > maxId then
    log:error("maximum %s bindings exceeded", type)
    return nil
  end
  return nextId
end

function Bindings:_getBindings()
  log:trace("Binding:_getBindings()")
  return persist:get(CONNECTION_BINDINGS_PERSIST_KEY, {})
end

function Bindings:_saveBindings(bindings)
  log:trace("Binding:_saveBindings(%s)", bindings)
  persist:set(CONNECTION_BINDINGS_PERSIST_KEY, not IsEmpty(bindings) and bindings or nil)
end

return Bindings:new()
