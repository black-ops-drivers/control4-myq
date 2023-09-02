DRIVER_GITHUB_REPO = "black-ops-drivers/control4-myq"
DRIVER_FILENAMES = {
  "myq_controller.c4z",
  "myq_device.c4z",
}
--
require("lib.utils")
require("vendor.drivers-common-public.global.handlers")
require("vendor.drivers-common-public.global.lib")
require("vendor.drivers-common-public.global.timer")
require("vendor.drivers-common-public.global.url")

JSON = require("vendor.JSON")

local log = require("lib.logging")
local bindings = require("lib.bindings")
local githubUpdater = require("lib.github-updater")

local api = require("api")

local function updateStatus(status)
  UpdateProperty("Driver Status", not IsEmpty(status) and status or "Unknown")
end

function OnDriverLateInit()
  if not CheckMinimumVersion() then
    return
  end
  gInitialized = false
  log:setLogName(C4:GetDeviceData(C4:GetDeviceID(), "name"))
  log:setLogLevel(Properties["Log Level"])
  log:setLogMode(Properties["Log Mode"])
  log:trace("OnDriverLateInit()")

  C4:AllowExecute(true)
  C4:FileSetDir("c29tZXNwZWNpYWxrZXk=++11")
  bindings:restoreBindings()

  -- Fire OnPropertyChanged to set the initial Headers and other Property
  -- global sets, they'll change if Property is changed.
  for p, _ in pairs(Properties) do
    local status, err = pcall(OnPropertyChanged, p)
    if not status then
      log:error(err)
    end
  end
  gInitialized = true

  api:setStatusCallback(updateStatus)
  Connect()
end

function OPC.Driver_Version(propertyValue)
  log:trace("OPC.Driver_Version('%s')", propertyValue)
  C4:UpdateProperty("Driver Version", C4:GetDriverConfigInfo("version"))
end

function OPC.Log_Mode(propertyValue)
  log:trace("OPC.Log_Mode('%s')", propertyValue)
  log:setLogMode(propertyValue)
  CancelTimer("LogMode")
  if not log:isEnabled() then
    return
  end
  log:warn("Log mode '%s' will expire in 3 hours", propertyValue)
  SetTimer("LogMode", 3 * ONE_HOUR, function()
    log:warn("Setting log mode to 'Off' (timer expired)")
    UpdateProperty("Log Mode", "Off", true)
  end)
end

function OPC.Log_Level(propertyValue)
  log:trace("OPC.Log_Level('%s')", propertyValue)
  log:setLogLevel(propertyValue)
  if log:getLogLevel() >= 6 and log:isPrintEnabled() then
    DEBUGPRINT = true
    DEBUG_TIMER = true
    DEBUG_RFN = true
    DEBUG_URL = true
  else
    DEBUGPRINT = false
    DEBUG_TIMER = false
    DEBUG_RFN = false
    DEBUG_URL = false
  end
end

function OPC.Email(propertyValue)
  log:trace("OPC.Email('%s')", propertyValue)
  api:setEmail(propertyValue)
  Connect()
end

function OPC.Password(propertyValue)
  log:trace("OPC.Password('%s')", not IsEmpty(propertyValue) and "****" or "")
  api:setPassword(propertyValue)
  Connect()
end

local transitioningUntilTime = 0

function Connect()
  log:trace("Connect()")
  if not gInitialized then
    updateStatus("Disconnected")
    return
  end

  updateStatus("Connecting")
  local lastUpdateTime = os.time() -- Don't check for updates on the first cycle
  local lastDevicesRefreshTime = 0
  local lastStatusesRefreshTime = 0

  local refresh = function()
    local now = os.time()
    local secondsSinceLastUpdate = now - lastUpdateTime
    local secondsSinceLastDevicesRefresh = now - lastDevicesRefreshTime
    local secondsSinceLastStatusesRefresh = now - lastStatusesRefreshTime
    if Properties["Automatic Updates"] == "Yes" and secondsSinceLastUpdate > (30 * 60) then
      log:info("Checking for driver update (timer expired)")
      lastUpdateTime = now
      UpdateDrivers()
    elseif secondsSinceLastDevicesRefresh > (15 * 60) then
      log:info("Fetching devices from the myQ API (timer expired)")
      lastDevicesRefreshTime = now
      RefreshDevices()
    elseif
      not api:hasAuthenticationFailure() and (now <= transitioningUntilTime or secondsSinceLastStatusesRefresh > 10)
    then
      log:debug("Fetching device statuses from the myQ API (timer expired)")
      lastStatusesRefreshTime = now
      RefreshDeviceStatuses()
    end
  end
  -- Perform the initial refresh then schedule it on a repeating timer
  refresh()
  SetTimer("Refresh", 5 * ONE_SECOND, refresh, true)
end

function EC.RefreshDevices()
  log:trace("EC.RefreshDevices()")
  log:print("Refreshing devices")
  RefreshDevices()
end

local function sendDeviceStatusToProxies(devices)
  log:trace("sendDeviceStatusToProxies(%s)", devices)
  for _, device in pairs(devices or {}) do
    local deviceBinding = bindings:getDynamicBinding("myQ", device.serial_number)
    if not IsEmpty(deviceBinding) then
      if toboolean(Select(device, "state", "online")) then
        log:debug("  %s -> %s", device.displayName, (Select(device, "state", "door_state") or "unknown"):upper())
      else
        log:debug("  %s -> OFFLINE", device.displayName)
      end
      SendToProxy(deviceBinding.bindingId, "UPDATE_STATE", { state = Serialize(device) })
    end
  end
end

function RefreshDevices()
  log:trace("RefreshDevices()")
  api:getDevices():next(function(devices)
    -- Create device bindings
    local deviceBindings = bindings:getDynamicBindings("myQ")
    for _, device in pairs(devices or {}) do
      log:info("Discovered device '%s'", device.displayName)
      deviceBindings[device.serial_number] = nil
      local binding =
        bindings:getOrAddDynamicBinding("myQ", device.serial_number, "PROXY", true, device.displayName, "MYQ_DEVICE")
      if binding == nil then
        return reject("number of devices exceeds this driver's limit!")
      end
      RFP[binding.bindingId] = function(idBinding, strCommand, tParams, args)
        log:trace("RFP idBinding=%s strCommand=%s tParams=%s args=%s", idBinding, strCommand, tParams, args)
        if strCommand == "DEVICE_COMMAND" and not IsEmpty(Select(tParams, "command")) then
          if tParams.command == "open" or tParams.command == "close" then
            api:commandDevice(device, tParams.command):next(function()
              log:debug("%s command sent to device %s", tParams.command, device.displayName)
              transitioningUntilTime = os.time() + 25
            end, function(error)
              log:error(
                "An error occurred sending %s command to device %s; %s",
                tParams.command,
                device.displayName,
                error
              )
            end)
          end
        end
      end
      OBC[binding.bindingId] = function(idBinding, strClass, bIsBound, otherDeviceId, otherBindingId)
        log:debug(
          "OBC idBinding=%s strClass=%s bIsBound=%s otherDeviceId=%s otherBindingId=%s",
          idBinding,
          strClass,
          bIsBound,
          otherDeviceId,
          otherBindingId
        )
        if bIsBound then
          RefreshDevices()
        end
      end
    end
    -- Delete any bindings for removed devices
    for bindingKey, binding in pairs(deviceBindings) do
      log:info("Deleting device '%s' that was removed from your account", binding.displayName)
      bindings:deleteBinding("myQ", bindingKey)
    end
    sendDeviceStatusToProxies(devices)
  end, function(error)
    log:error("An error occurred refreshing devices; %s", error)
  end)
end

function RefreshDeviceStatuses()
  log:trace("RefreshDeviceStatuses()")
  api:getDevices():next(sendDeviceStatusToProxies, function(error)
    log:error("An error occurred refreshing devices statuses; %s", error)
  end)
end

function EC.UpdateDrivers()
  log:trace("EC.UpdateDrivers()")
  log:print("Updating drivers")
  UpdateDrivers(true)
end

function UpdateDrivers(forceUpdate)
  log:trace("UpdateDrivers(%s)", forceUpdate)
  githubUpdater
    :updateAll(DRIVER_GITHUB_REPO, DRIVER_FILENAMES, Properties["Update Channel"] == "Prerelease", forceUpdate)
    :next(function(updatedDrivers)
      if not IsEmpty(updatedDrivers) then
        log:info("Updated driver(s): %s", table.concat(updatedDrivers, ","))
      else
        log:debug("No driver updates available")
      end
    end, function(error)
      log:error("An error occurred updating drivers; %s", error)
    end)
end
