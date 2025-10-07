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
	return math.max(min, math.min(max, value))
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

	-- Handle fluid flow through input and output slots
	resolveFluidVolumeFlow(FLUID_SLOT_A, FLUID_VOLUME_A)
	resolveFluidVolumeFlow(FLUID_SLOT_B, FLUID_VOLUME_B)

	-- Read target pressure from input slot
	local target_pressure, _ = component.getInputLogicSlotFloat(TARGET_PRESSURE_SLOT)
	target_pressure = clamp(target_pressure, 0, PRESSURE_SCALE)

	-- Current input pressure
	local pressure_a, _ = component.fluidContentsGetPressure(FLUID_VOLUME_A)
	pressure_a = clamp(pressure_a, 0, PRESSURE_SCALE)

	-- Exit early if already at or below target
	if pressure_a <= target_pressure then
		return
	end

	-- Get source fluid level
	local amount_a, _ = component.fluidContentsGetVolume(FLUID_VOLUME_A)
	if amount_a <= 0 then
		-- No fluid available to move
		return
	end

	local amount_b, _ = component.fluidContentsGetVolume(FLUID_VOLUME_B)

	if amount_b > amount_a then
		-- Exit early; regulator is one-way
		return
	end

	-- Estimate litres needed to reach target pressure
	local target_volume = (target_pressure / PRESSURE_SCALE) * FLUID_VOLUME_SIZE

	-- Compute how much we must actually move
	local move_amount = math.min(amount_a - target_volume, amount_a)
	if move_amount <= 0 then
		-- Already at or below target volume
		return
	end

	-- Cap by available space in volume B
	local space_b = FLUID_VOLUME_SIZE - amount_b
	move_amount = math.min(move_amount, space_b)
	if move_amount <= 0 then
		-- No room in output
		return
	end

	if move_amount > 0 then
		component.fluidContentsTransferVolume(FLUID_VOLUME_A, FLUID_VOLUME_B, move_amount)
	end
end
