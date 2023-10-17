obs = obslua

-- Returns the description displayed in the Scripts window
function script_description()
  return [[Timer Fade Filter
  This Lua script adds a video filter named Timer Fade. The filter can be added
  to a video source to have it fade in opacity at certain times of the day.]]
end

-- Called on script startup
function script_load(settings)
  obs.obs_register_source(source_info)
  obs.timer_add(update_sources, 1000)
end

-- List of active sources we need to update on a timer
active_sources = {}

function update_sources()
  for _, source_data in ipairs(active_sources) do
    -- Update opacity of this source
    local date = os.date("*t")
    local frac_hour = date.hour + (date.min / 60) + (date.sec / 3600)
    
    -- Opacity calculation based on current time and parameters
    if frac_hour < source_data.transition_in_start then
      source_data.opacity = 0
    elseif frac_hour < source_data.transition_in_end then
      source_data.opacity = (frac_hour - source_data.transition_in_start) / (source_data.transition_in_end - source_data.transition_in_start)
    elseif frac_hour < source_data.transition_out_start then
      source_data.opacity = 1
    elseif frac_hour < source_data.transition_out_end then
      source_data.opacity = 1 - ((frac_hour - source_data.transition_out_start) / (source_data.transition_out_end - source_data.transition_out_start))
    else
      source_data.opacity = 0
    end
  end
end

-- Definition of the global variable containing the source_info structure
source_info = {}
source_info.id = 'filter-timer-fader'           -- Unique string identifier of the source type
source_info.type = obs.OBS_SOURCE_TYPE_FILTER   -- INPUT or FILTER or TRANSITION
source_info.output_flags = obs.OBS_SOURCE_VIDEO -- Combination of VIDEO/AUDIO/ASYNC/etc

-- Returns the name displayed in the list of filters
source_info.get_name = function()
  return "Timer Fade"
end

-- Creates the implementation data for the source
source_info.create = function(settings, source)

  -- Initializes the custom data table
  local data = {}
  data.source = source -- Keeps a reference to this filter as a source object
  data.width = 1       -- Dummy value during initialization phase
  data.height = 1      -- Dummy value during initialization phase

  -- Compiles the effect
  obs.obs_enter_graphics()
  local effect_file_path = script_path() .. 'filter-timer-fader.effect.hlsl'
  data.effect = obs.gs_effect_create_from_file(effect_file_path, nil)
  obs.obs_leave_graphics()

  -- Calls the destroy function if the effect was not compiled properly
  if data.effect == nil then
    obs.blog(obs.LOG_ERROR, "Effect compilation failed for " .. effect_file_path)
    source_info.destroy(data)
    return nil
  end

  -- Retrieves the shader uniform variables
  data.params = {}
  data.params.width = obs.gs_effect_get_param_by_name(data.effect, "width")
  data.params.height = obs.gs_effect_get_param_by_name(data.effect, "height")
  data.params.opacity = obs.gs_effect_get_param_by_name(data.effect, "opacity")
  
  -- Index for removal later
  data.idx = table.getn(active_sources) + 1;

  -- Calls update to initialize the rest of the properties-managed settings
  source_info.update(data, settings)

  -- Register this source to be updated
  table.insert(active_sources, data)
  
  return data
end

-- Destroys and release resources linked to the custom data
source_info.destroy = function(data)
  if data.effect ~= nil then
    obs.obs_enter_graphics()
    obs.gs_effect_destroy(data.effect)
    data.effect = nil
    obs.obs_leave_graphics()
    table.remove(active_sources, data.idx)
  end
end

-- Returns the width of the source
source_info.get_width = function(data)
  return data.width
end

-- Returns the height of the source
source_info.get_height = function(data)
  return data.height
end

-- Called when rendering the source with the graphics subsystem
source_info.video_render = function(data)
  local parent = obs.obs_filter_get_parent(data.source)
  data.width = obs.obs_source_get_base_width(parent)
  data.height = obs.obs_source_get_base_height(parent)

  obs.obs_source_process_filter_begin(data.source, obs.GS_RGBA, obs.OBS_NO_DIRECT_RENDERING)
  -- Effect parameters initialization goes here
  obs.gs_effect_set_int(data.params.width, data.width)
  obs.gs_effect_set_int(data.params.height, data.height)
  obs.gs_effect_set_float(data.params.opacity, data.opacity)
  
  local date = os.date()
  
  obs.obs_source_process_filter_end(data.source, data.effect, data.width, data.height)
end

-- Sets the default settings for this source
source_info.get_defaults = function(settings)
  obs.obs_data_set_default_double(settings, "transition_in_start", 0.0)
  obs.obs_data_set_default_double(settings, "transition_in_end", 0.0)
  obs.obs_data_set_default_double(settings, "transition_out_start", 0.0)
  obs.obs_data_set_default_double(settings, "transition_out_end", 0.0)
end

-- Gets the property information of this source
source_info.get_properties = function(data)
  local props = obs.obs_properties_create()
  obs.obs_properties_add_float_slider(props, "transition_in_start", "Transition In Start (hour)", 0.0, 24.0, 0.5)
  obs.obs_properties_add_float_slider(props, "transition_in_end", "Transition In End (hour)", 0.0, 24.0, 0.5)
  obs.obs_properties_add_float_slider(props, "transition_out_start", "Transition Out Start (hour)", 0.0, 24.0, 0.5)
  obs.obs_properties_add_float_slider(props, "transition_out_end", "Transition Out End (hour)", 0.0, 24.0, 0.5)

  return props
end

-- Updates the internal data for this source upon settings change
source_info.update = function(data, settings)
  data.transition_in_start = obs.obs_data_get_double(settings, "transition_in_start")
  data.transition_in_end = obs.obs_data_get_double(settings, "transition_in_end")
  data.transition_out_start = obs.obs_data_get_double(settings, "transition_out_start")
  data.transition_out_end = obs.obs_data_get_double(settings, "transition_out_end")
  data.opacity = 1
end