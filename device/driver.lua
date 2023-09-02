require("lib.utils")
require("vendor.drivers-common-public.global.handlers")
require("vendor.drivers-common-public.global.lib")
require("vendor.drivers-common-public.global.timer")

JSON = require("vendor.JSON")

local log = require("lib.logging")
local persist = require("lib.persist")

local LED_DEFAULTS_INITIALIZED_PERSIST_KEY = "LedDefaultsInitialized"
local PROXY_BINDING = 5001
local MYQ_BINDING = 5002

local TOGGLE_LINK_ID = 500
local OPEN_LINK_ID = 501
local CLOSE_LINK_ID = 502
local STATE -- leaving this explicitly nil so we can distinguish driver init from "unknown"

local function setButtonLedColorsToProjectDefaults(force)
  log:trace("setButtonLedColorsToProjectDefaults(%s)", force)
  if not force and persist:get(LED_DEFAULTS_INITIALIZED_PERSIST_KEY, false) then
    log:debug("Button LED colors already initialized; ignoring")
    return
  end
  persist:set(LED_DEFAULTS_INITIALIZED_PERSIST_KEY, true)

  log:info("Setting button LED colors to project defaults")
  local items = Select(ParseXml(C4:GetProjectItems("LIMIT_DEVICE_DATA", "LOCATIONS")), "systemitems")
  if not IsList(items) then
    items = { items }
  end
  local openDefault, closedDefault, inactiveDefault
  for _, item in pairs(items) do
    if Select(item, "item", "id") == "1" then
      openDefault = Select(item, "item", "itemdata", "toggle_on")
      closedDefault = Select(item, "item", "itemdata", "toggle_off")
      inactiveDefault = Select(item, "item", "itemdata", "top_off")
      break
    end
  end
  UpdateProperty("Opened LED Color", hex2rgb(openDefault) or "0,200,0")
  UpdateProperty("Closed LED Color", hex2rgb(closedDefault) or "200,0,0")
  UpdateProperty("Partial Open LED Color", hex2rgb(openDefault) or "200,200,0")
  UpdateProperty("Inactive LED Color", hex2rgb(inactiveDefault) or "0,0,200")
  UpdateProperty("Unknown LED Color", "0,0,0")
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

  -- Fire OnPropertyChanged to set the initial Headers and other Property
  -- global sets, they'll change if Property is changed.
  for p, _ in pairs(Properties) do
    local status, err = pcall(OnPropertyChanged, p)
    if not status then
      log:error(err)
    end
  end
  gInitialized = true

  C4:AddVariable("STATE", "unknown", "STRING", false, false)
  setButtonLedColorsToProjectDefaults()
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

function EC.Open()
  log:trace("EC.Open()")
  SendToProxy(MYQ_BINDING, "DEVICE_COMMAND", { command = "open" })
end

function EC.Close()
  log:trace("EC.Close()")
  SendToProxy(MYQ_BINDING, "DEVICE_COMMAND", { command = "close" })
end

function EC.ResetLEDColors()
  log:trace("EC.ResetLEDColors()")
  setButtonLedColorsToProjectDefaults(true)
end

function TC.State(strName, tConditions)
  log:trace("TC.State(%s, %s)", strName, tConditions)
  local value = (Select(tConditions, "VALUE") or ""):lower()
  local state = STATE
  if state == "opening" or state == "closing" then
    state = "partially open"
  elseif state == "stopped" or state == "autoreverse" then
    state = "unknown"
  end

  if Select(tConditions, "LOGIC") == "EQUAL" then
    return value == state
  elseif Select(tConditions, "LOGIC") == "NOT_EQUAL" then
    return value ~= state
  end
  return false
end

function RFP.DO_CLICK(idBinding, strCommand, tParams, args)
  log:trace("RFP.DO_CLICK(%s, %s, %s, %s)", idBinding, strCommand, tParams, args)

  local iconType = Properties["Device Type"] == "Gate" and "gate" or "garage"
  local command, description, icon
  if (idBinding == TOGGLE_LINK_ID and STATE == "open") or (idBinding == CLOSE_LINK_ID and STATE ~= "closed") then
    command, description, icon = "close", "Close (Pending)", iconType .. "_pending"
  elseif (idBinding == TOGGLE_LINK_ID and STATE == "closed") or (idBinding == OPEN_LINK_ID and STATE ~= "open") then
    command, description, icon = "open", "Open (Pending)", iconType .. "_pending"
  elseif STATE == "opening" or STATE == "closing" then
    log:warn("Ignoring command; the device is not in a stationary state")
    return
  elseif (idBinding == CLOSE_LINK_ID and STATE == "closed") or (idBinding == OPEN_LINK_ID and STATE == "open") then
    log:warn("Ignoring command; the device is currently in the desired state")
    return
  else
    log:warn("Ignoring command; the device is in an unknown state")
    return
  end

  SendToProxy(MYQ_BINDING, "DEVICE_COMMAND", { command = command })
  SendToProxy(PROXY_BINDING, "ICON_CHANGED", { icon = icon, icon_description = description })
end

function RFP.SELECT(idBinding, strCommand, tParams, args)
  log:trace("RFP.SELECT(%s, %s, %s, %s)", idBinding, strCommand, tParams, args)
  RFP.DO_CLICK(TOGGLE_LINK_ID, "DO_CLICK", tParams, args)
end

local function getButtonColors()
  log:trace("getButtonColors()")
  return {
    OPENED = rgb2hex(Properties["Opened LED Color"] or "0,0,0"),
    CLOSED = rgb2hex(Properties["Closed LED Color"] or "0,0,0"),
    PARTIAL = rgb2hex(Properties["Partial Open LED Color"] or "0,0,0"),
    INACTIVE = rgb2hex(Properties["Inactive LED Color"] or "0,0,0"),
    UNKNOWN = rgb2hex(Properties["Unknown LED Color"] or "0,0,0"),
  }
end

local function setButtonColor(idBinding, onColor, offColor, state)
  log:trace("setButtonColor(%s, %s, %s, %s)", idBinding, onColor, offColor, state)
  SendToProxy(
    idBinding,
    "BUTTON_COLORS",
    { ON_COLOR = { COLOR_STR = onColor }, OFF_COLOR = { COLOR_STR = offColor } },
    "NOTIFY"
  )
  if state ~= nil then
    SendToProxy(idBinding, "MATCH_LED_STATE", { STATE = toboolean(state) and "1" or "0" })
  end
end

function RFP.REQUEST_BUTTON_COLORS(idBinding, strCommand, tParams, args)
  log:trace("RFP.REQUEST_BUTTON_COLORS(%s, %s, %s, %s)", idBinding, strCommand, tParams, args)
  local buttonColors = getButtonColors()
  if idBinding == TOGGLE_LINK_ID then
    setButtonColor(TOGGLE_LINK_ID, buttonColors.OPENED, buttonColors.CLOSED)
  elseif idBinding == OPEN_LINK_ID then
    setButtonColor(OPEN_LINK_ID, buttonColors.OPENED, buttonColors.INACTIVE)
  elseif idBinding == CLOSE_LINK_ID then
    setButtonColor(CLOSE_LINK_ID, buttonColors.CLOSED, buttonColors.INACTIVE)
  end
end

local function fireEvent(event)
  log:trace("fireEvent(%s)", event)
  log:info("Firing event '%s'", event)
  C4:FireEvent(event)
end

local STILL_OPEN_TIMER_ID = "StillOpen"

local function startStillOpenTimer()
  log:trace("startStillOpenTimer()")
  -- Do not restart the timer if it is already running
  if not IsEmpty(Timer[STILL_OPEN_TIMER_ID]) then
    return
  end

  local stillOpenTime = InRange(tointeger(Properties["Still Open Time (s)"]) or 0, 0, 3600)
  if stillOpenTime > 0 then
    log:debug("Starting Still Open Timer: " .. stillOpenTime .. " second(s)")
    SetTimer(STILL_OPEN_TIMER_ID, ONE_SECOND * stillOpenTime, function()
      fireEvent("Still Open")
    end)
  end
end

local function stopStillOpenTimer()
  log:trace("stopStillOpenTimer()")
  CancelTimer(STILL_OPEN_TIMER_ID)
end

local function updateState(newState)
  log:trace("updateState(%s)", newState)
  if IsEmpty(newState) or newState == STATE then
    log:debug("No state change; ignoring update")
    return
  end
  log:debug("State changed from %s -> %s", STATE, newState)

  -- Do not fire an event when STATE was uninitialized (ie. during driver initialization)
  local shouldFireEvent = STATE ~= nil
  STATE = newState or STATE

  C4:SetVariable("STATE", STATE)

  local deviceType = Properties["Device Type"] or "Unknown Device"
  local iconset = "garage"
  if deviceType == "Gate" then
    iconset = "gate"
  end

  -- Only record if we are also firing an event as otherwise there is no material change
  if shouldFireEvent then
    C4:RecordHistory(
      "Info",
      STATE,
      "Locks & Sensors",
      iconset == "gate" and "Gate" or "Garage Door",
      "The " .. deviceType .. " is " .. STATE
    )
  end

  local buttonColors = getButtonColors()
  if STATE == "open" then
    startStillOpenTimer()
    setButtonColor(TOGGLE_LINK_ID, buttonColors.OPENED, buttonColors.CLOSED, true)
    setButtonColor(CLOSE_LINK_ID, buttonColors.CLOSED, buttonColors.INACTIVE, false)
    setButtonColor(OPEN_LINK_ID, buttonColors.OPENED, buttonColors.INACTIVE, true)
    SendToProxy(PROXY_BINDING, "ICON_CHANGED", { icon = iconset .. "_open", icon_description = "Open" })
    if shouldFireEvent then
      fireEvent("Opened")
    end
  elseif STATE == "closed" then
    stopStillOpenTimer()
    setButtonColor(TOGGLE_LINK_ID, buttonColors.OPENED, buttonColors.CLOSED, false)
    setButtonColor(OPEN_LINK_ID, buttonColors.OPENED, buttonColors.INACTIVE, false)
    setButtonColor(CLOSE_LINK_ID, buttonColors.CLOSED, buttonColors.INACTIVE, true)
    SendToProxy(PROXY_BINDING, "ICON_CHANGED", { icon = iconset .. "_closed", icon_description = "Closed" })
    if shouldFireEvent then
      fireEvent("Closed")
    end
  elseif STATE == "opening" or STATE == "closing" then
    startStillOpenTimer()
    setButtonColor(TOGGLE_LINK_ID, buttonColors.PARTIAL, buttonColors.PARTIAL, true)
    setButtonColor(OPEN_LINK_ID, buttonColors.PARTIAL, buttonColors.PARTIAL, false)
    setButtonColor(CLOSE_LINK_ID, buttonColors.PARTIAL, buttonColors.PARTIAL, false)
    SendToProxy(
      PROXY_BINDING,
      "ICON_CHANGED",
      { icon = iconset .. "_partial", icon_description = STATE == "opening" and "Opening" or "Closing" }
    )
    if shouldFireEvent then
      fireEvent("Partial")
    end
  else
    startStillOpenTimer()
    setButtonColor(TOGGLE_LINK_ID, buttonColors.UNKNOWN, buttonColors.UNKNOWN, true)
    setButtonColor(OPEN_LINK_ID, buttonColors.UNKNOWN, buttonColors.UNKNOWN, false)
    setButtonColor(CLOSE_LINK_ID, buttonColors.UNKNOWN, buttonColors.UNKNOWN, false)
    SendToProxy(PROXY_BINDING, "ICON_CHANGED", { icon = iconset .. "_unknown", icon_description = "Unknown" })
    if shouldFireEvent then
      fireEvent("Unknown")
    end
  end
end

function RFP.UPDATE_STATE(idBinding, strCommand, tParams, args)
  log:trace("RFP.UPDATE_STATE(%s, %s, %s, %s)", idBinding, strCommand, tParams, args)
  if idBinding ~= MYQ_BINDING or IsEmpty(Select(tParams, "state")) then
    return
  end
  local device = Deserialize(tParams.state)
  log:trace("State: %s", device)

  -- Update device name property
  local displayName = Select(device, "displayName")
  if displayName and displayName ~= Properties["Device Name"] then
    UpdateProperty("Device Name", displayName)
  end

  -- Update device type property
  local deviceType = ({
    commercialdooropener = "Commercial Door Opener",
    garagedooropener = "Garage Door Opener",
    gate = "Gate",
    virtualgaragedooropener = "Virtual Garage Door Opener",
    wifigaragedooropener = "WiFi Garage Door Opener",
  })[(Select(device, "device_type") or ""):lower()] or "Unknown"
  if deviceType ~= Properties["Device Type"] then
    UpdateProperty("Device Type", deviceType)
  end

  -- Rename device if requested
  if
    toboolean(Properties["Auto-Rename"])
    and not IsEmpty(Select(device, "name"))
    and device.name ~= C4:GetDeviceDisplayName(C4:GetDeviceID() + 1)
  then
    C4:RenameDevice(C4:GetDeviceID() + 1, device.name)
  end

  -- Update status
  local online = toboolean(Select(device, "state", "online"))
  local status = online and (Select(device, "state", "door_state") or ""):lower() or "unknown"
  UpdateProperty("Device Status", online and status:upper() or "OFFLINE")
  updateState(status)
end
