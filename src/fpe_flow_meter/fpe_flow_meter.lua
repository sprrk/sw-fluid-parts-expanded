local FILTERS = require("../lib/fluid_filters").ALL_FLUIDS + require("../lib/fluid_filters").ALL_GASES

-- Component details:
-- Type: Flow meter
-- Measures and displays fluid flow.

local SETTINGS_READ_INTERVAL = 60
local NEEDLE_SWEEP_ANGLE_DEG = 270
local MAX_FLOW = 600
local ANGLE_RESOLUTION_DEG = 1.0
local MAX_CACHE_INDEX = math.floor(NEEDLE_SWEEP_ANGLE_DEG / ANGLE_RESOLUTION_DEG)
local FLUID_VOLUME_SIZE = 1.0 -- Liters
local FLUID_TICK_TO_LITER_SECOND_RATIO = 1186 -- No clue why, though.

-- Slot definitions
local FLUID_SLOT_A = 1
local FLUID_SLOT_B = 0
local SETTINGS_SLOT = 0
local FLOW_OUTPUT_SLOT = 0

-- Fluid volume indices
local FLUID_VOLUME_A = 2

local initialized = false
local flow = 0
local settings_read_ticks = 0

local FLOW_CACHE = {}

---@class FlowMeterSettings
---@field flow_range_start number
---@field flow_range_end number
---@field reverse boolean

---@type FlowMeterSettings
local settings = {
	flow_range_start = -600,
	flow_range_end = 600,
	reverse = false,
}

local function copy(t)
	local result = {}
	for k, v in pairs(t) do
		result[k] = v
	end
	return result
end

---@type FlowMeterSettings
local old_settings = copy(settings)

---@param value number
---@param min number
---@param max number
---@return number
local function clamp(value, min, max)
	return value < min and min or value > max and max or value
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

local function rebuildFlowCache()
	for i = 0, MAX_CACHE_INDEX do
		local angle_deg = i * ANGLE_RESOLUTION_DEG
		local angle_rad = math.rad(-NEEDLE_SWEEP_ANGLE_DEG * 0.5 + angle_deg)
		FLOW_CACHE[i] = matrix.rotationY(angle_rad)
	end
end

---@param composite table
local function readSettings(composite)
	settings.flow_range_start = parseSetting(composite.float_values, 1, -MAX_FLOW, MAX_FLOW, -MAX_FLOW)
	settings.flow_range_end = parseSetting(composite.float_values, 2, -MAX_FLOW, MAX_FLOW, MAX_FLOW)
	settings.reverse = composite.bool_values[1] or false

	-- Did any setting change?
	if
		settings.flow_range_start == old_settings.flow_range_start
		and settings.flow_range_end == old_settings.flow_range_end
		and settings.reverse == old_settings.reverse
	then
		return -- Nothing changed, bail out quickly
	end

	-- Rebuild cache if flow range changed
	if
		settings.flow_range_start ~= old_settings.flow_range_start
		or settings.flow_range_end ~= old_settings.flow_range_end
	then
		rebuildFlowCache()
	end

	-- Remember for next comparison
	for k, v in pairs(settings) do
		old_settings[k] = v
	end
end

local function initialize()
	component.fluidContentsSetCapacity(FLUID_VOLUME_A, FLUID_VOLUME_SIZE)
	initialized = true
end

function onTick(tick_time)
	local composite, _ = component.getInputLogicSlotComposite(SETTINGS_SLOT)

	if not initialized then
		initialize()
		readSettings(composite)
		rebuildFlowCache()
	end

	component.slotFluidResolveFlowToSlot(
		FLUID_SLOT_A,
		FLUID_SLOT_B,
		0, -- pump_pressure
		1, -- flow_factor
		false,
		FILTERS,
		FLUID_VOLUME_A
	)

	-- Read settings every few ticks
	settings_read_ticks = (settings_read_ticks + 1) % SETTINGS_READ_INTERVAL
	if settings_read_ticks == 0 then
		readSettings(composite)
	end

	-- Calculate the flow for the display
	local amount, _ = component.fluidContentsGetVolume(FLUID_VOLUME_A)
	flow = clamp((amount / tick_time) * FLUID_TICK_TO_LITER_SECOND_RATIO, -MAX_FLOW, MAX_FLOW)
	if settings.reverse then
		flow = -flow
	end

	component.setOutputLogicSlotFloat(FLOW_OUTPUT_SLOT, flow)

	initialized = true
end

function onRender()
	if not initialized then
		return
	end

	-- Map flow to angle range
	local span = settings.flow_range_end - settings.flow_range_start
	if span <= 0 then
		component.renderMesh0(FLOW_CACHE[0])
		return
	end

	local t = clamp((flow - settings.flow_range_start) / span, 0, 1)
	local index = math.floor(t * MAX_CACHE_INDEX + 0.5)
	component.renderMesh0(FLOW_CACHE[index])
end
