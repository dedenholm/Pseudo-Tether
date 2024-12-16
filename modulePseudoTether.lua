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
local df = require "lib/dtutils.file"
local inotify = require "inotify"
local handle = inotify.init { blocking = false }
du.check_min_api_version("7.0.0", "moduleExample")
local handle_returned =false
local sleep = dt.control.sleep
-- https://www.darktable.org/lua-api/index.html#darktable_gettext
local gettext = dt.gettext.gettext 

local watch_active = false
dt.gettext.bindtextdomain("moduleExample", dt.configuration.config_dir .."/lua/locale/")

local function _(msgid)
    return gettext(msgid)
end
-- return data structure for script_manager

local script_data = {}

script_data.metadata = {
  name = "Pseudo Tether",
  purpose = _("Automatically import files from folder"),
  author = "Daniel Rognkskog Edenholm",
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

local default_ingest_directory = dt.preferences.read("Pseudo_Tether",
"default_ingest_directory",
"directory")

print(dt.films[1].path .. " path to film #1!")

local function install_module()
  if not mE.module_installed then
    -- https://www.darktable.org/lua-api/index.html#darktable_register_lib
    dt.register_lib(
      "exampleModule",     -- Module name
      "exampleModule",     -- name
      true,                -- expandable
      false,               -- resetable
      {[dt.gui.views.lighttable] = {"DT_UI_CONTAINER_PANEL_RIGHT_CENTER", 100}},   -- containers
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

print ("dimpf" .. default_destination_directory)-- script_manager integration to allow a script to be removed

-- without restarting darktable
local function destroy()
    dt.gui.libs["exampleModule"].visible = false -- we haven't figured out how to destroy it yet, so we hide it for now
end

local function restart()
    dt.gui.libs["exampleModule"].visible = true -- the user wants to use it again, so we just make it visible and it shows up in the UI
end

-- https://www.darktable.org/lua-api/types_lua_check_button.html


-- https://www.darktable.org/lua-api/types_lua_entry.html
local jobcode = dt.new_widget("entry")
{
    text = "jobcode",
    placeholder = _("jobcode"),
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

local label = dt.new_widget("label")
label.label = _("my label") -- This is an alternative way to the "{}" syntax to set a property 
--local separator = dt.new_widget("separator"){}

local button3_toggle =false
local function button3_clicked(handle_read_cancel)
  if button3_toggle == true then
      button3_toggle = false
  else
      button3_toggle = true 
  end

  local watch_dir = ingest_directory.value

  print ("button3 clicked")

  dd.dprint(dt.gui.libs.copy_history)
 
  -- handle_read_cancel(watch_dir)
end


local move_files = dt.new_widget("check_button")
        {
          label = _("move to library"),
          visible = true,
          value = true
}

local function handle_read_cancel(watch_dir)
  local cancel_file = watch_dir .. '/cancel_file'
  local file = io.open(cancel_file, "w")


  if file == nil then print("error writing file") return
  else file:close() end

  print(cancel_file .."written")
  os.remove(cancel_file)
  print(cancel_file .."deleted")
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
    print ("Jobcode" .. jobcode.text)

    return imported_image
end


local function sort_in_library(imported_image)
 dd.dprint(imported_image)

  if df.check_if_file_exists(destination_directory.value) == true then


    print(destination_directory.value .. " exists")

    local final_directory = destination_directory.value .. "/" .. jobcode.text

    local  film_already_exists = search_film(final_directory)
    print(film_already_exists)
    if film_already_exists == 0 then

      print("film_already_exists == 0")

      if df.check_if_file_exists(final_directory) ==false then print ("making dir") df.mkdir(final_directory) end
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



local function handle_read(watch_dir, button2)
--local event= handle:read()
  print(watch_dir)
  watch_active= true
  --dd.dprint(event)
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
            imported_image = import_to_library(ingest_file)
          if move_files.value == true then sort_in_library(imported_image) end
        
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



local function buttonclicked(button, button2)


    dt.print(_("button clicked"))
--    if watch_dir == nil then 
  --  dt.print("please choose a directory to import from")
    --return

--  end   
    local watch_dir = ingest_directory.value
    button2.visible = true
    button.visible = false
    ingest_directory.visible = false
    jobcode.visible = false
    print("state1")
    print(watch_dir)
    handle_read(watch_dir, button2)
    print("state2")
    print('done_daniel')
end

local function button2clicked(button, button2)
    local watch_dir=ingest_directory.value
    print ("button2 clicked")
    dt.print("button2 clicked")
    watch_active = false
    --handle:rmwatch(wd)
    -- handle_read_cancel(watch_dir)
    button2.visible =false
    button.visible =true
    ingest_directory.visible = true
    jobcode.visible = true
end

  local button3 = dt.new_widget("button")
      {label = "handle close"
  }

local button = dt.new_widget("button")
        {
          label = _("my button"),
        }

local button2 = dt.new_widget("button")
        {
          label = _("my button2"),
          visible = false,
        }
dd.dprint(inotify)
button.clicked_callback = function () buttonclicked(button, button2) end
button2.clicked_callback = function() button2clicked(button, button2) end
button3.clicked_callback = function() button3_clicked(handle_read_cancel) end
  -- code

-- pack the widgets in a table for loading in the moidule
table.insert(mE.widgets, button)
--table.insert(mE.widgets, check_button)
table.insert(mE.widgets, button2)
table.insert(mE.widgets, button3)
--table.insert(mE.widgets, combobox)
table.insert(mE.widgets, jobcode)
table.insert(mE.widgets, ingest_directory)
table.insert(mE.widgets, move_files)
table.insert(mE.widgets, destination_directory)

--table.insert(mE.widgets, label)i
--table.insert(mE.widgets, separator)
--table.insert(mE.widgets, slider)

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
