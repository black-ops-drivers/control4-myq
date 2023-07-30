local Log = {}

function Log:new()
  local properties = {
    _logName = "",
    _logLevel = 5,
    _outputPrint = false,
    _outputC4Log = false,
    _maxTableLevels = 10,
  }
  setmetatable(properties, self)
  self.__index = self
  return properties
end

function Log:setLogName(logName)
  if logName == nil or logName == "" then
    logName = ""
  else
    logName = logName .. ": "
  end

  self._logName = logName
end

function Log:getLogName()
  return self._logName
end

function Log:setLogLevel(level)
  self._logLevel = tonumber(string.sub(level or "", 1, 1)) or self._logLevel
end

function Log:getLogLevel()
  return self._logLevel
end

function Log:setLogMode(logMode)
  logMode = logMode or ""
  self:setOutputPrintEnabled(logMode:find("Print") ~= nil)
  self:setOutputC4LogEnabled(logMode:find("Log") ~= nil)
end

function Log:setOutputPrintEnabled(value)
  self._outputPrint = value
end

function Log:setOutputC4LogEnabled(value)
  self._outputC4Log = value
end

function Log:isEnabled()
  return self:isPrintEnabled() or self:isC4LogEnabled()
end

function Log:isPrintEnabled()
  return self._outputPrint
end

function Log:isC4LogEnabled()
  return self._outputC4Log
end

local function fixFormatArgs(numArgs, args)
  for i = 1, numArgs + 1 do
    if args[i] == nil then
      args[i] = "nil"
    end
    if type(args[i]) == "table" then
      args[i] = JSON:encode(args[i])
    end
    if type(args[i]) ~= "string" and type(args[i]) ~= "number" then
      args[i] = tostring(args[i])
    end
  end
  return args
end

function Log:fatal(sLogText, ...)
  self:_log(0, sLogText, select("#", ...), { ... })
end

function Log:error(sLogText, ...)
  self:_log(1, sLogText, select("#", ...), { ... })
end

function Log:warn(sLogText, ...)
  self:_log(2, sLogText, select("#", ...), { ... })
end

function Log:info(sLogText, ...)
  self:_log(3, sLogText, select("#", ...), { ... })
end

function Log:debug(sLogText, ...)
  self:_log(4, sLogText, select("#", ...), { ... })
end

function Log:trace(sLogText, ...)
  self:_log(5, sLogText, select("#", ...), { ... })
end

function Log:ultra(sLogText, ...)
  self:_log(6, sLogText, select("#", ...), { ... })
end

function Log:print(sLogText, ...)
  self:_log(-1, sLogText, select("#", ...), { ... })
end

local maxTableLevels = 10
local function _renderTableAsString(tValue, tableText, sIndent, level)
  tableText = tableText or ""
  level = (level or 0) + 1
  sIndent = sIndent or ""

  if level <= maxTableLevels then
    if type(tValue) == "table" then
      for k, v in pairs(tValue) do
        if tableText == "" then
          tableText = sIndent .. tostring(k) .. ":  " .. tostring(v)
          if sIndent == ".   " then
            sIndent = "    "
          end
        else
          tableText = tableText .. "\n" .. sIndent .. tostring(k) .. ":  " .. tostring(v)
        end
        if type(v) == "table" then
          tableText = _renderTableAsString(v, tableText, sIndent .. "   ", level)
        end
      end
    else
      tableText = tableText .. "\n" .. sIndent .. tostring(tValue)
    end
  end

  return tableText
end

local function addLinePrefix(sPrefix, sLogText)
  local lines = {}
  for s in sLogText:gmatch("[^\r\n]+") do
    table.insert(lines, sPrefix .. s)
  end
  return table.concat(lines, "\n")
end

function Log:_log(level, sLogText, numArgs, args)
  if level == -1 or (self:isEnabled() and self._logLevel >= level) then
    args = fixFormatArgs(numArgs, args)
    if type(sLogText) == "string" then
      sLogText = string.format(sLogText, unpack(args))
    end

    if type(sLogText) == "table" then
      sLogText = _renderTableAsString(sLogText)
    end

    sLogText = tostring(sLogText)

    if level == -1 or self:isPrintEnabled() then
      print(addLinePrefix(self:_getPrintPrefix(level), sLogText))
    end

    if self:isC4LogEnabled() then
      if self._logLevel < 3 then
        C4:ErrorLog(addLinePrefix(self:_getLogPrefix(level), sLogText))
      else
        C4:DebugLog(addLinePrefix(self:_getLogPrefix(level), sLogText))
      end
    end
  end
end

local function _getLevelPrefix(level)
  local levelNames = {
    [-1] = "[PRINT]",
    [0] = "[FATAL]",
    [1] = "[ERROR]",
    [2] = "[WARN ]",
    [3] = "[INFO ]",
    [4] = "[DEBUG]",
    [5] = "[TRACE]",
    [6] = "[ULTRA]",
  }
  return (levelNames[level] or "[UKNWN]") .. ": "
end

function Log:_getPrintPrefix(level)
  return os.date() .. " " .. _getLevelPrefix(level)
end

function Log:_getLogPrefix(level)
  local prefix = ""
  if not IsEmpty(self._logName) then
    prefix = "[" .. self._logName .. "]"
  end
  return prefix .. _getLevelPrefix(level)
end

return Log:new()
