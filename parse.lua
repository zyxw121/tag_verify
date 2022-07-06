local parse = {}

local lpeg = require "lpeg"


local q =  lpeg.P'\"'
parse.q = q

local sep_p = lpeg.P("|")
local locales = lpeg.locale()

local tag_name_p = (locales["print"]-lpeg.S("|\"%{},"))^1 
parse.tag_name_p = tag_name_p

local w = lpeg.P' '^0
local w1 = lpeg.P' '^1



parse.with_name = function (p)
  local function make_x(name, f)
    local x = {}
    x.name=name
    x.apply_at = f
    return x
  end
  return lpeg.C(p) /make_x
end


parse.subset = function (a,b) --assume a,b are sorted tables
  if (#a ==0) then return true end
  if (#b == 0) then return false end
  local i,j = 1,1
  while (j<#b and i< #a and (a[i] >= b[j]) ) do
    if (a[i]==b[j]) then i = i+1 end
    j = j+1
  end
  return (a[i]<= b[j] and i==#a) --need >= for the a={} case
end

function parse.convert_set(table) 
   return setmetatable(table, {__le = parse.subset})
end

local convert_set = parse.convert_set
function parse.set_part_tag(get_tags)
  return function (t)
  return function (x)
    local tags =  get_tags(x)
    local matches = {}
    for _,tag in ipairs(tags) do
      if lpeg.match(lpeg.P(t),tag.name) then
        table.insert(matches, tag.name)
      end
    end
    table.sort(matches)
    return convert_set(matches)
  end
  end
end

function parse.higher_set_to_num(f)
return function(x)
  return #(f(x))
end
end

function inhabited(s)
  return function(x)
    return (#(s(x)) >=1)
  end
end


function parse.interpret_tag(get_tags) --returns true iff x has tag t. needs to match completely
  return function (t)
  return function (x)
    local tags =  get_tags(x)
    for _,tag in ipairs(tags) do
      if lpeg.match(lpeg.P(t)*-1,tag.name) then
        return true
      end
    end
    return false
  end
end
end

function parse.prefix(t1,t2) 
  if lpeg.match(t1*sep_p, t2) then return true
  else return false
  end
end


function parse.consolidate_set(s)
  local i = 1
  while (i< #s) do
    if parse.prefix(s[i], s[i+1]) then table.remove(s,i) 
    else i = i+1
    end
  end
  return s
end


function higher_consolidate(t)
  return function(x)
    return parse.consolidate_set(t(x))
  end
end



function parse.interpret_int(t)
  return function (x)
    return tonumber(t)
  end
end


parse.int_p = lpeg.C(lpeg.R"09"^1) / parse.interpret_int

parse.tag_path_p = function(tags)--can't have the *-1 to allow for quotes. don't use this raw.
  return lpeg.C(((tag_name_p * sep_p)^0 * tag_name_p)) /parse.interpret_tag(tags) 
end
parse.q_tag_path_p = function(tags)--can't have the *-1 to allow for quotes
  return q* parse.tag_path_p(tags) *q 
end

parse.part_tag_path_p = function(tags) 
  return lpeg.C((tag_name_p *sep_p)^0) *"%" /  parse.set_part_tag(tags) --/ higher_set_to_num
end

function tags_from_table(t)
--  print("called")
--  print(t)
--  tprint(t)
  return function (x)
    table.sort(t)
    return convert_set(t)
  end
end


parse.tag_list = function(tags)
  local tag = q*lpeg.C( (tag_name_p *sep_p)^0*tag_name_p   )*q
  return  lpeg.Ct(w*(tag *w*","*w)^0 *tag*w + w ) / tags_from_table
end

parse._set_p = function(tags)
  local tag = parse.tag_name_p
  local function f(p)
    return p * - lpeg.P(1)
  end
  return  ((tag * sep_p)^0 *tag / f / parse.set_part_tag(tags))
    +  (tag*sep_p)^0 / parse.set_part_tag(tags) *lpeg.P"%"
    + "{"*parse.tag_list(tags) *"}" 
end
parse.set_p = function(tags)
  local tag = parse.tag_name_p
  local function f(p)
    return p * - lpeg.P(1)
  end
  return  (q*( lpeg.C( (tag * sep_p)^0 *tag) / f / parse.set_part_tag(tags)) *q
    +  q*lpeg.C((tag*sep_p)^0) / parse.set_part_tag(tags) *lpeg.P"%"*q
    + "{"*parse.tag_list(tags) *"}" ) / higher_consolidate
end

--iexpr is: int  or "tag|tag|%"
parse.iexpr = function(tags)
  return parse.int_p
  + "num("*w* parse.set_p(tags) *w*")"/ parse.higher_set_to_num 
end




local function make_eq(i,j)
  return function (x)
    return (i(x) == j(x))
  end
end
local function make_leq(i,j)
  return function (x)
    return (i(x) <= j(x))
  end
end
local function make_or(f,g)
  return function (x)
    return f(x) or g(x)
  end
end
local function make_not(f)
  return function (x)
    return not f(x) 
  end
end
local function make_and(f,g)
  return function (x)
    return f(x) and g(x)
  end
end
local function make_if(f,g)
  return function (x)
    return (not f(x) or g(x))
  end
end
local function make_true ()
  return function (x)
    return true 
  end
end
local function make_false ()
  return function (x)
    return false 
  end
end


local function sorted_sets_unequal(a,b)
  if not (#a==#b) then return true end
  for i=1,#a,1 do
    if not (a[i]==b[i]) then return true end
  end
  return false
end

local function make_roll(get_roll,get_tags)
  return function (p) --p is the callback that generates the tag-set at x
    return function (x)  
    local here = p(x)
    local there = {}
    for _,image in ipairs(get_roll(x)) do
      local there = p(image) 
      if sorted_sets_unequal(here, there) 
        then return false 
      end
    end
    return true 
  end
end
end

parse.iexpr_p = function(tags)
  return parse.int_p
  + "num("*w* q*parse.set_p(tags)*q *w*")"/ parse.higher_set_to_num 
end

local myset = parse.set_p


local myint = function(tags)
  return parse.int_p
  + "num(" *lpeg.V"S" *")"
end

local myterm = function(tags,roll)
  return "eq(" *lpeg.V"CI" * ")" /make_eq
    + "leq(" *lpeg.V"CI" * ")" /make_leq
    + "eq(" *lpeg.V"CS" * ")" /make_leq
    + "subset(" *lpeg.V"CS" * ")" /make_leq --add set comparison
    + lpeg.P"true" / make_true
    + lpeg.P"false" / make_false
    --+ parse.q_tag_path_p(tags)
    + "roll(" * parse.part_tag_path_p(tags) *")" /make_roll(roll,tags)
end

parse.make_form = function(term,int,set)
  return function (tags, roll) 
  return lpeg.P{
  "F";
  F = lpeg.V"FL" * "or" *lpeg.V"FR" /make_or 
    + "not" *lpeg.V"FR" /make_not
    + lpeg.V"FL" *"and" *lpeg.V"FR"/make_and 
    + "if(" *lpeg.V"CC" *")"/make_if
    + lpeg.V"FT",
  CI = w*lpeg.V"I" *w*","*w*lpeg.V"I"*w, --pair of two ints
  CS = w*lpeg.V"S" *w*","*w*lpeg.V"S"*w, --pair of two sets 
  C = w*lpeg.V"F" *w,
  CC = w*lpeg.V"F" *w*","*w*lpeg.V"F"*w, --pair of two forms
  FT = lpeg.V"BF"+ lpeg.V"T", --bracketed formula or term
  BF = "(" * w*lpeg.V"F"*w *")", 
  FL = lpeg.V"FT" * w1 + lpeg.V"BF", 
  FR = w1 *lpeg.V"FT" + lpeg.V"BF",
  T = term(tags,roll),
  S = set(tags),
  I = int(tags)
}
end
end


parse._form = parse.make_form(myterm,myint,myset) --for internal use

parse.form = function(tags,roll) --requires the entire input to be a valid formula
  return parse.make_form(myterm, myint,myset)(tags,roll) *-1
end

parse.named_form = function(tags,roll) --requires the entire input to be a valid formula
  return parse.with_name(parse.make_form(myterm, myint,myset)(tags,roll) *-1)

end
parse.make_list = function(p)
  return lpeg.Ct(w*p*w*(w*","*w*p)^0)
end

parse.list_form = function(tags,roll)
  local form = parse.with_name(parse._form(tags,roll))
  return parse.make_list(form) 
end

function wrap_match(p) 
  return function(text)
  return lpeg.match(p, text)
end
end

parse.wrap_match = wrap_match

parse.fmatch = function(tags, roll)
    return wrap_match(parse.named_form(tags, roll))
end

parse.fsmatch = function(tags,roll)
    return wrap_match(parse.list_form(tags,roll))
end


function parse.tprint (tbl, indent)
  if not indent then indent = 0 end
  for k, v in pairs(tbl) do
    formatting = string.rep("  ", indent) .. k .. ": "
    if type(v) == "table" then
      print(formatting)
      parse.tprint(v, indent+1)
    else
      print(formatting .. tostring(v))
    end
  end
end

return parse
