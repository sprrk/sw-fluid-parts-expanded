local FILTERS = require("../lib/fluid_filters").ALL_LIQUIDS + require("../lib/fluid_filters").ALL_GASES

-- Component details:
-- Type: compact pressure sensor

local FLUID_VOLUME_SIZE = 0.1 -- Liters
local FLUID_SLOT = 0
local PRESSURE_OUTPUT_SLOT = 0
local FLUID_VOLUME = 0

local initialized = false

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
	component.fluidContentsSetCapacity(FLUID_VOLUME, FLUID_VOLUME_SIZE)
	initialized = true
end

function onTick(_)
	if not initialized then
		initialize()
	end

	resolveFluidVolumeFlow(FLUID_SLOT, FLUID_VOLUME)

	local pressure = component.fluidContentsGetPressure(FLUID_VOLUME)

	component.setOutputLogicSlotFloat(PRESSURE_OUTPUT_SLOT, pressure)
end
