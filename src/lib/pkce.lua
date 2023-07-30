local log = require("lib.logging")

local PKCE = {}

function PKCE:new()
  local properties = {}
  setmetatable(properties, self)
  self.__index = self
  return properties
end

function PKCE:_generateVerifier(length)
  log:trace("PKCE:_generateVerifier(%s)", length)
  return GetRandomString(length, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
end

---
--- Generate a PKCE challenge from a verifier.
---
function PKCE:_generateChallenge(verifier)
  log:trace("PKCE:_generateChallenge(%s)", verifier)
  local challenge = C4:Hash("SHA256", verifier, {
    data_encoding = "NONE",
    return_encoding = "BASE64",
  })
  challenge = string.gsub(challenge, "/", "_")
  challenge = string.gsub(challenge, "%+", "-")
  challenge = string.gsub(challenge, "=+$", "")
  return challenge
end

---
--- Generate a PKCE challenge pair.
---
function PKCE:challenge(length)
  log:trace("PKCE:challenge(%s)", length)
  length = tointeger(length)
  if length == nil then
    length = 43
  end
  length = InRange(length, 43, 128)

  local verifier = self:_generateVerifier(length)
  local challenge = self:_generateChallenge(verifier)

  return verifier, challenge
end

---
--- Verify that the given verifier produces the expected challenge.
---
function PKCE:verify(verifier, expectedChallenge)
  log:trace("PKCE:verify(%s, %s)", verifier, expectedChallenge)
  assert(type(verifier) == "string" and not IsEmpty(verifier), "argument 'verifier' must be a non-empty string")
  assert(
    type(expectedChallenge) == "string" and not IsEmpty(expectedChallenge),
    "argument 'expectedChallenge' must be a non-empty string"
  )
  return self:_generateChallenge(verifier) == expectedChallenge
end

return PKCE:new()
