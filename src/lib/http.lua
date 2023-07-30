local deferred = require("vendor.deferred")

local log = require("lib.logging")

local DEFAULT_TIMEOUT = 10 * 1000

local Http = {}

function Http:new()
  log:trace("Http:new()")
  local properties = {
    _defaultTimeout = DEFAULT_TIMEOUT,
  }
  setmetatable(properties, self)
  self.__index = self
  return properties
end

function Http:setDefaultTimeout(timeout)
  log:trace("Http:setDefaultTimeout(%s)", timeout)
  self._defaultTimeout = tointeger(timeout)
end

function Http:getDefaultTimeout()
  log:trace("Http:getDefaultTimeout()")
  return self._defaultTimeout
end

function Http:request(method, url, data, headers, options)
  log:trace("Http:request(%s, %s, %s, %s, %s)", method, url, data, headers, options)
  local d = deferred.new()

  local timeoutTimer
  if self:getDefaultTimeout() ~= nil then
    timeoutTimer = SetTimer(tostring(os.time()), self:getDefaultTimeout(), function()
      d:reject(string.format("HTTP %s request to %s timed out", method, url))
    end)
  end
  options = options or {}
  local returnRedirect = toboolean(options.return_redirect)
  options.return_redirect = nil
  if IsEmpty(options) then
    options = nil
  end
  urlDo(method, url, data, headers, function(strError, responseCode, responseHeaders, responseBody, _, responseUrl)
    if timeoutTimer ~= nil then
      timeoutTimer:Cancel()
    end
    if
      (not returnRedirect or responseCode ~= 302)
      and (strError or IsEmpty(responseCode) or responseCode < 200 or responseCode >= 300)
    then
      d:reject(
        string.format(
          "HTTP %s request to %s failed%s%s",
          method,
          url,
          not IsEmpty(responseCode) and (" with status code " .. responseCode) or "",
          not IsEmpty(strError) and ("; " .. strError) or ""
        )
      )
    else
      d:resolve({
        url = responseUrl,
        code = responseCode,
        headers = responseHeaders,
        body = responseBody,
      })
    end
  end, nil, options)
  return d
end

function Http:get(url, headers, options)
  return self:request("GET", url, nil, headers, options)
end

function Http:post(url, data, headers, options)
  return self:request("POST", url, data, headers, options)
end

function Http:put(url, data, headers, options)
  return self:request("PUT", url, data, headers, options)
end

function Http:delete(url, headers, options)
  return self:request("DELETE", url, nil, headers, options)
end

return Http:new()
