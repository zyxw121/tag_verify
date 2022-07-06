
local lust = require 'lust'
local describe, it, expect = lust.describe, lust.it, lust.expect
local lpeg = require 'lpeg'
local p = require 'parse'

local function split(str,sep)
  sep = lpeg.P(sep)
  local elem = lpeg.C((1 - sep)^0)
  local p = lpeg.Ct(elem * (sep * elem)^0)
  return lpeg.match(p, str)
end

local function make_image(ts)
  local i = 1 
  local image = {}
  image["tags"] = {}

  for _,t in ipairs(split(ts, ",")) do
    local tag = {}
    tag["name"] = t
    image["tags"][i] = tag
    i = i+1
  end
  image["film"] = {}
  local function add_to_roll(y)
    table.insert(image["film"],y)
  end
  image["add_to_roll"] = add_to_roll
  return image

end

function tags(y) 
  return y["tags"]
end

function roll(y)
  return y["film"]
end


local function tags_set(x)
  local ts = {}
  if (type(x)=="string") then
    ts = split(x, ",")
  else
    for i,t in ipairs(tags(x)) do
    ts[i]=t.name
    end
  end
  table.sort(ts)
  return ts
end

local tprint = p.tprint
local with_name = p.with_name

local q = lpeg.P'\"'

local function quoted(text) 
  return "\""..text.."\""
end

local myt = function(t,r) 
  return lpeg.R"az"
end
local myi = function(t)
  return p.int_p 
end

--terms are single letters, ints are ints. use for testing structure
local tform = p.make_form(myt,myi, myt)(tags,roll) *-1
local form = p.form(tags,roll)


describe('tag_verify', function()
  lust.before(function()
    -- This gets run before every test.
  end)

  describe('rule parser', function() -- Can be nested
    it('int_p', function()
      local x = make_image("test,120")
      local function match(text)
        return lpeg.match(p.int_p, text)
      end
      expect(match("1")(x)).to.equal(1)
      expect(match("120")(x)).to.equal(120)
      expect(match("\"120\"")).to_not.exist()
    end)
    
    it('tag_name', function ()
      local function match(text,i)
        return lpeg.match(p.tag_name_p*-1, text)
      end
      expect(match("test")).to.exist()
      expect(match("te|st")).to_not.exist()
      expect(match("te%")).to_not.exist()
      expect(match("120")).to.exist()
--      expect(lpeg.match(p.tag_name_p, "t|")).to_not.exist()
    end)

    it('tag_path', function()
      local x = make_image("test,120,a|b")
      local function match(text,i)
        return lpeg.match(p.q_tag_path_p(tags), text)
      end
      expect(match("\"1\"")(x)).to.equal(false)
      expect(match("\"120\"")(x)).to.equal(true)
      expect(match("\"test\"")(x)).to.equal(true)
      expect(match("\"a|b\"")(x)).to.equal(true)
      expect(match("120")).to_not.exist(false)
      expect(match("\"a\"")(x)).to.equal(false)
    end)

    it('tag_list', function()
      local x = make_image("test,120,a|b")
      local function match(text,i)
        return lpeg.match("{"*p.tag_list(tags)*"}", text)
      end
      expect(match("{}")(x)).to.equal({})
      expect(match("{\"x\"}")(x)).to.equal({"x"})
      expect(match("{\"z\",\"y\",\"x\"}")(x)).to.equal({"x","y","z"})
      expect(match("{  \"a|b\" , \"a|b|c\"   }")(x)).to.equal({"a|b","a|b|c"})
    end)

    it('sets', function()
      local x = make_image("test,120,a|b,a|c,a|b|f,d|e")

      local function match_set(text)
        return lpeg.match(p.set_p(tags), text)
      end

      expect(p.prefix("a","a|b")).to.equal(true)
      expect(p.prefix("a|b","a|b")).to.equal(false)
      expect(p.prefix("a|b","a|b|c")).to.equal(true)
      expect(p.prefix("a|b|c","a|b")).to.equal(false)

      expect(p.consolidate_set(match_set("\"a|%\"")(x))).to.equal(tags_set("a|c,a|b|f"))

      expect(match_set("\"d|%\"")).to.exist()
      expect(match_set("\"%\"")).to.exist()
      expect(match_set("\"test\"")).to.exist()

      expect(match_set("\"%\"")(x)).to.equal(tags_set("a|c,a|b|f,test,120,d|e"))
      expect(match_set("\"d|%\"")(x)).to.equal(tags_set("d|e"))
      expect(match_set("\"a|%\"")(x)).to.equal(tags_set("a|c,a|b|f"))
      expect(match_set("\"a|b\"")(x)).to.equal(tags_set("a|b"))
      expect(lpeg.match(q*p.set_p(tags)*q,"\"a|b%\"")).to_not.exist()
--      expect(match_set("\"a|b%\"")(x)).to_not.exist()
      expect(match_set("\"a\"")(x)).to.equal({})
      expect(match_set("\"test\"")(x)).to.equal(tags_set("test"))
      expect(match_set("{ \"tet\" }")(x)).to.equal(tags_set("tet"))
      expect(match_set("{  \"a|b\" , \"a|b|c\"   }")(x)).to.equal({"a|b|c"})
    end)

    it('ints', function()
      local x = make_image("test,120,a|b,a|c,a|b|f,d|e")

      local function match(text)
        return lpeg.match(p.iexpr(tags), text)
      end
        expect(match("100")(x)).to.equal(100)
        expect(match("num({\"test\"})")(x)).to.equal(1)
        expect(match("num({\"tst\"})")(x)).to.equal(1)
        expect(match("num(\"test\")")(x)).to.equal(1)
        expect(match("num(\"tst\")")(x)).to.equal(0)
        expect(match("num(\"120\")")(x)).to.equal(1)
        expect(match("num(\"10\")")(x)).to.equal(0)
        expect(match("num(\"a|%\")")(x)).to.equal(2)

    end)
    it('part_tag_path', function()
      local x = make_image("test,120,a|b,a|c,d|e")
      local function match_set(text)
        return lpeg.match(p.part_tag_path_p(tags), text)
      end
      local function match_num(text)
        return lpeg.match(p.part_tag_path_p(tags) / p.higher_set_to_num, text)
      end
      expect(match_num("d|%")).to.exist()
      expect(match_num("d|%")(x)).to.equal(1)
      expect(match_num("a|%")(x)).to.equal(2)
     
      expect(match_set("%")(x)).to.equal(tags_set(x))
      expect(match_set("a|%") ).to.exist()
      expect(match_set("a|%")(x) ).to.exist()
      expect(match_set("a|%")(x) ).to.equal({"a|b","a|c"})
      expect(match_set("d|%")(x) ).to.equal({"d|e"})
      expect(match_set("e|%")(x) ).to.equal({})
      expect(match_set("test|%")(x) ).to.equal({})
      expect(match_set("test") ).to_not.exist() --part_tag requires |% at end
    end)
    
    it('syntax', function ()
      local function match(text)
        return lpeg.match(tform, text)
      end
      expect(match("a")).to.exist()
      expect(match("(a)")).to.exist()
      expect(match("not (a)")).to.exist()
      expect(match("not a")).to.exist()
      expect(match("nota")).to_not.exist()
      expect(match("a or a")).to.exist()
      expect(match("(not a) or a")).to.exist()
      expect(match("not a or b")).to_not.exist()
      expect(match("or b")).to_not.exist()
      expect(match(" 1 or b")).to_not.exist()
      expect(match("(not a) or (b or (c))")).to.exist()
      expect(match("(not(a))or(b or(c))")).to.exist()
      expect(match("(a and b)")).to.exist()
      expect(match("if(a,a and b)")).to.exist()
      expect(match("(2)")).to_not.exist()
      expect(match("if( a ,   ( a  )    and b)")).to.exist()
    end)
    it('subset', function()
      local a,b,c = 'a','b','c'
      expect(p.subset({},{})).to.equal(true)
      expect(p.subset({},{a})).to.equal(true)
      expect(p.subset({a},{a})).to.equal(true)
      expect(p.subset({a},{a,b})).to.equal(true)
      expect(p.subset({a,b,c},{a,b})).to.equal(false)
      expect(p.subset({a,c},{a,b})).to.equal(false)
      expect(p.convert_set({a,c}) <= p.convert_set({a,b})).to.equal(false)
    end)

    it('eq, leq, constants', function()
      local x = make_image("test,120,a|b,a|c,d|e")
      local function match(text)
        return lpeg.match(form, text)
      end
      expect(match("eq(true,false)")).to_not.exist()
      expect(match("eq(false)")).to_not.exist()
      expect(match("eq(0)")).to_not.exist()
      expect(match("eq(0,  )")).to_not.exist()
      expect(match("eq(0,0)")).to.exist()
      expect(match("eq( 0   , 0 )")(x)).to.equal(true)
      expect(match("eq(0,1)")(x)).to.equal(false)
      expect(match("leq(0,1)")(x)).to.equal(true)
      expect(match("leq(1,1)")(x)).to.equal(true)
      expect(match("leq(2,1)")(x)).to.equal(false)
      expect(match("true")(x)).to.equal(true)
      expect(match("false")(x)).to.equal(false)

      expect(match("eq({\"d|e\"} ,\"d|%\" )")(x)).to.equal(true)
      expect(match("eq({\"a|b\", \"a|c\"} ,\"a|%\" )")(x)).to.equal(true)
      expect(match("subset( \"a|%\", {\"a|b\", \"a|c\" , \"a|x|y\"})")(x)).to.equal(true)


    end)

    it('roll', function()
      local x = make_image("test,120,a|b,a|c,d|e")
      local y = make_image("test,120,a|b,a|c,d|f")
      x.add_to_roll(y)
      local function match(text)
        return lpeg.match(form, text)
      end
      expect(match("roll(a|%)")).to.exist()
      expect(match("roll(a|%)")(x)).to.exist()
      expect(match("roll(a|%)")(x)).to.equal(true)
      expect(match("roll(d|%)")(x)).to.equal(false)
    end)

    it('connectives', function()
      local x = make_image("test")
      local function match(text)
        return lpeg.match(form, text)
      end
      --seems unnecesary. the connectives are so transparently correct
      expect(match("true or true")(x)).to.equal(true)
    end)
 
    it('lists', function()
      local x = make_image("test")
      local function match(text)
        return lpeg.match(p.list_form(tags,roll), text)
      end
      expect(match("false")[1].name).to.equal("false")
      

      local xs = match("true,true, true  ,    true ")
      expect(#xs).to.equal(4)
      for _,r in ipairs(xs) do
        expect(r.name).to.equal("true")
        expect(r.apply_at(x)).to.equal(true)
    end
    end)


  end)
end)
