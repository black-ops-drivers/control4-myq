local log = require("lib.logging")

local err = function(f, ...)
  if debug then
    local line = debug.getinfo(2).currentline
    f = f:gsub("#LINE#", tostring(line))
  end
  log:error(f, ...)
end
local dbg = function(f, ...)
  if debug then
    local line = debug.getinfo(2).currentline
    f = f:gsub("#LINE#", tostring(line))
  end
  log:ultra(f, ...)
end

local ElementNode = require("vendor.htmlparser.ElementNode")
local voidelements = require("vendor.htmlparser.voidelements")

local HtmlParser = {}
local function parse(text, limit, opts)
  opts = type(opts) == "table" and not IsEmpty(opts) and opts or {}
  text = tostring(text)
  limit = tointeger(limit) or 1000
  local tpl = false

  if not opts.keep_comments then -- Strip (or not) comments
    text = text:gsub("<!%-%-.-%-%->", "") -- Many chances commented code will have syntax errors, that'll lead to parser failures
  end

  local tpr = {}

  if not opts.keep_danger_placeholders then -- little speedup by cost of potential parsing breakages
    -- search unused "invalid" bytes
    local busy, i = {}, 0
    repeat
      local cc = string.char(i)
      if not (text:match(cc)) then
        if not tpr["<"] or not tpr[">"] then
          if not busy[i] then
            if not tpr["<"] then
              tpr["<"] = cc
            elseif not tpr[">"] then
              tpr[">"] = cc
            end
            busy[i] = true
            dbg("c:{%s}||cc:{%d}||tpr[c]:{%s}", c, cc:byte(), tpr[c])
            dbg("busy[i]:{%s},i:{%d}", busy[i], i)
            dbg("[FindPH]:#LINE# Success! || i=%d", i)
          else
            dbg("[FindPH]:#LINE# Busy! || i=%d", i)
          end
          dbg("c:{%s}||cc:{%d}||tpr[c]:{%s}", c, cc:byte(), tpr[c])
          dbg("%s", busy[i])
        else
          dbg("[FindPH]:#LINE# Done!", i)
          break
        end
      else
        dbg("[FindPH]:#LINE# Text contains this byte! || i=%d", i)
      end
      local skip = 1
      if i == 31 then
        skip = 96 -- ASCII
      end
      i = i + skip
    until i == 255
    i = nil

    if not tpr["<"] or not tpr[">"] then
      err(
        "Impossible to find at least two unused byte codes in this HTML-code. We need it to escape bracket-contained placeholders inside tags."
      )
      err(
        "Consider enabling 'keep_danger_placeholders' option (to silence this error, if parser wasn't failed with current HTML-code) or manually replace few random bytes, to free up the codes."
      )
    else
      dbg("[FindPH]:#LINE# Found! || '<'=%d, '>'=%d", tpr["<"]:byte(), tpr[">"]:byte())
    end

    --	dbg("tpr[>] || tpr[] || #busy%d")

    local function g(id, ...)
      local arg = { ... }
      local orig = arg[id]
      arg[id] = arg[id]:gsub("(.)", tpr)
      if arg[id] ~= orig then
        tpl = true
        dbg("[g]:#LINE# orig: %s", orig)
        dbg("[g]:#LINE# replaced: %s", arg[id])
      end
      dbg(
        "[g]:#LINE# called, id: %s, arg[id]: %s, args { " .. (("{%s}, "):rep(#arg):gsub(", $", "")) .. " }",
        id,
        arg[id],
        ...
      )
      dbg("[g]:#LINE# concat(arg): %s", table.concat(arg))
      return table.concat(arg)
    end

    -- tpl-placeholders and attributes
    text = text
      :gsub("(=[%s]-)(%b'')", function(...)
        return g(2, ...)
      end)
      :gsub('(=[%s]-)(%b"")', function(...)
        return g(2, ...)
      end) -- Escape "<"/">" inside attr.values (see issue #50)
      :gsub(
        "(<" -- Match "<",
          .. (opts.tpl_skip_pattern or "[^!]") -- with exclusion pattern (for example, to ignore comments, which aren't template placeholders, but can legally contain "<"/">" inside.
          .. ")([^>]+)" -- If matched, we want to escape '<'s if we meet them inside tag
          .. "(>)",
        function(...)
          return g(2, ...)
        end
      )
      :gsub(
        "("
          .. (tpr["<"] or "__FAILED__") -- Here we search for "<", we escaped in previous gsub (and don't break things if we have no escaping replacement)
          .. ")("
          .. (opts.tpl_marker_pattern or "[^%w%s]") -- Capture templating symbol
          .. ")([%g%s]-)" -- match placeholder's content
          .. "(%2)(>)" -- placeholder's tail
          .. "([^>]*>)", -- remainings
        function(...)
          return g(5, ...)
        end
      )
  end

  local index = 0
  local root = ElementNode:new(index, tostring(text))
  local node, descend, tpos, opentags = root, true, 1, {}

  while true do
    if index == limit then
      err(
        "Main loop reached loop limit (%d). Consider either increasing it or checking HTML-code for syntax errors",
        limit
      )
      break
    end

    local openstart, name
    openstart, tpos, name = root._text:find(
      "<" -- an uncaptured starting "<"
        .. "([%w-]+)" -- name = the first word, directly following the "<"
        .. "[^>]*>", -- include, but not capture everything up to the next ">"
      tpos
    )
    dbg("[MainLoop]:#LINE# openstart=%s || tpos=%s || name=%s", openstart, tpos, name)

    if not name then
      break
    end

    index = index + 1
    local tag = ElementNode:new(index, tostring(name), (node or {}), descend, openstart, tpos)
    node = tag
    local tagloop
    local tagst, apos = tag:gettext(), 1

    while true do
      dbg("[TagLoop]:#LINE# tag.name=%s, tagloop=%s", tag.name, tagloop)
      if tagloop == limit then
        err(
          "Tag parsing loop reached loop limit (%d). Consider either increasing it or checking HTML-code for syntax errors",
          limit
        )
        break
      end

      local start, k, eq, quote, v, zsp
      start, apos, k, zsp, eq, zsp, quote = tagst:find(
        "%s+" -- some uncaptured space
          .. "([^%s=/>]+)" -- k = an unspaced string up to an optional "=" or the "/" or ">"
          .. "([%s]-)" -- zero or more spaces
          .. "(=?)" -- eq = the optional; "=", else ""
          .. "([%s]-)" -- zero or more spaces
          .. [=[(['"]?)]=], -- quote = an optional "'" or '"' following the "=", or ""
        apos
      )
      dbg(
        "[TagLoop]:#LINE# start=%s || apos=%s || k=%s || zsp='%s' || eq='%s', quote=[%s]",
        start,
        apos,
        k,
        zsp,
        eq,
        quote
      )

      if not k or k == "/>" or k == ">" then
        break
      end

      if eq == "=" then
        local pattern = "=([^%s>]*)"
        if quote ~= "" then
          pattern = quote .. "([^" .. quote .. "]*)" .. quote
        end
        start, apos, v = tagst:find(pattern, apos)
        dbg("[TagLoop]:#LINE# start=%s || apos=%s || v=%s || pattern=%s", start, apos, v, pattern)
      end

      v = v or ""
      if tpl then
        for rk, rv in pairs(tpr) do
          v = v:gsub(rv, rk)
          dbg("[TagLoop]:#LINE# rv=%s || rk=%s", rv, rk)
        end
      end

      dbg("[TagLoop]:#LINE# k=%s || v=%s", k, v)
      tag:addattribute(k, v)
      tagloop = (tagloop or 0) + 1
    end

    if voidelements[tag.name:lower()] then
      descend = false
      tag:close()
    else
      descend = true
      opentags[tag.name] = opentags[tag.name] or {}
      table.insert(opentags[tag.name], tag)
    end

    local closeend = tpos
    local closingloop
    while true do
      -- Can't remember why did I add that, so comment it for now (and not remove), in case it will be needed again
      -- (although, it causes #59 and #60, so it will anyway be needed to rework)
      -- if voidelements[tag.name:lower()] then break end -- already closed
      if closingloop == limit then
        err(
          "Tag closing loop reached loop limit (%d). Consider either increasing it or checking HTML-code for syntax errors",
          limit
        )
        break
      end

      local closestart, closing, closename
      closestart, closeend, closing, closename = root._text:find("[^<]*<(/?)([%w-]+)", closeend)
      dbg(
        "[TagCloseLoop]:#LINE# closestart=%s || closeend=%s || closing=%s || closename=%s",
        closestart,
        closeend,
        closing,
        closename
      )

      if not closing or closing == "" then
        break
      end

      tag = table.remove(opentags[closename] or {}) or tag -- kludges for the cases of closing void or non-opened tags
      closestart = root._text:find("<", closestart)
      dbg("[TagCloseLoop]:#LINE# closestart=%s", closestart)
      tag:close(closestart, closeend + 1)
      node = tag.parent
      descend = true
      closingloop = (closingloop or 0) + 1
    end
  end
  if tpl then
    dbg("tpl")
    for k, v in pairs(tpr) do
      root._text = root._text:gsub(v, k)
    end
  end
  return root
end
HtmlParser.parse = parse
return HtmlParser
