local FILTERS = require("../lib/fluid_filters").ALL
local FLUID_TYPES = require("../lib/fluid_types")

local FLUID_SLOT_A = 0
local FLUID_SLOT_B = 1
local FLOW_OUTPUT_SLOT = 0
local DATA_OUTPUT_SLOT = 0
local FLUID_VOLUME = 0
local FLUID_VOLUME_SIZE = 1.0 -- Liters

-- Conversion ratios: Fluid units per tick -> liter per second
local LIQUID_RATIO = 600
local GAS_RATIO = 36000 -- 10 * 60 * 60; 10 * ticks/sec * max atm?

local initialized = false

---@param fluid_type integer
---@param tick_time number
---@param ratio number
---@return number
local function getAmount(fluid_type, tick_time, ratio)
	return ((component.fluidContentsGetFluidTypeVolume(FLUID_VOLUME, fluid_type) or 0) / tick_time) * ratio
end

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

	local water = getAmount(FLUID_TYPES.WATER, tick_time, LIQUID_RATIO)
	local diesel = getAmount(FLUID_TYPES.DIESEL, tick_time, LIQUID_RATIO)
	local jet = getAmount(FLUID_TYPES.JET, tick_time, LIQUID_RATIO)
	local air = getAmount(FLUID_TYPES.AIR, tick_time, GAS_RATIO)
	local co2 = getAmount(FLUID_TYPES.CO2, tick_time, GAS_RATIO)
	local oil = getAmount(FLUID_TYPES.OIL, tick_time, LIQUID_RATIO)
	local sea_water = getAmount(FLUID_TYPES.SEA_WATER, tick_time, LIQUID_RATIO)
	local steam = getAmount(FLUID_TYPES.STEAM, tick_time, GAS_RATIO)
	local slurry = getAmount(FLUID_TYPES.SLURRY, tick_time, LIQUID_RATIO)
	local saturated_slurry = getAmount(FLUID_TYPES.SATURATED_SLURRY, tick_time, LIQUID_RATIO)
	local o2 = getAmount(FLUID_TYPES.O2, tick_time, GAS_RATIO)
	local n2 = getAmount(FLUID_TYPES.N2, tick_time, GAS_RATIO)
	local h2 = getAmount(FLUID_TYPES.H2, tick_time, GAS_RATIO)

	local total_liquid = water + diesel + jet + oil + sea_water + slurry + saturated_slurry
	local total_gas = air + co2 + steam + o2 + n2 + h2
	local total = total_liquid + total_gas

	component.setOutputLogicSlotFloat(FLOW_OUTPUT_SLOT, total)
	component.setOutputLogicSlotComposite(DATA_OUTPUT_SLOT, {
		float_values = {
			[1] = water,
			[2] = diesel,
			[3] = jet,
			[4] = air,
			[5] = co2,
			[6] = oil,
			[7] = sea_water,
			[8] = steam,
			[9] = slurry,
			[10] = saturated_slurry,
			[11] = o2,
			[12] = n2,
			[13] = h2,
			[30] = total_liquid,
			[31] = total_gas,
			[32] = total,
		},
	})
end
