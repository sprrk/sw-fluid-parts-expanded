local FILTERS = require("../lib/fluid_filters").ALL_FLUIDS + require("../lib/fluid_filters").ALL_GASES

local FLUID_SLOT_A = 0
local FLUID_SLOT_B = 1
local FLOW_OUTPUT_SLOT = 0
local FLUID_VOLUME = 0
local FLUID_VOLUME_SIZE = 1.0 -- Liters
local FLUID_TICK_TO_LITER_SECOND_RATIO = 600 -- NOTE: This is only valid for liquids.

local initialized = false

local function initialize()
	component.fluidContentsSetCapacity(FLUID_VOLUME, FLUID_VOLUME_SIZE)
	initialized = true
end

function onTick(tick_time)
	if not initialized then
		initialize()
	end

	component.slotFluidResolveFlowToSlot(
		FLUID_SLOT_A,
		FLUID_SLOT_B,
		0, -- pump_pressure
		1, -- flow_factor
		false,
		FILTERS,
		FLUID_VOLUME
	)

	local amount, amount_get_ok = component.fluidContentsGetVolume(FLUID_VOLUME)
	if amount_get_ok then
		component.setOutputLogicSlotFloat(FLOW_OUTPUT_SLOT, (amount / tick_time) * FLUID_TICK_TO_LITER_SECOND_RATIO)
	end
end
