--[[
   ]]

--[[
Enable tag system constraints and verification 
]]

local dt = require "darktable"
local ps = require "tag_verify/parse"
local rules = {}


local function tag_string(image)
  tags = image.get_tags(image)
  local ts = ""
  for _,t in ipairs(tags) do
    ts = ts .. t.name ..", "
  end
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

local fmatch = ps.fmatch(get_tags, get_roll)
local fsmatch = ps.fsmatch(get_tags, get_roll)


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

local function make_validate_image(rs,image)
  extra = {}
  for i,rule in ipairs(rs) do
    if (rule.apply_at(image)) then
      extra[i] = " passed"
    else
      extra[i] = " failed"
    end
  end
  return extra
end



local function select_untagged_images(event, images)
  job = dt.gui.create_job(_("select untagged images"), true, stop_job)
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

function write_rule(x)
  local r = get_rules_raw()
  if (r == "") then dt.preferences.write("tag_verify", "rules", "string", x)
  else dt.preferences.write("tag_verify", "rules", "string", r..","..x)
  end
end

function write_rules(x)
  dt.preferences.write("tag_verify", "rules", "string", x)
end
  

function clear_rules()
  dt.preferences.write("tag_verify", "rules", "string", "")
  rules = {}
end


local my_entry = dt.new_widget("entry"){ tooltip = "please enter text here" }





local function populate_combobox(c)
  assert(#c==0)
  for i,rule in ipairs(get_rules()) do
    c[i] = rule.name
  end
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

local my_label = dt.new_widget("label"){label = "new rule:"}
local status_label = dt.new_widget("label"){label = "status:"}
local current_image = dt.new_widget("label"){label = ""}



local function make_rules_string(rs)
  local str = ""
  if (#rs == 0) then 
    return ""
  end
  str = rs[1].name
  for i = 2,#rs,1 do
    str = str .. ","..rs[i].name
  end
  return str
end

local rules_list = dt.new_widget("combobox"){label = "test"}

local rules_list_text = dt.new_widget("text_view"){editable = false}

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
  text = rules[1].name..extra[1]
  for i =2,#rules,1 do 
   text = text.."\n"..rules[i].name ..extra[i]
  end
  text_view.text = text
end

local function delete_entry()
  local n=  rules_list.selected
  dt.print_toast("deleted rule: "..rules_list[n])
  if (n==0 or n==nil) then return end
  table.remove(rules,n)
  table.remove(rules_list,n)
  local str = make_rules_string(rules)
  write_rules(str)
  update_text_list(rules_list_text)
  clear_combobox(rules_list)
  populate_combobox(rules_list)

end
local delete_button = dt.new_widget("button"){label = "delete", clicked_callback = delete_entry}
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


local function add_entry()
  local t = my_entry.text
  local rule = fmatch(t)
  if (rule==nil) then
    dt.print_toast("error: "..t)
  else
    dt.print_toast("added rule: "..t)
    r1=get_rules_raw()
    write_rule(t) 
    r2 = get_rules_raw()
    assert((r1=="" and r2==t) or r2==(r1..","..t))
    assert(rules[#rules+1]==nil)
    local x = {}
    x["name"] = t
    x["apply_at"] = rule
    rules[#rules+1] =rule 
  update_combobox(rules_list,t)
  update_text_list(rules_list_text)
  end

end

  local new_rule_box = dt.new_widget("box"){
    orientation = "horizontal",
    my_label,
    my_entry,
    dt.new_widget("button"){label = "add", clicked_callback = add_entry}
  }

  local select_rule_box = dt.new_widget("box"){
    orientation = "horizontal",
    rules_list,
    delete_button
  }

local my_widget = dt.new_widget("box"){
    new_rule_box,
    status_label,
    select_rule_box,
    current_image,
    rules_list_text,
    dt.new_widget("button"){label = "clear", clicked_callback = function() 
      clear_rules()
      clear_combobox(rules_list)
      rules_list.selected = 0
      update_text_list(rules_list_text)
    end
    },
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

  dt.register_lib("test","tag verify",true,false,{
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
