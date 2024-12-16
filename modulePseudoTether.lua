--[[
    This file is part of darktable,
    copyright (c) 2016 Tobias Jakobs

    darktable is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    darktable is distributed in the hope that it will be useful,
     but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with darktable.  If not, see <http://www.gnu.org/licenses/>.
]]
--[[

USAGE
* require this script from your luarc file
  To do this add this line to the file .config/darktable/luarc: 
require "examples/moduleExample"

* it creates a new example lighttable module

More informations about building user interface elements:
https://www.darktable.org/usermanual/ch09.html.php#lua_gui_example
And about new_widget here:
https://www.darktable.org/lua-api/index.html.php#darktable_new_widget
]]
local dd = require "lib/dtutils.debug"
local dt = require "darktable"
local du = require "lib/dtutils"
local ds = require "lib/dtutils.string"
local df = require "lib/dtutils.file"
local inotify = require "inotify"
local handle = inotify.init { blocking = false }

du.check_min_api_version("7.0.0", "moduleExample")
local sleep = dt.control.sleep
-- https://www.darktable.org/lua-api/index.html#darktable_gettext
local gettext = dt.gettext.gettext
local dsprobe =table.unpack(ds)
dd.dprint (dsprobe)
print("a")
dd.dprint(ds.build_substitute_list)
print("b")
local watch_active = false
dt.gettext.bindtextdomain("moduleExample", dt.configuration.config_dir .."/lua/locale/")

local function _(msgid)
    return gettext(msgid)
end
-- return data structure for script_manager

local script_data = {}

script_data.metadata = {
  name = "Pseudo Tether",
  purpose = _("Automatically import files added to folder"),
  author = "Daniel Rognskog Edenholm",
  help = ""
}

script_data.destroy = nil -- function to destory the script
script_data.destroy_method = nil -- set to hide for libs since we can't destroy them commpletely yet, otherwise leave as nil
script_data.restart = nil -- how to restart the (lib) script after it's been hidden - i.e. make it visible again
script_data.show = nil -- only required for libs since the destroy_method only hides them

-- translation

-- declare a local namespace and a couple of variables we'll need to install the module
local mE = {}
mE.widgets = {}
mE.event_registered = false  -- keep track of whether we've added an event callback or not
mE.module_installed = false  -- keep track of whether the module is module_installed

--[[ We have to create the module in one of two ways depending on which view darktable starts
     in.  In orker to not repeat code, we wrap the darktable.register_lib in a local function.

]]

 local function table_contains(table, value)

  for i in ipairs(table) do
    if (table[i] == value) then
      return true
    end
  end
  return false
end


local function search_film(film_path)
  print(film_path)
  for i in ipairs(dt.films) do
    print (i .. " " .. dt.films[i].path)
    if dt.films[i].path == film_path then
      return i
    end
  end

  return 0


end


dt.preferences.register("Pseudo_Tether",
                        "default_ingest_directory",
                        "directory",
                        "Default Watched Directory",
                        "The default directory to watch for incoming files",
                        ""
)
dt.preferences.register("Pseudo_Tether",
                        "default_destination_directory",
                        "directory",
                        "Default destination directory",
                        "default directory to move files to",
                        "/home/$USER/Pictures/")
dt.preferences.register("Pseudo_Tether",
                        "jpeg",
                        "bool",
                        ".jpeg",
                        "import jpeg files added to watch directory",
                        true
)
dt.preferences.register("Pseudo_Tether",
                        "nef",
                        "bool",
                        ".NEF",
                        "import NEF files added to watch directory",
                        true
)
dt.preferences.register("Pseudo_Tether",
                        "cr2",
                        "bool",
                        ".CR2",
                        "import CR2 files added to watch directory",
                        true
)
dt.preferences.register("Pseudo_Tether",
                        "dng",
                        "bool",
                        ".DNG",
                        "import DNG files added to watch directory",
                        true
)
dt.preferences.register ("Pseudo_Tether",
                        "tiff",
                        "bool",
                        ".tiff",
                        "import .tiff files added to watch directory",
                        true
)

dt.preferences.register("Pseudo_Tether",
                          "ext_custom",
                          "string",
                          "custom extension",
                          "add a custom extension to import",
                          ".IIQ"
                        )
if dt.preferences.read("Pseudo_Tether", "session_counter", "integer") <= 0 then print("no session counter") dt.preferences.write("Pseudo_Tether", "session_counter", "integer", "0000") else print("session_counter: " .. dt.preferences.read("Pseudo_Tether", "session_counter", "integer") )end


local ext_table = {"jpeg","nef","cr2", "dng","tiff"}

local ext_watched_extensions = {}
--print (dt.preferences.read("Pseudo_Tether","ext_TIFF","string"))
  for ext in ipairs(ext_table) do

        print(ext_table[ext] .. " added")
        if dt.preferences.read("Pseudo_Tether", ext_table[ext], "bool") == true then
          table.insert(ext_watched_extensions, ext_table[ext])
          if ext_table[ext]  == "jpeg" then
            table.insert(ext_watched_extensions, "jpg")
          end
          if ext_table[ext] == "tiff" then
            table.insert(ext_watched_extensions, "tif")
          end
        end
  end

table.insert(ext_watched_extensions, string.lower(dt.preferences.read("Pseudo_Tether", "ext_custom", "string")))

print(table.unpack(ext_watched_extensions))
local default_ingest_directory = dt.preferences.read("Pseudo_Tether",
"default_ingest_directory",
"directory")

print(dt.films[1].path .. " path to film #1!")


local function install_module()
  if not mE.module_installed then
    -- https://www.darktable.org/lua-api/index.html#darktable_register_lib
    dt.register_lib(
      "PseudoTether",     -- Module name
      "PseudoTether",     -- name
      true,                -- expandable
      false,               -- resetable

      {[dt.gui.views.lighttable] = {"DT_UI_CONTAINER_PANEL_RIGHT_CENTER", 100},[dt.gui.views.darkroom] = {"DT_UI_CONTAINER_PANEL_LEFT_CENTER", 100}},   -- containers
      -- https://www.darktable.org/lua-api/types_lua_box.html
      dt.new_widget("box") -- widget
      {
        orientation = "vertical",
      table.unpack(mE.widgets),
      },
      nil,-- view_enter
      nil -- view_leave
    )

    mE.module_installed = true
  end
end
local default_destination_directory = dt.preferences.read("Pseudo_Tether","default_destination_directory",
  "directory"
)

print ("dimpf" .. default_destination_directory)

-- script_manager integration to allow a script to be removed
-- without restarting darktable

local function destroy()
    dt.gui.libs["PseudoTether"].visible = false -- we haven't figured out how to destroy it yet, so we hide it for now
end

local function restart()
    dt.gui.libs["PseudoTether"].visible = true -- the user wants to use it again, so we just make it visible and it shows up in the UI
end



local session_title = dt.new_widget("entry")
{
    text = "Capture Session",
    placeholder = _("Capture Session"),
    is_password = false,
    editable = true,
    tooltip = _("name of the filmroll you want to import to"),
    reset_callback = function(self) self.text = "text" end
}
local destination_directory = dt.new_widget("file_chooser_button")
{
  title = _("import to directory"),
  value = default_destination_directory,
  is_directory = true
}
-- https://www.darktable.org/lua-api/types_lua_file_chooser_button.html
local ingest_directory = dt.new_widget("file_chooser_button")
{
    title = _("Import from directory"),  -- The title of the window when choosing a file
    value = default_ingest_directory,                       -- The currently selected file
    is_directory = true              -- True if the file chooser button only allows directories to be selecte
}
local session_counter = dt.new_widget("label")
      session_counter.label = dt.preferences.read("Pseudo_Tether", "session_counter", "integer")


local label = dt.new_widget("label")
label.label = _("my label") -- This is an alternative way to the "{}" syntax to set a property 
--local separator = dt.new_widget("separator"){}
local separator = dt.new_widget("separator")
separator.orientation = "vertical"
local prepend_date =dt.new_widget("check_button"){label = _("Add datecode prefix"),
visible =true,
value = true}

local ingest_directory_box = dt.new_widget("box"){
                                    orientation ="horizontal",
                                    dt.new_widget("label"){label="Watched Directory: ", halign ="start"},
                                    ingest_directory
}

local destination_directory_box =dt.new_widget("box"){
                                    orientation ="horizontal",
                                    dt.new_widget("label"){label="Destination Directory: ", halign ="start"},
                                    destination_directory
}
local move_files = dt.new_widget("check_button")
        {
          label = _("move to library"),
          visible = true,
          value = true
}
local reset_session_counter = dt.new_widget("button")
        {label = "Reset session counter"}
local move_files_options = dt.new_widget("box"){orientation = "horizontal",
prepend_date, reset_session_counter}
local jobcode_box = dt.new_widget("box"){
                                    orientation ="horizontal",
                                    dt.new_widget("label"){label = "Jobcode:",halign ="start"},
                                    session_title,
                                    session_counter
}
local function jobcode(image, sequence)
  print("function jobcode" .. sequence)
  print(session_title.text)
  print(session_counter.label .. " counter")
  local session = session_title.text .. " " .. session_counter.label
  if prepend_date.value == true then session = "$(YEAR)$(MONTH)$(DAY)".. session end
  ds.build_substitute_list(image, sequence, session)

  local jobcode_substituted =  ds.substitute_list(session)

  --local jobcode_substituted = ds.substitute_list(image, sequence, session_title.text ..  " " .. session_counter.label)
  --jobcode = ds.substitute(image, sequence, session_title.text .. " " .. session_counter.label)
  print(jobcode_substituted)
  return jobcode_substituted
end

local function move_files_extra_options()
  if move_files.value == false then
    destination_directory_box.visible = false
    jobcode_box.visible = false
    move_files_options.visible =false
  elseif move_files.value == true then
    destination_directory_box.visible = true
    move_files_options.visible =true
    jobcode_box.visible = true
  end
end


local function import_to_library(file)
    --file = df.sanitize_filename(file)
    print(file .. " Recieved")
    local filetype = df.get_filetype(file)
    if filetype then

    filetype = string.lower(filetype)

    if table_contains(ext_watched_extensions, filetype) == true then

    print(file.. " with filetype ".. filetype .. " is wanted ")
    local imported_image = dt.database.import(file)
    --dd.dprint(imported_image)
    return imported_image

    else
      print( file.. " with filetype " .. filetype .. " is not wanted" )
    end
    end
    return 0

end


local function sort_in_library(imported_image, sequence)
  dd.dprint(imported_image)
  print ("sequence " .. sequence)

  if df.check_if_file_exists(destination_directory.value) == true then


    print(destination_directory.value .. " exists")
    print ("calculated jobcode: " .. jobcode(imported_image, sequence))
    local final_directory = destination_directory.value .. "/" .. jobcode(imported_image, sequence)

    local  film_already_exists = search_film(final_directory)
    print(film_already_exists)
    if film_already_exists == 0 then

      print("film_already_exists == 0")
      if df.check_if_file_exists(final_directory) == false then print ("making dir") df.mkdir(df.sanitize_filename(final_directory))
        if df.check_if_file_exists(final_directory) == false then print("failed creating " .. final_directory) return end end
      print("final dirextory " .. final_directory)
      print("final Directory sanitized" .. df.sanitize_filename(final_directory))
      print("create film")
      local new_film = dt.films.new(final_directory)
      print (new_film.path .. "newfilm")
      print (new_film)
      print ("move image")
      dt.database.move_image(new_film, imported_image)


    else

      print("film already exists. adding image")
      dt.database.move_image(imported_image, dt.films[film_already_exists])
      print ("image added to film ".. final_directory)
      print ("image moved to" .. dt.films[film_already_exists].path)

     end
  end
end



local function handle_read(watch_dir)
  print(watch_dir)
  watch_active= true

  local dt_message = "Files added to '" .. watch_dir .. "' will be imported"
  if move_files.value == true then dt_message = dt_message ..  " and moved to '" .. destination_directory.value .. "/" end -- .. jobcode() .. "'"end

  dt.print("Capture Session Started")
  dt.print(dt_message)

  print(inotify.IN_MOVED_TO .. "   inmovedto")

  local wd = handle:addwatch(watch_dir, inotify.IN_CREATE, inotify.IN_MOVED_TO, inotify.IN_MOVE)
  while watch_active==true do

    local inotify_events = handle:read()

    for i,ev in pairs(inotify_events) do
      if(ev["mask"] == inotify.IN_MOVED_TO) then

        local ingest_file = watch_dir ..'/'.. ev.name
        print (inotify.IN_MOVED_TO.. " moved to")
        print (inotify.IN_MOVE .. " moved")
        print (inotify.IN_CREATE .. " create")
        print(ev["mask"])
        print (ev["mask"] == inotify.IN_MOVED_TO)
        print(ingest_file)
          --ingest_file = df.sanitize_filename(ingest_file) 

        local filetype = df.get_filetype(ingest_file)
        print(filetype .."filetype")
          if table_contains(ext_watched_extensions,filetype) then
            print("file wanted")
          local imported_image = import_to_library(ingest_file)
          if move_files.value == true then sort_in_library(imported_image, i) end

           else
            print ("not that one")
      end
      end
      end
  sleep(1500)
  print("file event sync frame.")
  end
  dd.dprint(wd)
  handle:rmwatch(wd)

end



local function start_capture(button_start_capture, button_stop_capture)


    local watch_dir = ingest_directory.value

    if watch_dir == nil then
      dt.print("please choose a directory to import from")
    return

    end

    button_stop_capture.visible = true
    button_start_capture.visible = false
    ingest_directory_box.visible = false
    jobcode_box.visible = false
    destination_directory_box.visible = false

    print("state1")
    print(watch_dir)
    handle_read(watch_dir)
    print("state2")
    print('done_daniel')
end

local function stop_capture(button_start_capture, button_stop_capture)

    dt.print("Capture Session Ended")
    watch_active = false
    button_stop_capture.visible =false
    button_start_capture.visible =true
    ingest_directory_box.visible = true
    dt.preferences.write("Pseudo_Tether", "session_counter", "integer", dt.preferences.read("Pseudo_Tether", "session_counter", "integer")+1)
    session_counter.label = dt.preferences.read("Pseudo_Tether", "session_counter", "integer")
    move_files_extra_options()
end

--  local button3 = dt.new_widget("button")
 --     {label = "handle close"
  --}

local button_start_capture = dt.new_widget("button")
        {
          label = _("Start Capture Session"),
        }

local button_stop_capture = dt.new_widget("button")
        {
          label = _("End Capture Session"),
          visible = false,
        }
dd.dprint(inotify)

move_files.clicked_callback = function() move_files_extra_options() end
button_start_capture.clicked_callback = function () start_capture(button_start_capture,button_stop_capture) end
button_stop_capture.clicked_callback = function() stop_capture(button_start_capture,button_stop_capture) end
reset_session_counter.clicked_callback = function() dt.preferences.write("Pseudo_Tether", "session_counter", "integer", "0000") session_counter.label = 0000 end

-- pack the widgets in a table for loading in the moidule
table.insert(mE.widgets, button_start_capture)
table.insert(mE.widgets, button_stop_capture)
-- table.insert(mE.widgets, button3)
--table.insert(mE.widgets, combobox)
table.insert(mE.widgets, ingest_directory_box)

table.insert(mE.widgets, separator)

table.insert(mE.widgets, move_files)
table.insert(mE.widgets, destination_directory_box)
table.insert(mE.widgets, jobcode_box)
table.insert(mE.widgets, move_files_options)
table.insert(mE.widgets, label)

-- ... and tell dt about it all

if dt.gui.current_view().id == "lighttable" then -- make sure we are in lighttable view
  install_module()  -- register the lib
else
  if not mE.event_registered then -- if we are not in lighttable view then register an event to signal when we might be
    -- https://www.darktable.org/lua-api/index.html#darktable_register_event
    dt.register_event(
      "mdouleExample", "view-changed",  -- we want to be informed when the view changes
      function(event, old_view, new_view)
        if new_view.name == "lighttable" and old_view.name == "darkroom" then  -- if the view changes from darkroom to lighttable
          install_module()  -- register the lib
         end
      end
    )
    mE.event_registered = true  --  keep track of whether we have an event handler installed
  end
end

-- set the destroy routine so that script_manager can call it when
-- it's time to destroy the script and then return the data to 
-- script_manager
script_data.destroy = destroy
script_data.restart = restart  -- only required for lib modules until we figure out how to destroy them
script_data.destroy_method = "hide" -- tell script_manager that we are hiding the lib so it knows to use the restart function
script_data.show = restart  -- if the script was "off" when darktable exited, the module is hidden, so force it to show on start

return script_data
-- vim: shiftwidth=2 expandtab tabstop=2 cindent syntax=lua
-- kate: hl Lua;
