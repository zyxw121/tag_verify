--[[
   ]]

--[[
Enable tag system constraints and verification 
]]

local dt = require "darktable"
local ps = require "tag_verify/parse"

local verbose = true
local editing = false
local editing_n = 0


local rules = {}


local function expr_to_string(r)
  return r.sort .."("..r.name..")"
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




local fmatch = ps.ematch(get_tags, get_roll)
local ematch = ps.ematch(get_tags, get_roll)
local fsmatch = ps.esmatch(get_tags, get_roll)


-- return data structure for script_manager
local script_data = {}
script_data.destroy = nil -- function to destory the script
script_data.destroy_method = nil -- set to hide for libs since we can't destroy them commpletely yet, otherwise leave as nil
script_data.restart = nil -- how to restart the (lib) script after it's been hidden - i.e. make it visible again

local function swap()


end


local function stop_job(job)
  job.valid = false
end

local function validate_image(rs,image)
local fails = {}
local x = true
for _,rule in ipairs(rs) do
  local y = rule.apply_at(image)
  x = x and y
  if (not y) then
    table.insert(fails, rule.name)
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

local function make_validate_image(rs,image)
  extra = {}
  for i,rule in ipairs(rs) do
    extra[i] = apply_rule(rule,image)
  end
  return extra
end



local function select_untagged_images(event, images)
  job = dt.gui.create_job("select badly tagged images", true, stop_job)
  local selection = {}

  for key,image in ipairs(images) do
    if(job.valid) then
      job.percent = (key - 1)/#images
      result = validate_image(rules, image)
      if (not result["passed"]) then
        table.insert(selection, image)
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
  r = fsmatch(rs)
  if (r== nil) then r={} end
  return r
end

function write_rule(rule)
  local r = get_rules_raw()
  local x = expr_to_string(rule)
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


local rule_entry = dt.new_widget("entry"){ tooltip = "please enter text here" }





local function populate_combobox(c)
  assert(#c==0)
  for i,rule in ipairs(get_rules()) do
    c[i] = rule.name
  end
  c.selected=#c
end

function update_combobox(c,t)
  local n = #c+1
  c[n]=t
  c.selected=n
end
  
function clear_combobox(c)
  for i=#c,1,-1 do --have to go backwards
    c[i] = nil
  end
end

local rule_entry_label = dt.new_widget("label"){label = "new rule:"}
local status_label = dt.new_widget("label"){label = ""}
local current_image = dt.new_widget("label"){label = ""}



local function make_rules_string(rs)
  local str = ""
  if (#rs == 0) then 
    return ""
  end
  str = expr_to_string(rs[1])
  for i = 2,#rs,1 do
    str = str .. ";"..expr_to_string(rs[i])
  end
  return str
end

local rules_list = dt.new_widget("combobox"){label = "rules"}

local rules_list_text = dt.new_widget("text_view"){editable = false}

local function rule_to_text(rule)
  local post = ""
  if (rule.editing) then post = " editing ..." end
  return rule.name .. post
end


local function update_text_list(text_view, extra)
  if (not extra) then
    extra = {}
    for i,_ in ipairs(rules) do
      extra[i] = ""
    end
  end
  assert(#extra == #rules)
  local text = ""
  if (#rules == 0) then return 
  end
  text = rule_to_text(rules[1])..extra[1]
  for i =2,#rules,1 do 
   text = text.."\n"..rule_to_text(rules[i]) ..extra[i]
  end
  text_view.text = text
end

local function update_all(rules)
  local str = make_rules_string(rules)
  write_rules(str)
  update_text_list(rules_list_text)
  clear_combobox(rules_list)
  populate_combobox(rules_list)
  rules_list.selected = nil
end


local function end_editing(add_button, edit_button)
      editing = false
      rules[editing_n].editing = false
      rule_entry_label.label ="new rule:"
      edit_button.label = "edit"
      add_button.label = "add"
      rule_entry.text = ""
      update_text_list(rules_list_text)
      rules_list.selected = editing_n
end


local function delete_entry(add_button, edit_button)
  return function(self)
  if (editing) then 
  end_editing(add_button, edit_button)
  end 
  local n=  rules_list.selected
  local t = rules_list[n]
  dt.print_toast("deleted rule: "..rules_list[n])
  if (n==0 or n==nil) then return end
  table.remove(rules,n)
  table.remove(rules_list,n)
  update_all(rules)
  rule_entry.text = t
end
end


local function on_hover(event, image)
  local extra = nil
  local text = ""
  if (not image) then
    text =""
  else
    text = image.filename
    extra = make_validate_image(rules,image)
  end
  current_image.label = text
  update_text_list(rules_list_text, extra)
end

local function add_entry(edit_button)
  return function(self)
  local t = rule_entry.text
  local rule = ematch(t)
  if (rule==nil) then
    dt.print_toast("error: "..t)
  else
    if (editing) then
      dt.print_toast("updated: "..t)
      rules[editing_n] = rule
      update_all(rules)
      end_editing(self, edit_button)
    else
      dt.print_toast("added rule: "..t)
      local r1=get_rules_raw()
      write_rule(rule) 
      local r2 = get_rules_raw()
  --    assert((r1=="" and r2==t) or r2==(r1..","..t))
      assert(rules[#rules+1]==nil)
      rules[#rules+1] =rule 
      update_combobox(rules_list,t)
      update_text_list(rules_list_text)
      rule_entry.text = "" 
  end
  end
end
end




local function edit_entry(add_button)
  return function(self)
  local n = rules_list.selected
  if (n== nil or n== 0) then dt.print_toast("no rule selected")
  end
  if (not editing) then
    editing = true
    editing_n = n 
    rules[n].editing = true
    local current = rules_list.value
    update_text_list(rules_list_text)
    rule_entry_label.label = "editing:"
    self.label = "cancel"
    add_button.label = "save"
    rule_entry.text = rules_list[editing_n]
  else
    end_editing(add_button, self)
  end
end
end

local delete_button = dt.new_widget("button"){label = "delete"}
local edit_button = dt.new_widget("button"){label = "edit"}
local add_button = dt.new_widget("button"){label = "add"}

add_button.clicked_callback = add_entry(edit_button)
edit_button.clicked_callback = edit_entry(add_button)
delete_button.clicked_callback = delete_entry(add_button, edit_button)

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

local function debug(self)
print("rules table:-------")
ps.tprint(rules)
print("rules string:------")
print(get_rules_raw())
print("rules list box:---")
for i,r in ipairs(rules_list) do
  print(i..": "..r)
end
print(dt.debug.dump(self))

end

local function clear()
      clear_rules()
      clear_combobox(rules_list)
      rules_list.selected = 0
      update_text_list(rules_list_text)

end

local my_widget = dt.new_widget("box"){
    new_rule_box,
    status_label,
    select_rule_box,
    current_image,
    rules_list_text,
    dt.new_widget("button"){label = "clear", clicked_callback = clear },
    dt.new_widget("button"){label="debug", clicked_callback = debug},
 }


local function initialise()
rules = get_rules()

populate_combobox(rules_list)
  update_text_list(rules_list_text)
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
dt.register_event("update_hovered", "mouse-over-image-changed", on_hover)



script_data.destroy = destroy

return script_data
