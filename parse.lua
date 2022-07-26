local parse = {}

local lpeg = require "lpeg"

function parse.tprint (tbl, indent)
  if not indent then indent = 0 end
  local empty = true
  for k, v in pairs(tbl) do
    empty = false
    formatting = string.rep("  ", indent) .. k .. ": "
    if type(v) == "table" then
      print(formatting)
      parse.tprint(v, indent+1)
    else
      print(formatting .. tostring(v))
    end
  end
  if (empty) then print("empty table") end
end

local q =  lpeg.P'\"'
parse.q = q

local sep_p = lpeg.P("|")
local locales = lpeg.locale()

local tag_name_p = (locales["print"]-lpeg.S("|\"%{},"))^1 
parse.tag_name_p = tag_name_p

local w = lpeg.P' '^0
local w1 = lpeg.P' '^1




parse.with_name = function(t)
  return function (p)
  local function make_x(name, f)
    local x = {}
    x.name=name
    x.apply_at = f
    x.sort = t
    return x
  end
  return lpeg.C(p) /make_x
end
end


parse.subset = function (a,b) --assume a,b are sorted tables
  if (#a ==0) then return true end
  if (#b == 0) then return false end
  local i,j = 1,1
  --loop invariant: a[1..i) is a subset of b[1..j)
  --terminates when one array is fully traversed.
  --if it is a, then every element in a has been found in b
  while (j<=#b and i<= #a and (a[i] >= b[j]) ) do
    if (a[i]==b[j]) then i = i+1 end
    j = j+1
  end
  return (i==(#a+1))
end

function parse.convert_set(table) 
   return setmetatable(table, {__le = parse.subset})
end

local convert_set = parse.convert_set


function parse.tag_set(get_tags)
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


parse.inhabited = inhabited

function parse.prefix(t1,t2) 
  if lpeg.match(t1, t2) then return true
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

function quoted(p)
  return q*p*q
end


parse.int_p = lpeg.C(lpeg.R"09"^1) / parse.interpret_int

parse.tag_path_p =  lpeg.C((tag_name_p * sep_p)^0 * tag_name_p)


parse.q_tag_path_p = quoted(parse.tag_path_p)

parse.part_tag_path_p = lpeg.C((tag_name_p *sep_p)^0) *"%" 

function tags_from_table(t)
--  print("called")
--  print(t)
--  tprint(t)
  return function (x)
    table.sort(t)
    return convert_set(t)
  end
end

parse.make_list = function(p, s) --returns a non-empty list of ps
  s = s or ','
  return lpeg.Ct(w*p*w*(w*s*w*p*w)^0)
end

parse.make_list0 = function(p,s) --returns a potentially empty list of ps
  s = s or ','
  return lpeg.Ct(w*p*w*(w*s*w*p*w)^0 + w)
end

local q_tag = quoted(lpeg.C( (tag_name_p *sep_p)^0*tag_name_p))
parse.q_tag_list = parse.make_list0(q_tag) / tags_from_table
  

function parse.term(p)
  return p * - lpeg.P(1)
end

parse.set_p = function(tags)
  return  (quoted(parse.tag_path_p / parse.term / parse.tag_set(tags))
    +  quoted(parse.part_tag_path_p / parse.tag_set(tags))
    + "{"*parse.q_tag_list *"}" ) /higher_consolidate
end



parse.set_p1 = function(tags)
  local tag = parse.tag_name_p
  local function f(p)
    return p * - lpeg.P(1)
  end
  return  (q*( lpeg.C( (tag * sep_p)^0 *tag) / f / parse.tag_set(tags)) *q
    +  q*lpeg.C((tag*sep_p)^0) / parse.tag_set(tags) *lpeg.P"%"*q
    + "{"*parse.q_tag_list(tags) *"}" ) / higher_consolidate
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
local function make_xor(f,g)
  return function (x)
    return (f(x) or g(x)) and ((not g(x)) or (not f(x)))
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

parse.union = function(s,t)
    for _,y in ipairs(t) do
      table.insert(s,y)
    end
    table.sort(s)
    return parse.consolidate_set(s)
end

local function make_union(s,t)
--  print("union of:")
--  tprint(s(x))
--  tprint(t(x))
  return function (x)
    return parse.union(s(x),t(x))
  end
end

parse.make_union = make_union

function parse.intersect(s,t)
    local i,j = 1,1
    while (i <=#s and j <= #t) do
      local a,b = s[i], t[j]
      if (a==b) then 
        i = i+1
        j = j+1
      end
      if(a < b) then
        table.remove(s,i)       
      else
        table.remove(t,j)
      end
    end
    if (i > #s) then
      return parse.consolidate_set(s)
    else
      return parse.consolidate_set(t)
    end
end

local function make_intersection(s,t)
  return function (x)
    return parse.intersect(s(x),t(x))
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

local myset1 = parse.set_p



local make_set = function(set)
  return function(tags)
  return lpeg.P{
    "S";
  S = "union("* w*lpeg.V"S" *w*","*w*lpeg.V"S"*w*")" / make_union
    + lpeg.V"SL" * "setor" *lpeg.V"SR" /make_union
    + lpeg.V"SL" * "setand" *lpeg.V"SR" /make_intersection
    + lpeg.V"ST"
    + "set(" *lpeg.V"S" *")",
  SL = lpeg.V"ST" * w1 + lpeg.V"BS", 
  CS = w*lpeg.V"S" *w*","*w*lpeg.V"S"*w, --pair of two sets 
  SR = w1 *lpeg.V"ST" + lpeg.V"BS",
  ST = lpeg.V"BS" + lpeg.V"PS", --bracketed set
  BS = "(" * w*lpeg.V"S"*w *")", 
  PS= set(tags),
  }
end
end

local myset = make_set(myset1)
parse.myset = myset

local myint1 = function(tags)
  return parse.int_p
  + "num(" * myset(tags) / parse.higher_set_to_num *")"
end

local myint = function(tags)
  return parse.int_p
  + "num(" *lpeg.V"S" / parse.higher_set_to_num *")"
end

local myterm = function(tags,roll)
  return "eq(" *lpeg.V"CI" * ")" /make_eq
    + "leq(" *lpeg.V"CI" * ")" /make_leq
    + "eq(" *lpeg.V"CS" * ")" /make_leq
    + "subset(" *lpeg.V"CS" * ")" /make_leq --add set comparison
    + lpeg.P"true" / make_true
    + lpeg.P"false" / make_false
    + parse.set_p(tags) / inhabited
    + "roll(" * parse.set_p(tags) *")" /make_roll(roll,tags)
end

local function myf(s,t)
  print("s "..s)
  print("t "..t)
end


parse.make_form = function(term,int,set)
  return function (tags, roll) 
  return lpeg.P{
  "F";
  F = lpeg.V"FL" * "or" *lpeg.V"FR" /make_or 
    + "not" *lpeg.V"FR" /make_not
    + lpeg.V"FL" *"and" *lpeg.V"FR"/make_and 
    + lpeg.V"FL" *"xor" *lpeg.V"FR"/make_xor 
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
  S = set(tags),
  T = term(tags,roll),
  I = int(tags)
}
end
end



parse._form = parse.make_form(myterm,myint,myset) --for internal use

parse.form = function(tags,roll) --requires the entire input to be a valid formula
  return parse.make_form(myterm, myint,myset)(tags,roll) *-1
end

parse.named_form = function(tags,roll) --requires the entire input to be a valid formula
  return parse.with_name("form")(parse.make_form(myterm, myint,myset)(tags,roll) *-1)

end

parse.expression = function(tags,roll)
  local f =   parse.with_name("form")(parse._form(tags,roll)) 
  local s = w*"set"*w*":"*w* parse.with_name("set")(myset1(tags)) 
  local i = w*"int"*w*":"*w* parse.with_name("int")(myint1(tags)) 
  return (s+i+f)
end
parse._expression = function(tags,roll)
  local f =   parse.with_name("form")(parse._form(tags,roll)) 
  local s = w*"set"*w*":"*w* parse.with_name("set")(myset1(tags)) 
  local i = w*"int"*w*":"*w* parse.with_name("int")(myint1(tags)) 
  return (s+i+f) *-1
end
parse.expression1 = function(tags,roll)
  local f = 'form('* parse.with_name("form")(parse._form(tags,roll)) *")"
  local s = 'set(' *parse.with_name("set")(myset1(tags)) *')'
  local i = 'int('*parse.with_name("int")(myint1(tags)) *')'
  return s+i+f
end

parse.list_expr = function(tags,roll)
  local expr = parse.expression(tags, roll)
  return parse.make_list(expr,";")
end

parse.list_form = function(tags,roll)
  local form = parse.with_name("form")(parse._form(tags,roll))
  return parse.make_list(form,";") 
end

function wrap_match(p) 
  return function(text)
  return lpeg.match(p, text)
end
end

parse.wrap_match = wrap_match

parse.ematch = function(tags,roll)
 return wrap_match(parse._expression(tags,roll)) 
end

parse.fmatch = function(tags, roll)
    return wrap_match(parse.named_form(tags, roll))
end

parse.esmatch = function(tags,roll)
    return wrap_match(parse.list_expr(tags,roll))
end
parse.fsmatch = function(tags,roll)
    return wrap_match(parse.list_form(tags,roll))
end



return parse
