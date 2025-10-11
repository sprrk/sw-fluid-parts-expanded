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
local FLUID_TICK_TO_LITER_SECOND_RATIO = 600
-- NOTE: In another test setup, the FLUID_TICK_TO_LITER_SECOND_RATIO was 1186,
--       no clue why, though.

-- Slot definitions
local FLUID_SLOT_A = 1
local FLUID_SLOT_B = 0
local SETTINGS_SLOT = 0
local FLOW_OUTPUT_SLOT = 0
local ODOMETER_OUTPUT_SLOT = 1

-- Fluid volume indices
local FLUID_VOLUME_A = 0

-- Odometer configuration
local COUNTER_WHEEL_Y = 0.075
local COUNTER_WHEEL_Z = 0.06
local ODOMETER_PERSISTENCE_ID = "odometer"
local WHEEL_RESOLUTION_DEG = 9
local DEGREES_PER_DIGIT = 36
local WHEEL_COUNT = 5
local WHEEL_POSITIONS = { -0.03, -0.015, 0, 0.015, 0.03 } -- From right (0.1 L) to left (1000 L)
local WHEEL_MESH_INDICES = { 2, 1, 1, 1, 1 } -- White wheel first, then black wheels

local initialized = false
local flow = 0
local settings_read_ticks = 0
local odometer_liters = 0.0 -- Total volume passed since last reset

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

local WHEEL_CACHE = {}
local function rebuildWheelCache()
	for wheel_index = 1, WHEEL_COUNT do
		WHEEL_CACHE[wheel_index] = {}
		-- 0° … 360° to cover all 10 digits (0-9)
		local steps = math.floor(360 / WHEEL_RESOLUTION_DEG) + 1
		for step = 0, steps - 1 do
			local angle_deg = step * WHEEL_RESOLUTION_DEG
			local angle_rad = math.rad(angle_deg)
			local rot = matrix.rotationX(angle_rad)
			local pos = matrix.translation(WHEEL_POSITIONS[wheel_index], COUNTER_WHEEL_Y, COUNTER_WHEEL_Z)
			WHEEL_CACHE[wheel_index][step] = matrix.multiply(pos, rot)
		end
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
		rebuildWheelCache()
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

	-- Update odometer
	odometer_liters = odometer_liters + amount
	if composite.bool_values[2] then
		odometer_liters = 0.0
	end

	component.setOutputLogicSlotFloat(FLOW_OUTPUT_SLOT, flow)
	component.setOutputLogicSlotFloat(ODOMETER_OUTPUT_SLOT, odometer_liters)

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

	-- Render odometer wheels
	local value = odometer_liters
	for wheel_index = 1, WHEEL_COUNT do
		local scale = 10 ^ (wheel_index - 2) -- 0.1, 1, 10, 100, 1000
		local digit = (value / scale) % 10 -- 0.0 .. 9.999
		local step_f = (digit * DEGREES_PER_DIGIT) / WHEEL_RESOLUTION_DEG
		local step = math.floor(step_f + 0.5) % #WHEEL_CACHE[wheel_index]
		local mesh_index = WHEEL_MESH_INDICES[wheel_index]
		if mesh_index == 1 then
			component.renderMesh1(WHEEL_CACHE[wheel_index][step])
		else
			component.renderMesh2(WHEEL_CACHE[wheel_index][step])
		end
	end
end

function onParse()
	local value_out, success = parser.parseNumber(ODOMETER_PERSISTENCE_ID, odometer_liters)
	if success and value_out then
		odometer_liters = value_out
	end
end
