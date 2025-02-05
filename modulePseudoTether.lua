--[[
    This0le is part of darktable,
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
local gettext = dt.gettext.gettext

dt.gettext.bindtextdomain("moduleExample", dt.configuration.config_dir .."/lua/locale/")

local function _(msgid)
    return gettext(msgid)
end

 -- Variables --
--
--


local watch_active = false
local previous_image
local current_image
local ext_watched_extensions = {}
local curr_img_id
local prev_img_id
local imported_image
local empty_style
local last_session_title
--Script manager Stuff


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
local pt = {}
 pt.widgets = {}
pt.event_registered = false  -- keep track of whether we've added an event callback or not
pt.module_installed = false  -- keep track of whether the module is module_installed
--[[ We have to create the module in one of two ways depending on which view darktable starts
  in.  In orker to not repeat code, we wrap the darktable.register_lib in a local function.
--]]





-- Two match functions:


local function table_contains(table, value)

  for i in ipairs(table) do
    if (table[i] == value) then
      return true
    end
  end
  return false
end


local function search_film(film_path)
  for i in ipairs(dt.films) do
    if dt.films[i].path == film_path then
      return i
    end
  end

  return 0

end


local function register_prefs()
dt.preferences.register("Pseudo_Tether", "variable_substitution", "bool", "Variable Substitution", "Use darktables variable substitution feature on the session name", true)

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
                        "create_session_counter_tag",
                        "bool",
                        "Auto tag images with session #",
                        "Automatically create the tag: 'Info|Capture Session|<Session #>'",
                        true)
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

if dt.preferences.read("Pseudo_Tether", "session_counter", "integer") <= 0 then print("no session counter") dt.preferences.write("Pseudo_Tether", "session_counter", "integer", "0") else print("session_counter: " .. dt.preferences.read("Pseudo_Tether", "session_counter", "integer") )end
end


if dt.preferences.read("Pseudo_Tether", "session_title", "string") == "" or nil then print("lst nil") last_session_title = _("Session Name") else print("lst not nil") last_session_title = dt.preferences.read("Pseudo_Tether", "session_title", "string") end
local default_ingest_directory = dt.preferences.read("Pseudo_Tether",
"default_ingest_directory",
"directory")

local default_destination_directory = dt.preferences.read("Pseudo_Tether","default_destination_directory",
  "directory"
)

-- build a list of file extensions to watch for:

local function ext_watchlist()
    local ext_table = {"jpeg","nef","cr2", "dng","tiff"}
    for ext in ipairs(ext_table) do
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
  return ext_watched_extensions
end

-- Process the session number to a string for file naming

local function session_counter_stringify ()
  local session_counter_string = "" .. dt.preferences.read("Pseudo_Tether", "session_counter", "integer")

  while string.len(session_counter_string) <= 3 do
      session_counter_string = "0" .. session_counter_string
      print(session_counter_string)
  end

return session_counter_string
  end

local function install_module()
  if not pt.module_installed then

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
      table.unpack(pt.widgets),
      },
      nil,-- view_enter
      nil -- view_leave
    )

    pt.module_installed = true
  end
end
-- script_manager integration to allow a script to be removed
-- without restarting darktable
local function destroy()
    dt.gui.libs["PseudoTether"].visible = false
    dt.styles.delete(empty_style)
    -- we haven't figured out how to destroy it yet, so we hide it for now
    watch_active = false
end

local function restart()
    dt.gui.libs["PseudoTether"].visible = true -- the user wants to use it again, so we just make it visible and it shows up in the UI
end

local function refresh_collection()
  local rules = dt.gui.libs.collect.filter()
  dt.gui.libs.collect.filter(rules)
end

-- Widget definitions:

    local session_title = dt.new_widget("entry")
    {
      text = last_session_title,
      placeholder = last_session_title,
      is_password = false,
      editable = true,
      tooltip = _("name of the filmroll you want to import to"),
      visible = true,
      reset_callback = function(self) self.text = "text" end
    }
    local destination_directory = dt.new_widget("file_chooser_button")
    {
      title = _("import to directory"),
      value = default_destination_directory,
      is_directory = true,
      visible = true,
    }
    local ingest_directory = dt.new_widget("file_chooser_button")
    {
      title = _("Import from directory"),  -- The title of the window when choosing a file
      value = default_ingest_directory,                       -- The currently selected file
      is_directory = true,             -- True if the file chooser button only allows directories to be selecte
      visible = true
    }
    local session_counter = dt.new_widget("label")

    session_counter.label = session_counter_stringify()
    session_counter.visible = true
    session_counter.ellipsize = "none"

    local separator = dt.new_widget("separator")
    separator.orientation = "horizontal"
    separator.visible =true


    local prepend_date =dt.new_widget("check_button"){label = _("Add datecode prefix:"),
                                    visible =true,
                                    value = true}
    local directory_label_box = dt.new_widget("box"){
                                    orientation ="vertical",
                                    dt.new_widget("label"){label="Watched Directory: ", halign ="start"},
                                    visible = true
    }
    local watch_folder_box= dt.new_widget("box"){
                                    dt.new_widget("label"){ label ="Watched directory:"},
                                    ingest_directory,
                                    orientation ="vertical",
    }
    local move_files = dt.new_widget("check_button"){
                                    label = _("Sort after import:"),
                                    visible = true,
                                    value = true
    }
    local propagate_history_button = dt.new_widget("check_button")
                                    {label = "propagate history",
                                    value = false
    }  
    local move_files_box = dt.new_widget("box"){
                                    orientation ="vertical",
                                    visible = true,
                                    move_files,
                                    destination_directory,
    }
    local reset_session_counter = dt.new_widget("button"){
                                    label = "Reset session counter",
                                    visible = true
    }

    local increment_session_counter = dt.new_widget("button"){
                                    label ="+",
                                    visible = true
    }
    local decrease_session_counter = dt.new_widget("button"){
                                    label ="-",
                                    visible = true
}

    local move_files_options = dt.new_widget("box"){orientation = "vertical",
                                    dt.new_widget("box"){orientation= "horizontal",
                                    propagate_history_button
                                    },
    }
    local sessioncode_header = dt.new_widget("section_label"){label = "SessionCode:"}
    local jobcode_box = dt.new_widget("box"){orientation ="vertical",
                                    dt.new_widget("box"){orientation ="horizontal",
                                      prepend_date,
                                      dt.new_widget("label"){label= os.date("%Y%m%d"), halign="start"}
                                    },
                                    dt.new_widget("box"){orientation ="horizontal",
-- dt.new_widget("label"){label = "SessionCode:",halign ="start", ellipsize ="none"},
                                    session_title,
                                    decrease_session_counter,
                                    session_counter,
                                    increment_session_counter,
                                    visible =true,
                                    },
                                    -- reset_session_counter
    }
    local jobcode_display = dt.new_widget("label"){visible=false, label =os.date("%Y%m%d") .. "_" .. session_title.text .. session_counter_stringify()}
        local button_start_capture = dt.new_widget("button"){
                                    label = _("Start Capture Session"),
                                    visible = true,
    }
    local button_stop_capture = dt.new_widget("button"){
                                    label = _("End Capture Session"),
                                    visible = false,
        }


local function toggle_move_files_options(bool)
  if move_files.value == false then
    jobcode_box.visible = false
    move_files_options.visible =false
    destination_directory.visible =false
  elseif move_files.value == true then
    move_files_options.visible =bool
    jobcode_box.visible = bool
    destination_directory.visible= bool
  end
end

local function toggle_capture_buttons(bool)
    button_stop_capture.visible = not bool
    button_start_capture.visible = bool
    watch_folder_box.visible = bool
    jobcode_box.visible = bool
    move_files_box.visible = bool
    jobcode_display.visible = not bool
end


local function init_gui(start_capture,stop_capture)


    move_files.clicked_callback = function() toggle_move_files_options(move_files.value) end
    button_start_capture.clicked_callback = function () start_capture(button_start_capture,button_stop_capture) end
    button_stop_capture.clicked_callback = function() stop_capture(button_start_capture,button_stop_capture) end
    reset_session_counter.clicked_callback = function() dt.preferences.write("Pseudo_Tether", "session_counter", "integer", "0") session_counter.label = session_counter_stringify() end
    increment_session_counter.clicked_callback = function() dt.preferences.write("Pseudo_Tether", "session_counter", "integer", dt.preferences.read("Pseudo_Tether", "session_counter", "integer")+1) session_counter {label = session_counter_stringify(),ellipsize ="none"} end
    decrease_session_counter.clicked_callback = function() dt.preferences.write("Pseudo_Tether", "session_counter", "integer", dt.preferences.read("Pseudo_Tether", "session_counter", "integer")-1)  session_counter {label = session_counter_stringify(),ellipsize ="none"} end



    table.insert(pt.widgets, watch_folder_box)
    table.insert(pt.widgets, separator)
    table.insert(pt.widgets, move_files_box)
    table.insert(pt.widgets, move_files_options)
    table.insert(pt.widgets, sessioncode_header)
    table.insert(pt.widgets, jobcode_box)
    table.insert(pt.widgets, jobcode_display)
    table.insert(pt.widgets, button_start_capture)
    table.insert(pt.widgets, button_stop_capture)
 -- dd.dprint(pt_widgets)
end


local function create_session_code(image, sequence)

  local session = session_title.text .. " " .. session_counter_stringify()
  if prepend_date.value == true
    then session = os.date("%Y%m%d").. "_" .. session
  end

  if dt.preferences.read("Pseudo_Tether", "variable_substitution", "bool") == true then
    if pcall(ds.build_substitute_list, image, sequence, session) then
      session =  ds.substitute_list(session)
    else  dt.print("Error in value substitution")
    end
  end
  return session
end


local function import_to_library(file)
      local filetype = df.get_filetype(file)
      filetype = string.lower(filetype)
      if table_contains(ext_watched_extensions, filetype) == true and df.check_if_file_exists(file) then
        imported_image = dt.database.import(file)
        previous_image = current_image
        current_image = imported_image
        prev_img_id = curr_img_id
        curr_img_id = imported_image.id
        return imported_image
      end
end


local function sort_in_library(imported_image, sequence)

  if df.check_if_file_exists(destination_directory.value) == true then

    local session_code = create_session_code(imported_image, sequence)
    local final_directory = destination_directory.value .. "/" .. session_code

    local  film_already_exists = search_film(final_directory)
    print(film_already_exists)

    if film_already_exists == 0 then

      dt.print("Create new film: " .. session_code)
      if df.check_if_file_exists(final_directory) == false then dt.print (final_directory .." not found, creating directory") df.mkdir(df.sanitize_filename(final_directory))
      if df.check_if_file_exists(final_directory) == false then dt.print("failed creating " .. final_directory .. "aborting move") return end end
      local new_film = dt.films.new(final_directory)
      dt.database.move_image(new_film, imported_image)
      refresh_collection()

    else

      dt.print("Adding Image to " .. session_code)
      dt.database.move_image(imported_image, dt.films[film_already_exists])
      refresh_collection()
      print ("image added to film ".. final_directory)
      print ("image moved to" .. dt.films[film_already_exists].path)

     end
  end
end
local function find_style(string) for i in ipairs(dt.styles) do
      if      dt.styles[i].name == string then
      print (dt.styles[i].name .. i)
    return i
    end
     end
end
local function propagate_history_2()

   if not(previous_image==nil or current_image== nil) then
    local temp_style = empty_style
    temp_style = dt.styles.create(previous_image, "temp_style", "temp_style")
    dt.styles.apply(temp_style, current_image)
    local style_index = find_style("temp_style")
    dt.styles.delete(dt.styles[style_index])
    print (style_index .. dt.styles[style_index].name)
    for i in ipairs(dt.styles)do
      if dt.styles[i].name == "temp_style" then
        print ("not deleted")
      end
    end
  end
    print("did i get ya?")
    refresh_collection()
  end

local function propagate_history()
  if not(previous_image==nil or current_image== nil) then
    print("action")
    local empty_sel = {}
    local current_sel = {current_image}
    print (current_image.filename)
    print(current_sel[1].filename)
    local prev_sel = {previous_image}
    print (previous_image.filename)
    print (prev_sel[1].filename)
    local prev_view = dt.gui.current_view().id
    dt.gui.action("global/switch views/lighttable", 1,000)
    sleep (200)
    dt.gui.selection({})
    dt.gui.selection({previous_image})
    refresh_collection()
    sleep(500)
    dt.gui.action("lib/copy_history/copy", "", "activate", 1,000)
    sleep(500)
    refresh_collection()
    dt.gui.selection({})
    dt.gui.selection({imported_image})

    refresh_collection()
    sleep(500)
    dt.gui.action("lib/copy_history/paste", "", "activate", 1,000)
    sleep(500)
    dt.gui.action("global/switch views/darkroom", 1,000)
    refresh_collection()
  end

  dt.gui.views.darkroom.display_image(imported_image)
end

local function find_tag() local return_tag = dt.tags.find("info|capture session|" .. session_counter_stringify()) dd.dprint(return_tag) return return_tag end

local function handle_read(watch_dir)
    while watch_active==true do

    local inotify_events = handle:read()

    for i,ev in ipairs(inotify_events) do
      if ev["mask"] == inotify.IN_MOVED_TO or ev["mask"] == inotify.IN_CREATE then
        local ingest_file = watch_dir ..'/'.. ev.name
        if df.check_if_file_exists(ingest_file) then

          local imported_image = import_to_library(ingest_file)
          if move_files.value == true then
            sort_in_library(imported_image, i)
          end

          if dt.preferences.read("Pseudo_Tether", "create_session_counter_tag", "bool") == true then local tag = dt.tags.create("Info|Capture Session|" .. session_counter_stringify()) dd.dprint(tag) dt.tags.attach(tag, imported_image)  end

          if propagate_history_button.value == true then
            propagate_history_2()
          end
        end
      end
      end
  sleep(500)
  end

end
local function capture_session(watch_dir)

  watch_active= true
  local wd = handle:addwatch(watch_dir, inotify.IN_CREATE, inotify.IN_MOVED_TO, inotify.IN_MOVE)
  local dt_message = "Files added to '" .. watch_dir .. "' will be imported"
  if move_files.value == true then dt_message = dt_message ..  " and moved to '" .. destination_directory.value .. "/" end -- .. jobcode() .. "'"end
  dt.print("Capture Session Started")
  dt.print(dt_message)
  
  handle_read(watch_dir)

  handle:rmwatch(wd)

end
local function start_capture()

    local watch_dir = ingest_directory.value
    if watch_dir == nil or watch_dir =="" then
      dt.print("No import directory specified. Please choose a directory to import from")
      return

    end
    if prepend_date.value == true then jobcode_display.label =os.date("%Y%m%d") .. "_" .. session_title.text .. " " .. session_counter_stringify() else jobcode_display.label = session_title.text ..session_counter_stringify() end
    toggle_capture_buttons(false)
    toggle_move_files_options(false)

    print(watch_dir)
    capture_session(watch_dir)
    print('done_daniel')
end

local function stop_capture()

    dt.print("Capture Session Ended")
    watch_active = false
    button_stop_capture.visible =false
    button_start_capture.visible =true
    jobcode_display.visible =false
    watch_folder_box.visible = true
    dt.preferences.write("Pseudo_Tether", "session_counter", "integer", dt.preferences.read("Pseudo_Tether", "session_counter", "integer")+1)
    dt.preferences.write("Pseudo_Tether", "session_title", "string", session_title.text)
    session_counter.label = session_counter_stringify()
    move_files_box.visible=true
    toggle_move_files_options(true)
   --local dump1 = dt.debug.dump(dt.gui.libs.copy_history)

end

--  local button3 = dt.new_widget("button")
 --     {label = "handle close"
  --}

register_prefs()
ext_watched_extensions = ext_watchlist()
init_gui(start_capture,stop_capture)

--print("move_files.value = " .. move_files.value)
-- pack the widgets in a table for loading in the moidule

-- table.insert(button3)
--table.insert(pt.widgets, combobox)
--table.insert(pt.widgets, ingest_directory_box)

--table.insert(pt.widgets, separator)

--table.insert(pt.widgets, move_files)
--table.insert(pt.widgets, destination_directory_box)
-- table.insert(pt.widgets, jobcode_box)
--table.insert(pt.widgets, move_files_options)
--table.insert(pt.widgets, label)

-- ... and tell dt about it all

if dt.gui.current_view().id == "lighttable" then -- make sure we are in lighttable view
  install_module()  -- register the lib
else
  if not pt.event_registered then -- if we are not in lighttable view then register an event to signal when we might be
    -- https://www.darktable.org/lua-api/index.html#darktable_register_event
    dt.register_event(
      "mdouleExample", "view-changed",  -- we want to be informed when the view changes
      function(event, old_view, new_view)
        if new_view.name == "lighttable" and old_view.name == "darkroom" then  -- if the view changes from darkroom to lighttable
          install_module()  -- register the lib
         end
      end
    )
    pt.event_registered = true  --  keep track of whether we have an event handler installed
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
