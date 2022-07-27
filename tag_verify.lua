--[[
   ]]

--[[
Enable tag system constraints and verification 
]]

local dt = require "darktable"
local ps = require "tag_verify/parse"

local verbose = false
local editing = false
local editing_n = 0

local rules = {}

local function expr_to_pref_string(r)
  if (r.sort == "form") then 
    return r.name
  else
    return r.sort ..": "..r.name
  end
end

local function tag_string(image)
  tags = image.get_tags(image)
  local ts = ""
  for _,t in ipairs(tags) do
    ts = ts .. t.name ..", "
  end
  table.sort(ts)
  return ts
end

local function get_roll(image)
  local n =#image.film
  roll = {}
  for i = 1,n,1 do
    roll[i] = image.film[i]
  end
  return roll
end

local function get_tags(image)
  return image.get_tags(image)
end

 local get_roll = function(image)
    local n =#image.film
    roll = {}
    for i = 1,n,1 do
      roll[i] = image.film[i]
    end
    return roll
  end

local function make_memo(memo)
   local nin_memo = function(image,f)
    return (memo[f] == nil or memo[f][image.film.path]==nil) --can be null
  end
  local add_to_memo = function(image,f, val)
    if (memo[f]==nil) then memo[f] = {} end
    memo[f][image.film.path] = val
  end
  local get_memo = function(image, f)
    if (memo[f] == nil) then return nil end
    return memo[f][image.film.path]
  end
  return {nin_memo = nin_memo, add_to_memo = add_to_memo, get_memo = get_memo}
end

local ematch = ps.ematch(get_tags, get_roll)
local esmatch = ps.esmatch(get_tags, get_roll)

-- return data structure for script_manager
local script_data = {}
script_data.destroy = nil -- function to destory the script
script_data.destroy_method = nil -- set to hide for libs since we can't destroy them commpletely yet, otherwise leave as nil
script_data.restart = nil -- how to restart the (lib) script after it's been hidden - i.e. make it visible again


local function stop_job(job)
  job.valid = false
end

local function validate_image(rs,image)
  local fails = {}
  local x = true
  for _,rule in ipairs(rs) do
    if (rule.sort=="form") then
      local y = rule.apply_at(image)
      x = x and y
      if (not y) then
        table.insert(fails, rule.name)
      end
    end
  end
  local result = {}
  result["passed"] = x
  result["fails"] = fails
  return result
end

local function set_to_string(set)
  if (#set == 0) then return "" end
    
  local str = set[1]
  for i=2,#set,1 do
    str = str .. ", " .. set[i]
  end
  return str
end

local function apply_rule(r,image)
  if r["sort"] == "form" then
    if r.apply_at(image) then return " ✓"
    else return " ❌"
    end
  end
  if r["sort"] == "int" then
    return " " .. r.apply_at(image)
  end
  if r["sort"] == "set" then
    local set = r.apply_at(image)
    return " {" .. set_to_string(set) .. "}"
  end
end

local function make_validate_image(rs,memo)
  extra = {}
  for i,rule in ipairs(rs) do
    extra[i] = apply_rule(rule,memo)
  end
  return extra
end


local function select_untagged_images(event, images)
  job = dt.gui.create_job("select badly tagged images", true, stop_job)
  local selection = {}
  local mymemo = {}
  local memo_cont = make_memo(mymemo)

  for key,image in ipairs(images) do
    if(job.valid) then
      job.percent = (key - 1)/#images

      for _,rule in ipairs(rules) do
      if (rule.sort == 'form') then
        memo_cont.image = image
        if (not rule.apply_at(memo_cont)) then
          table.insert(selection, image)
        end
      end
      end

    else
      break
    end
  end
  job.valid = false
  -- return table of images to set the selection to
  return selection
end

function myerrorhandler( err )
   print( "ERROR:", err )
end

function get_rules_raw()
  return  dt.preferences.read("tag_verify", "rules", "string")
end

function get_rules()
  local rs =  dt.preferences.read("tag_verify", "rules", "string")
  local r = {}
  r = esmatch(rs)
  if (r== nil) then r={} end
  return r
end

function write_rule(rule)
  local r = get_rules_raw()
  local x = expr_to_pref_string(rule)
  if (r == "") then dt.preferences.write("tag_verify", "rules", "string", x)
  else dt.preferences.write("tag_verify", "rules", "string", r..";"..x)
  end
end

function write_rules(x)
  dt.preferences.write("tag_verify", "rules", "string", x)
end

function clear_rules()
  dt.preferences.write("tag_verify", "rules", "string", "")
  rules = {}
end

local function make_rules_string(rs)
  return ps.intercalate(rs, ';', expr_to_pref_string) 
end

local function rule_to_text(rule)
  local post = ""
  if (rule.editing) then post = " editing ..." end
  return expr_to_pref_string(rule) .. post
end

local function populate_combobox(c)
  assert(#c==0)
  for i,rule in ipairs(get_rules()) do
    c[i] = rule.name
  end
  c.selected=#c
end

function update_combobox(c)
  return function(t)
  local n = #c+1
  c[n]=t
  c.selected=n
end
end
  
function clear_combobox(c)
  for i=#c,1,-1 do --have to go backwards
    c[i] = nil
  end
end

local function update_text_list(text_view)
  return function(extra)
    if (not extra) then
      extra = {}
      for i,_ in ipairs(rules) do
        extra[i] = ""
      end
    end
    assert(#extra == #rules)
    text_view.text = ps.intercalate(rules, '\n', function(r,i) return rule_to_text(r)..extra[i] end ) 
end
end

local function on_hover(gui)
  return function(event, image)

  memo_cont = make_memo({})
  memo_cont.image = image

  local extra = nil
  local text = ""
  if (not image) then
    text =""
  else
    text = image.filename
    extra = make_validate_image(rules,memo_cont)
  end
  gui.current_image.label = text
  gui.update_text_list(extra)
end
end


local function update_all(gui)
  local str = make_rules_string(rules)
  write_rules(str)
  gui.update_text_list()
  gui.clear_combobox()
  gui.populate_combobox()
  gui.rules_list.selected = nil
end


local function end_editing(gui)
  editing = false
  rules[editing_n].editing = false
  gui.rule_entry_label.label ="new rule:"
  gui.edit_button.label = "edit"
  gui.add_button.label = "add"
  gui.rule_entry.text = ""
  gui.update_text_list()
  gui.rules_list.selected = editing_n
end

local function delete_entry(gui)
  return function(self)
  if (editing) then end_editing(gui) end 
  local n = gui.rules_list.selected
  if (n==0 or n==nil) then return end
  local t = gui.rules_list[n]
  dt.print_toast("deleted rule: "..t)
  table.remove(rules,n)
  table.remove(gui.rules_list,n)
  update_all(gui)
  gui.rule_entry.text = t
end
end


local function add_entry(gui)
  return function(self)
  local t = gui.rule_entry.text
  local rule = ematch(t)
  if (rule==nil) then
    dt.print_toast("error: "..t)
  else
    if (editing) then
      dt.print_toast("updated: "..t)
      rules[editing_n] = rule
      update_all(gui)
      end_editing(gui)
    else
      dt.print_toast("added rule: "..t)
      local r1=get_rules_raw()
      write_rule(rule) 
      local r2 = get_rules_raw()
  --    assert((r1=="" and r2==t) or r2==(r1..","..t))
      assert(rules[#rules+1]==nil)
      rules[#rules+1] =rule 
      gui.update_combobox(t)
      gui.update_text_list()
      gui.rule_entry.text = "" 
  end
  end
end
end

local function edit_entry(gui)
  return function(self)
  local n = gui.rules_list.selected
  if (n== nil or n== 0) then 
    dt.print_toast("no rule selected") 
    return 
  end
  if (not editing) then
    editing = true
    editing_n = n 
    rules[n].editing = true
    local current = gui.rules_list.value
    gui.update_text_list()
    gui.rule_entry_label.label = "editing:"
    gui.edit_button.label = "cancel"
    gui.add_button.label = "save"
    gui.rule_entry.text = expr_to_pref_string(rules[editing_n]) 
  else
    end_editing(gui)
  end
end
end

local rule_entry = dt.new_widget("entry"){ tooltip = "please enter text here" }
local rule_entry_label = dt.new_widget("label"){label = "new rule:"}
local status_label = dt.new_widget("label"){label = ""}
local current_image = dt.new_widget("label"){label = ""}
local rules_list = dt.new_widget("combobox"){label = "rules"}
local rules_list_text = dt.new_widget("text_view"){editable = false}
local delete_button = dt.new_widget("button"){label = "delete"}
local edit_button = dt.new_widget("button"){label = "edit"}
local add_button = dt.new_widget("button"){label = "add"}
local debug_button = dt.new_widget("button"){label = "debug", visible=verbose}

local gui = {
  edit_button = edit_button, 
  add_button = add_button,
  current_image = current_image,
  rules_list_text = rules_list_text,
  rules_list = rules_list,
  rule_entry = rule_entry,
  rule_entry_label = rule_entry_label,
  update_text_list = update_text_list(rules_list_text),
  update_combobox = update_combobox(rules_list),
  populate_combobox = function() populate_combobox(rules_list) end,
  clear_combobox = function() clear_combobox(rules_list) end,
}

add_button.clicked_callback = add_entry(gui)
edit_button.clicked_callback = edit_entry(gui)
delete_button.clicked_callback = delete_entry(gui)

  local new_rule_box = dt.new_widget("box"){
    orientation = "horizontal",
    rule_entry_label,
    rule_entry,
    add_button
  }

  local select_rule_box = dt.new_widget("box"){
    orientation = "horizontal",
    rules_list,
    edit_button,
    delete_button
  }

local function debug(gui)
  return function(self)
    print("rules table:-------")
    ps.tprint(rules)
    print("rules string:------")
    print(get_rules_raw())
    print("rules list box:---")
    for i,r in ipairs(gui.rules_list) do
      print(i..": "..r)
    end
    print("editing: ")
    print(editing)
    print("editing_n: "..editing_n)
    print(dt.debug.dump(gui.rules_list))
    print("done")
  end
end

debug_button.clicked_callback = debug(gui)

local function clear(gui)
  return function(self)
      clear_rules()
      gui.clear_combobox()
      gui.rules_list.selected = 0
      gui.update_text_list()

end   
end

local my_widget = dt.new_widget("box"){
    new_rule_box,
    status_label,
    select_rule_box,
    current_image,
    rules_list_text,
    dt.new_widget("button"){label = "clear", clicked_callback = clear(gui) },
    debug_button,
 }


local function initialise()
rules = get_rules()
gui.populate_combobox()
  gui.update_text_list()
end

local function destroy()
  dt.gui.libs.select.destroy_selection("select_bad")
end

initialise()

  dt.register_lib("tag verify","tag verify",true,false,{
    [dt.gui.views.lighttable] = {"DT_UI_CONTAINER_PANEL_RIGHT_CENTER",460},
    },my_widget)

dt.gui.libs.select.register_selection(
  "select_bad", "select badly tagged",
  select_untagged_images,
  "select all images that do not pass the tag conditions")

dt.preferences.register("tag_verify", "tag_rules", "string", "Tag Rules", "t", "")
dt.register_event("update_hovered", "mouse-over-image-changed", on_hover(gui))



script_data.destroy = destroy

return script_data
