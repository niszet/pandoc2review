-- Re:VIEW Writer for Pandoc
-- Copyright 2020 Kenshi Muto
-- Usage: pandoc -f markdown-auto_identifiers -t review.lua --lua-filter nestedlist.lua file.md > file.re

-- config
local config = {
  use_header_id = "true",
  use_hr = "true",
  use_table_align = "true",

  bold = "b",
  italic = "i",
  code = "tt",
  strike = "u", -- XXX: Re:VIEW doesn't support <strike>
  lineblock = "source", --- XXX: Re:VIEW doesn't provide poem style by default
}

-- counter
local table_num = 0
local list_num = 0
local fig_num = 0
local note_num = 0
local footnotes = {}

-- internal
local metadata = nil
local stringify = (require "pandoc.utils").stringify

local function try_catch(what)
  -- ref: http://bushimichi.blogspot.com/2016/11/lua-try-catch.html
  local status, result = pcall(what.try)
  if not status then
    what.catch(result)
  end
  return result
end

local function log(s)
  io.stderr:write(s)
end

local function surround_inline(s)
  if (string.match(s, "{") or string.match(s, "}")) then
    if (string.match(s, "%$")) then -- use % for regexp escape
      if (string.match(s, "|")) then
        -- give up. escape } by \}
        return "{" .. string.gsub(s, "}", "\\}") .. "}"
      else
        -- surround by ||
        return "|" .. s .. "|"
      end
    else
      -- surround by $$
        return "$" .. s .. "$"
    end
  end
  return "{" .. s .. "}"
end

local function html_align(align)
  if align == "AlignLeft" then
    return ""
  elseif align == "AlignRight" then
    return "right"
  elseif align == "AlignCenter" then
    return "center"
  else
    return ""
  end
end

function Blocksep()
  return "\n\n"
end

function Doc(body, metadata, variables)
  local buffer = {}
  local function add(s)
    table.insert(buffer, s)
  end
  add(body)
  if (#footnotes > 0) then
    add("\n" .. table.concat(footnotes, "\n"))
  end
  return table.concat(buffer, "\n")
end

function Str(s)
  return s
end

function Space()
  return " "
end

function LineBreak()
  return "\n"
end

function SoftBreak(s)
  return ""
end

function Plain(s)
  return s
end

function Para(s)
  return string.gsub(s, "\n", "")
end

local function attr_val(attr, key)
  local attr_table = {}
  for k, v in pairs(attr) do
    if (k == key and v and v ~= "") then
      return v
    end
  end
  return ""
end

function Header(level, s, attr)
  headmark = ""
  for i = 1, level do
    headmark = headmark .. "="
  end

  cls = attr_val(attr, "class")
  if (cls ~= "") then
    if (cls == "unnumbered") then
      cls = "nonum"
    end
    headmark = headmark .. "[" .. cls .. "]"
  end

  if (config.use_header_id and attr.id ~= "" and attr.id ~= s) then
    headmark = headmark .. "{" .. attr.id .. "}"
  end

  return headmark .. " " .. s
end

function HorizontalRule()
  if (config.use_hr) then
    return "//hr"
  else
    return ""
  end
end

function BulletList(items)
  local buffer = {}
  for _, item in pairs(items) do
    if (item == "//beginchild") or (item == "//endchild") then
      table.insert(buffer, item)
    else
      table.insert(buffer, " * " .. item)
    end
  end
  return table.concat(buffer, "\n")
end

function OrderedList(items, start)
  local buffer = {}
  local n = start
  for _, item in pairs(items) do
    if (item == "//beginchild") or (item == "//endchild") then
      table.insert(buffer, item)
    else
      table.insert(buffer, " " .. n .. ". " .. item)
      n = n + 1
    end
  end
  return table.concat(buffer, "\n")
end

function DefinitionList(items)
  local buffer = {}
  for _, item in pairs(items) do
    for k, v in pairs(item) do
      if (item == "//beginchild") or (item == "//endchild") then
        table.insert(buffer, item)
      else
        table.insert(buffer, " : " .. k .. "\n\t" .. table.concat(v, "\n"))
      end
    end
  end
  return table.concat(buffer, "\n") .. "\n"
end

function BlockQuote(s)
  return "//quote{\n" .. s .. "\n//}"
end

function CodeBlock(s, attr)
  tag = "//"

  caption = attr_val(attr, "caption") -- ```{caption=CAPTION}
  if (caption ~= "") then
    list_num = list_num + 1
    tag = tag .. "list[list" .. list_num .. "][" .. caption .. "]"
  else
    tag = tag .. "emlist"
  end

  cls = attr_val(attr, "class")
  if (cls ~= "") then
    tag = tag .. "[][" .. cls .. "]"
  end
  return tag .. "{\n" .. s .. "\n//}"
end

function LineBlock(s)
  -- | block. FIXME://source代替でよいか
  return "//" .. config.lineblock .. "{\n" .. table.concat(s, "\n") .. "\n//}"
end

function Link(s, src, tit)
  -- FIXME: titを使う可能性はあるか？
  if (src == s) then
    return "@<href>" .. surround_inline(src)
  else
    return "@<href>" .. surround_inline(src .. "," .. s)
  end
end

function Code(s, attr)
  -- ignore attr
  return "@<" .. config.code .. ">" .. surround_inline(s)
end

function Emph(s)
  return "@<" .. config.italic .. ">" .. surround_inline(s)
end

function Strong(s)
  -- FIXME: ___ とすると Strong(Emph)、つまり @<b>$@<i>{ITBOLD}$ が産まれてしまう…
  return "@<" .. config.bold .. ">" .. surround_inline(s)
end

function Strikeout(s)
  return "@<" .. config.strike .. ">" .. surround_inline(s)
end

function Subscript(s)
  return "@<sub>" .. surround_inline(s)
end

function Superscript(s)
  return "@<sup>" .. surround_inline(s)
end

function InlineMath(s)
  return "@<m>" .. surround_inline(s)
end

function DisplayMath(s)
  return "//texequation{\n" .. s .. "\n//}"
end

function Table(caption, aligns, widths, headers, rows)
  local buffer = {}
  local function add(s)
    table.insert(buffer, s)
  end
  if caption ~= "" then
    table_num = table_num + 1
    add("//table[table" .. table_num .. "][" .. caption .. "]{")
  else
    add("//table{")
  end
  local tmp = {}
  for i, h in pairs(headers) do
    align = html_align(aligns[i])
    if (config.use_table_align and align ~= "") then
      h = "@<dtp>{table align=" .. align .. "}" .. h
    end
    table.insert(tmp, h)
  end
  add(table.concat(tmp, "\t"))
  add("--------------")
  for _, row in pairs(rows) do
    tmp = {}
      for i, c in pairs(row) do
      align = html_align(aligns[i])
      if (config.use_table_align and align ~= "") then
        c = "@<dtp>{table align=" .. align .. "}" .. c
      end
      table.insert(tmp, c)
    end
    add(table.concat(tmp, "\t"))
  end
  add("//}")

  return table.concat(buffer, "\n")
end

function CaptionedImage(s, src, tit)
  local id = string.gsub(s, "%.%w+$", "")
  id = string.gsub(id, "images/", "")
  local buffer = {}
  if (tit ~= "") then
    table.insert(buffer, "//image[" .. id .. "][" .. tit .. "]{")
  else
    table.insert(buffer, "//indepimage[" .. id .. "]{")
  end
  if (src ~= "" and src ~= "fig:") then
    src = string.gsub(src, "fig:", "")
    table.insert(buffer, src)
  end
  table.insert(buffer, "//}")
  return table.concat(buffer, "\n")
end

function Note(s)
  note_num = note_num + 1
  table.insert(footnotes, "//footnote[fn" .. note_num .. "][" .. s .. "]")
  return "@<fn>{fn" .. note_num .. "}"
end

function Cite(s, cs)
  -- use @ as is.
  return s
end

function Div(s, attr)
  return "//" .. attr_val(attr, "class") .. "{\n" .. s .. "\n//}"
end

function Span(s, attr)
  -- FIXME: attrを捨ててよいか
  return s
end

function RawInline(format, text)
  return text
end

function RawBlock(format, text)
  return text
end

try_catch {
  try = function()
    metadata = PANDOC_DOCUMENT.meta
  end,
  catch = function(error)
    log("Due to your pandoc version is too old, config.yml loader is disabled.\n")
  end
}

if (metadata) then
  -- Load config from YAML
  if (metadata.pandoc2review and metadata.pandoc2review.use_header_id) then
    if (stringify(metadata.pandoc2review.use_header_id) == "false") then
      config.use_header_id = nil
    end
  end

  if (metadata.pandoc2review and metadata.pandoc2review.use_hr) then
    if (stringify(metadata.pandoc2review.use_hr) == "false") then
      config.use_hr = nil
    end
  end

  if (metadata.pandoc2review and metadata.pandoc2review.use_table_align) then
    if (stringify(metadata.pandoc2review.use_table_align) == "false") then
      config.use_table_align = nil
    end
  end

  if (metadata.pandoc2review and metadata.pandoc2review.bold) then
    config.bold = stringify(metadata.pandoc2review.bold)
  end

  if (metadata.pandoc2review and metadata.pandoc2review.italic) then
    config.italic = stringify(metadata.pandoc2review.italic)
  end

  if (metadata.pandoc2review and metadata.pandoc2review.code) then
    config.code = stringify(metadata.pandoc2review.code)
  end

  if (metadata.pandoc2review and metadata.pandoc2review.strike) then
    config.strike = stringify(metadata.pandoc2review.strike)
  end

  if (metadata.pandoc2review and metadata.pandoc2review.lineblock) then
    config.lineblock = stringify(metadata.pandoc2review.lineblock)
  end
end

local meta = {}
meta.__index =
  function(_, key)
    log(string.format("WARNING: Undefined function '%s'\n", key))
    return function() return "" end
  end

setmetatable(_G, meta)
