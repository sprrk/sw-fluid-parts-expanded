local FILTERS = require("../lib/fluid_filters").ALL_FLUIDS + require("../lib/fluid_filters").ALL_GASES

-- Component details:
-- Type: pressure gauge
-- An analog pressure gauge.

local SETTINGS_SLOT = 0
local PRESSURE_OUTPUT_SLOT = 0
local FLUID_SLOT_A = 0
local FLUID_VOLUME_A = 0
local FLUID_VOLUME_SIZE = 0.1

local SETTINGS_READ_INTERVAL = 60
local NEEDLE_SWEEP_ANGLE_DEG = 270
local MAX_PRESSURE = 60
local SEGMENTS = 24
local DEGREES_PER_SEGMENT = NEEDLE_SWEEP_ANGLE_DEG / SEGMENTS
local PRESSURE_QUANTIZATION = MAX_PRESSURE / NEEDLE_SWEEP_ANGLE_DEG
local MAX_CACHE_INDEX = math.floor(MAX_PRESSURE / PRESSURE_QUANTIZATION)

local initialized = false
local pressure = 0
local settings_read_ticks = 0

local PRESSURE_CACHE = {}

local SEGMENT_ROTATIONS = {}
for i = 1, SEGMENTS do
	local angle_deg = DEGREES_PER_SEGMENT * (i - 1)
	local angle_rad = math.rad(-NEEDLE_SWEEP_ANGLE_DEG * 0.5 + angle_deg)
	SEGMENT_ROTATIONS[i] = matrix.rotationY(angle_rad)
end

---@class BandRange
---@field first integer|nil
---@field last integer|nil

---@type table<"green"|"red_1"|"red_2", BandRange>
local band_cache = {
	green = { first = nil, last = nil },
	red_1 = { first = nil, last = nil },
	red_2 = { first = nil, last = nil },
}

---@class PressureGaugeSettings
---@field pressure_range_start number
---@field pressure_range_end number
---@field green_start number
---@field green_end number
---@field red_1_start number
---@field red_1_end number
---@field red_2_start number
---@field red_2_end number

---@type PressureGaugeSettings
local settings = {
	pressure_range_start = 0,
	pressure_range_end = 60,
	green_start = 0,
	green_end = 0,
	red_1_start = 0,
	red_1_end = 0,
	red_2_start = 0,
	red_2_end = 0,
}

local function copy(t)
	local result = {}
	for k, v in pairs(t) do
		result[k] = v
	end
	return result
end

---@type PressureGaugeSettings
local old_settings = copy(settings)

---@param value number
---@param min number
---@param max number
---@return number
local function clamp(value, min, max)
	return math.max(min, math.min(max, value))
end

---@param float_values table
---@param index integer
---@param min number
---@param max number
---@param default number
---@return number
local function parseSetting(float_values, index, min, max, default)
	local value = float_values[index]
	if value then
		if default ~= 0 and value == 0 then
			return default
		else
			return clamp(value, min, max)
		end
	else
		return default
	end
end

---@param p number
---@return number
local function pressureToAngle(p)
	local span = settings.pressure_range_end - settings.pressure_range_start
	if span <= 0 then -- zero-width range: park needle at start
		return math.rad(-NEEDLE_SWEEP_ANGLE_DEG * 0.5)
	end
	local t = clamp((p - settings.pressure_range_start) / span, 0, 1)
	return math.rad(-NEEDLE_SWEEP_ANGLE_DEG * 0.5 + t * NEEDLE_SWEEP_ANGLE_DEG)
end

local function rebuildPressureCache()
	for i = 0, MAX_CACHE_INDEX do
		local p = PRESSURE_QUANTIZATION * i
		local angle = pressureToAngle(p)
		PRESSURE_CACHE[i] = matrix.rotationY(angle)
	end
end

---@param p number
---@return number|nil
local function pressureToSegment(p)
	local span = settings.pressure_range_end - settings.pressure_range_start
	if span <= 0 then
		return nil
	end
	local t = clamp((p - settings.pressure_range_start) / span, 0, 1)
	return clamp(math.floor(t * SEGMENTS) + 1, 0, SEGMENTS)
end

---@param render_function fun(m: table)
local function renderSegments(render_function, cache)
	if cache.first ~= nil and cache.last ~= nil then
		for i = cache.first, cache.last do
			local rotation = SEGMENT_ROTATIONS[i]
			if rotation then
				render_function(rotation)
			end
		end
	end
end

---@param composite_float_values table
local function readSettings(composite_float_values)
	settings.pressure_range_start = parseSetting(composite_float_values, 2, 0, MAX_PRESSURE, 0)
	settings.pressure_range_end = parseSetting(composite_float_values, 3, 0, MAX_PRESSURE, MAX_PRESSURE)
	settings.green_start = parseSetting(composite_float_values, 4, 0, MAX_PRESSURE, 0)
	settings.green_end = parseSetting(composite_float_values, 5, 0, MAX_PRESSURE, 0)
	settings.red_1_start = parseSetting(composite_float_values, 6, 0, MAX_PRESSURE, 0)
	settings.red_1_end = parseSetting(composite_float_values, 7, 0, MAX_PRESSURE, 0)
	settings.red_2_start = parseSetting(composite_float_values, 8, 0, MAX_PRESSURE, 0)
	settings.red_2_end = parseSetting(composite_float_values, 9, 0, MAX_PRESSURE, 0)

	-- Did any band setting change?
	if
		settings.green_start == old_settings.green_start
		and settings.green_end == old_settings.green_end
		and settings.red_1_start == old_settings.red_1_start
		and settings.red_1_end == old_settings.red_1_end
		and settings.red_2_start == old_settings.red_2_start
		and settings.red_2_end == old_settings.red_2_end
		and settings.pressure_range_start == old_settings.pressure_range_start
		and settings.pressure_range_end == old_settings.pressure_range_end
	then
		return -- Nothing changed, bail out quickly
	end

	-- Build ranges once per settings update
	band_cache.green.first = pressureToSegment(settings.green_start)
	band_cache.green.last = pressureToSegment(math.min(settings.green_end, settings.pressure_range_end))

	band_cache.red_1.first = pressureToSegment(settings.red_1_start)
	band_cache.red_1.last = pressureToSegment(math.min(settings.red_1_end, settings.pressure_range_end))

	band_cache.red_2.first = pressureToSegment(settings.red_2_start)
	band_cache.red_2.last = pressureToSegment(math.min(settings.red_2_end, settings.pressure_range_end))

	-- Rebuild cache if pressure range changed
	if
		settings.pressure_range_start ~= old_settings.pressure_range_start
		or settings.pressure_range_end ~= old_settings.pressure_range_end
	then
		rebuildPressureCache()
	end

	-- Remember for next comparison
	for k, v in pairs(settings) do
		old_settings[k] = v
	end
end

function onTick(_)
	local composite, _ = component.getInputLogicSlotComposite(SETTINGS_SLOT)
	local composite_float_values = composite.float_values

	if not initialized then
		component.fluidContentsSetCapacity(FLUID_VOLUME_A, FLUID_VOLUME_SIZE)
		readSettings(composite_float_values)
		rebuildPressureCache()
	end

	-- Move fluid in/out of the buffer volume
	component.slotFluidResolveFlow(
		FLUID_SLOT_A,
		FLUID_VOLUME_A,
		0.0, -- pump_pressure
		1.0, -- flow_factor
		false, -- is_one_way_in_to_slot
		false, -- is_one_way_out_of_slot
		FILTERS,
		-1 -- index_fluid_contents_transfer
	)

	-- Read the pressure value
	local _pressure, pressure_get_ok = 0, false
	if composite_float_values[1] == 0 then
		-- Pressure reading via fluid slot
		_pressure, pressure_get_ok = component.fluidContentsGetPressure(FLUID_VOLUME_A)
	else
		-- Pressure value override via composite
		_pressure, pressure_get_ok = composite_float_values[1], true
	end
	pressure = pressure_get_ok and clamp(_pressure, 0, MAX_PRESSURE) or 0

	-- Read settings every few ticks
	settings_read_ticks = (settings_read_ticks + 1) % SETTINGS_READ_INTERVAL
	if settings_read_ticks == 0 then
		readSettings(composite_float_values)
	end

	component.setOutputLogicSlotFloat(PRESSURE_OUTPUT_SLOT, _pressure)

	initialized = true
end

function onRender()
	if not initialized then
		return
	end

	-- Needle
	local index = math.floor(pressure / PRESSURE_QUANTIZATION + 0.5)
	component.renderMesh0(PRESSURE_CACHE[index])

	-- Green and red arcs
	renderSegments(component.renderMesh1, band_cache.green)
	renderSegments(component.renderMesh2, band_cache.red_1)
	renderSegments(component.renderMesh2, band_cache.red_2)
end
