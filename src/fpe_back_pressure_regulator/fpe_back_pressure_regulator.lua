local FILTERS = require("../lib/fluid_filters").ALL_FLUIDS + require("../lib/fluid_filters").ALL_GASES

-- Component details:
-- Type: back-pressure regulator
-- Regulates input pressure by moving fluid from input to output until
-- target pressure is achieved, or pressure is equalized.

local PRESSURE_SCALE = 60
local FLUID_VOLUME_SIZE = 6.0 -- Liters

-- Slot definitions
local FLUID_SLOT_A = 0
local FLUID_SLOT_B = 1
local TARGET_PRESSURE_SLOT = 0

-- Fluid volume indices
local FLUID_VOLUME_A = 0
local FLUID_VOLUME_B = 1

local initialized = false

---@param value number
---@param min number
---@param max number
---@return number
local function clamp(value, min, max)
	return value < min and min or value > max and max or value
end

---@param slot integer
---@param volume integer
local function resolveFluidVolumeFlow(slot, volume)
	component.slotFluidResolveFlow(
		slot,
		volume,
		0.0, -- pump_pressure
		1.0, -- flow_factor
		false, -- is_one_way_in_to_slot
		false, -- is_one_way_out_of_slot
		FILTERS,
		-1 -- index_fluid_contents_transfer
	)
end

local function initialize()
	component.fluidContentsSetCapacity(FLUID_VOLUME_A, FLUID_VOLUME_SIZE)
	component.fluidContentsSetCapacity(FLUID_VOLUME_B, FLUID_VOLUME_SIZE)
	initialized = true
end

function onTick(_)
	if not initialized then
		initialize()
	end

	resolveFluidVolumeFlow(FLUID_SLOT_A, FLUID_VOLUME_A)
	resolveFluidVolumeFlow(FLUID_SLOT_B, FLUID_VOLUME_B)

	local target_pressure = clamp(component.getInputLogicSlotFloat(TARGET_PRESSURE_SLOT), 0, PRESSURE_SCALE)
	if clamp(component.fluidContentsGetPressure(FLUID_VOLUME_A), 0, PRESSURE_SCALE) <= target_pressure then
		-- Exit early; already at or below target
		return
	end

	local amount_a = component.fluidContentsGetVolume(FLUID_VOLUME_A)
	if amount_a <= 0 then
		-- Exit early; no fluid available to move
		return
	end

	local amount_b = component.fluidContentsGetVolume(FLUID_VOLUME_B)
	if amount_b >= amount_a then
		-- Exit early; regulator is one-way
		return
	end

	local move_amount =
		math.min(amount_a - (target_pressure / PRESSURE_SCALE) * FLUID_VOLUME_SIZE, FLUID_VOLUME_SIZE - amount_b)

	if move_amount > 0 then
		component.fluidContentsTransferVolume(FLUID_VOLUME_A, FLUID_VOLUME_B, move_amount)
	end
end
