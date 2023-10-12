local http = require("lib.http")
local log = require("lib.logging")
local pkce = require("lib.pkce")
local persist = require("lib.persist")

local htmlparser = require("vendor.htmlparser")
local deferred = require("vendor.deferred")

local API = {}

local OAUTH_PERSIST_KEY = "ApiOauth"
local OAUTH_BASE_URI = "https://partner-identity.myq-cloud.com"
local OAUTH_AUTHORIZE_URI = OAUTH_BASE_URI .. "/connect/authorize"
local OAUTH_TOKEN_URI = OAUTH_BASE_URI .. "/connect/token"
local OAUTH_CLIENT_ID = "ANDROID_CGI_MYQ"
local OAUTH_CLIENT_SECRET = "VUQ0RFhuS3lQV3EyNUJTdw=="
local OAUTH_REDIRECT_URI = "com.myqops://android"
local OAUTH_SCOPE = "MyQ_Residential offline_access"
local ACCOUNTS_BASE_URI = "https://accounts.myq-cloud.com"
local DEVICES_BASE_URI = "https://devices.myq-cloud.com"
local ACCOUNTS_DEVICES_BASE_URI = "https://account-devices-gdo.myq-cloud.com"
local USER_AGENT =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.5 Mobile/15E148 Safari/604.1"

local noop = function() end

function API:new()
  local properties = {
    _email = nil,
    _password = nil,
    _credentialsFingerprint = nil,
    _oauth = persist:get(OAUTH_PERSIST_KEY, {}, true),
    _statusCallback = noop,
    _authenticationFailed = false,
  }
  setmetatable(properties, self)
  self.__index = self
  return properties
end

function API:setEmail(email)
  log:trace("API:setEmail(%s)", email)
  self._email = not IsEmpty(email) and email or nil
  self:_fingerprintCredentials()
end

function API:getEmail()
  log:trace("API:getEmail()")
  return self._email
end

function API:setPassword(password)
  log:trace("API:setPassword(%s)", not IsEmpty(password) and "****" or "")
  self._password = not IsEmpty(password) and password or nil
  self:_fingerprintCredentials()
end

function API:getPassword()
  log:trace("API:getPassword()")
  return self._password
end

function API:_fingerprintCredentials()
  log:trace("API:_fingerprintCredentials()")
  -- Fingerprint the credentials so we know when the credentials changed and a token refresh is necessary
  local credentialsFingerprint, err = C4:Hash("MD5", (self._email or "") .. (self._password or ""), {
    return_encoding = "BASE64",
    data_encoding = "NONE",
  })
  self._credentialsFingerprint = credentialsFingerprint
  if not IsEmpty(err) then
    log:warn("failed to fingerprint credentials; %s", err)
  end
end

function API:setStatusCallback(callback)
  log:trace("API:setStatusCallback(%s)", callback)
  self._statusCallback = type(callback) == "function" and callback or noop
  self:_updateStatus()
end

function API:_updateStatus(status)
  log:trace("API:_updateStatus(%s)", status)
  if IsEmpty(status) then
    if not self:isConfigured() then
      status = "Not configured"
    elseif IsEmpty(self._oauth) then
      status = "Authenticating"
    else
      status = "Connected"
    end
  end
  self._statusCallback(status)
end

function API:isConfigured()
  log:trace("API:isConfigured()")
  return not IsEmpty(self._email) and not IsEmpty(self._password)
end

function API:hasAuthenticationFailure()
  log:trace("API:hasAuthenticationFailure()")
  return self._authenticationFailed
end

function API:getDevices()
  log:trace("API:getDevices()")
  return self:_getAuthorizationHeader():next(function(authorization)
    return self:_getAccounts():next(function(accounts)
      local accountsById = {}
      local accountDeviceRequests = {}
      for _, account in pairs(accounts) do
        local accountId = Select(account, "id")
        if not IsEmpty(accountId) then
          accountsById[accountId] = account
          table.insert(
            accountDeviceRequests,
            http:get(DEVICES_BASE_URI .. "/api/v5.2/Accounts/" .. accountId .. "/Devices", {
              Authorization = authorization,
              ["User-Agent"] = USER_AGENT,
            })
          )
        end
      end
      return deferred.all(accountDeviceRequests):next(function(responses)
        local garageDoors = {}
        for _, response in pairs(responses) do
          for _, device in pairs(Select(response, "body", "items") or {}) do
            if
              (Select(device, "device_family") or ""):find("garagedoor") ~= nil
              and not IsEmpty(Select(device, "account_id"))
            then
              local displayName = Select(accountsById, device.account_id, "name") or ""
              if not IsEmpty(displayName) then
                displayName = displayName .. " > "
              end
              device.displayName = displayName .. (device.name or "Garage Door")
              table.insert(garageDoors, device)
            end
          end
        end
        return garageDoors
      end)
    end)
  end)
end

function API:commandDevice(device, command)
  log:trace("API:commandDevice(%s, %s)", device, command)
  return self:_getAuthorizationHeader():next(function(authorization)
    return http:put(
      ACCOUNTS_DEVICES_BASE_URI
        .. "/api/v5.2/Accounts/"
        .. device.account_id
        .. "/door_openers/"
        .. device.serial_number
        .. "/"
        .. command,
      nil,
      {
        Authorization = authorization,
        ["User-Agent"] = USER_AGENT,
      }
    )
  end)
end

function API:_getAccounts()
  log:trace("API:_getAccounts()")
  return self:_getAuthorizationHeader():next(function(authorization)
    return http
      :get(ACCOUNTS_BASE_URI .. "/api/v6.0/accounts", {
        Authorization = authorization,
        ["User-Agent"] = USER_AGENT,
      })
      :next(function(response)
        return Select(response, "body", "accounts")
      end)
  end)
end

function API:_getAuthorizationHeader()
  return self:_getOauthCredentials():next(function(oauth)
    if not IsEmpty(Select(oauth), "token_type") and not IsEmpty(Select(oauth), "access_token") then
      return assert(oauth.token_type) .. " " .. assert(oauth.access_token)
    else
      return reject("authentication failed; invalid oauth body")
    end
  end)
end

function API:_getOauthCredentials(forceNewToken)
  log:trace("API:_getOauthCredentials(%s)", forceNewToken)
  if not self:isConfigured() then
    self:_updateStatus()
    return reject("missing email and/or password")
  end

  -- Credentials fingerprint helps us identify when an oauth token does not belong to the stored credentials
  local email, password, credentialsFingerprint = self._email, self._password, self._credentialsFingerprint
  if IsEmpty(credentialsFingerprint) then
    return reject("authentication failed; invalid credentials fingerprint")
  end

  if Select(self._oauth, "credentialsFingerprint") == credentialsFingerprint and not toboolean(forceNewToken) then
    if (Select(self._oauth, "expires_at") or 0) > os.time() then
      self:_updateStatus()
      return resolve(self._oauth)
    elseif not IsEmpty(self._oauth, "refresh_token") then
      log:debug("Refreshing myQ API OAuth token...")
      return http
        :post(
          OAUTH_TOKEN_URI,
          MakeURL(nil, {
            client_id = OAUTH_CLIENT_ID,
            client_secret = OAUTH_CLIENT_SECRET,
            grant_type = "refresh_token",
            refresh_token = self._oauth.refresh_token,
            redirect_uri = OAUTH_REDIRECT_URI,
            scope = OAUTH_SCOPE,
          }),
          {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["User-Agent"] = USER_AGENT,
          },
          { cookies_enable = true }
        )
        :next(function(response)
          self._oauth = response.body
          -- Calculate the expiry time minus some buffer to allow for refresh
          self._oauth.expires_at = os.time() + self._oauth.expires_in - 180
          self._oauth.credentialsFingerprint = credentialsFingerprint
          persist:set(OAUTH_PERSIST_KEY, self._oauth, true)
          self:_updateStatus()
          return self._oauth
        end, function(error)
          log:warn("authentication token refresh failed; %s\ngenerating a new token using stored credentials", error)
          return self:_getOauthCredentials(true)
        end)
    end
  end
  log:debug("Minting a new myQ API OAuth token...")
  self._oauth = {}
  persist:delete(OAUTH_PERSIST_KEY)
  self:_updateStatus()

  C4:urlClearCookies()

  local verifier, challenge = pkce:challenge()
  return http
    :get(
      MakeURL(OAUTH_AUTHORIZE_URI, {
        client_id = OAUTH_CLIENT_ID,
        response_type = "code",
        redirect_uri = OAUTH_REDIRECT_URI,
        scope = OAUTH_SCOPE,
        code_challenge = challenge,
        code_challenge_method = "S256",
      }),
      {
        ["User-Agent"] = USER_AGENT,
      },
      { cookies_enable = true }
    )
    :next(function(response)
      local parsedBody = htmlparser.parse(response.body)
      local endpoint = Select(parsedBody:select("form[action]"), 1, "attributes", "action")
      if IsEmpty(endpoint) then
        return reject("authentication failed; login action could not be found")
      end
      local verificationToken =
        Select(parsedBody:select("input[name='__RequestVerificationToken']"), 1, "attributes", "value")
      if IsEmpty(verificationToken) then
        return reject("authentication failed; login verification token could not be found")
      end

      local d = deferred.new()
      C4:url()
        :SetOptions({ cookies_enable = true })
        :OnDone(function(_, loginResponses)
          loginResponses = IsList(loginResponses) and loginResponses or {}
          for _, loginResponse in pairs(loginResponses) do
            local responseCode = tointeger(Select(loginResponse, "code")) or 0
            local tHeaders = Select(loginResponse, "headers") or {}
            TableMap(tHeaders, function(value, key)
              tHeaders[key:lower()] = value
            end)
            if
              responseCode == 302
              and not IsEmpty(Select(tHeaders, "set-cookie"))
              and not IsEmpty(Select(tHeaders, "location"))
            then
              d:resolve(tHeaders.location)
            end
          end
          log:ultra("authentication failure responses: %s", loginResponses)
          d:reject("authentication failed; incorrect email and password")
        end)
        :Post(
          OAUTH_BASE_URI .. endpoint,
          MakeURL(nil, {
            Email = assert(email),
            Password = assert(password),
            __RequestVerificationToken = verificationToken,
            brand = "myq",
            UnifiedFlowRequested = "True",
          }),
          {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["User-Agent"] = USER_AGENT,
          }
        )
      return d
    end)
    :next(function(endpoint)
      local d = deferred.new()
      local url = OAUTH_BASE_URI .. assert(endpoint)
      C4:url()
        :SetOptions({ cookies_enable = true })
        :OnDone(function(_, responses)
          responses = IsList(responses) and responses or {}
          local responseCode = tointeger(Select(responses, #responses, "code")) or 0
          local tHeaders = Select(responses, #responses, "headers") or {}
          TableMap(tHeaders, function(value, key)
            tHeaders[key:lower()] = value
          end)
          local code = (Select(tHeaders, "location") or ""):match("code=([A-Z0-9]+)")
          if responseCode == 302 and not IsEmpty(code) then
            d:resolve(code)
          else
            d:reject("authentication failed; failed to intercept redirect code")
          end
        end)
        :Get(url, {
          ["User-Agent"] = USER_AGENT,
        })
      return d
    end)
    :next(function(code)
      return http
        :post(
          OAUTH_TOKEN_URI,
          MakeURL(nil, {
            client_id = OAUTH_CLIENT_ID,
            client_secret = OAUTH_CLIENT_SECRET,
            code = code,
            code_verifier = verifier,
            grant_type = "authorization_code",
            redirect_uri = OAUTH_REDIRECT_URI,
            scope = OAUTH_SCOPE,
          }),
          {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["User-Agent"] = USER_AGENT,
          },
          { cookies_enable = true }
        )
        :next(function(response)
          self._oauth = response.body
          self._oauth.expires_at = os.time() + self._oauth.expires_in - 180
          self._oauth.credentialsFingerprint = credentialsFingerprint
          persist:set(OAUTH_PERSIST_KEY, self._oauth, true)
          self:_updateStatus()
          return self._oauth
        end)
    end)
    :next(function(response)
      self._authenticationFailed = false
      return response
    end, function(error)
      log:error("Authentication failed; %s", error)
      self._authenticationFailed = true
      self:_updateStatus("Authentication failed; check logs for more details")
      return reject(error)
    end)
end

return API:new()
