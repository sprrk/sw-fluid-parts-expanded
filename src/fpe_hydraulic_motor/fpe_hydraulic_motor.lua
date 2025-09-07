local MASS = 1.0
local RPS_SLOT = 0
local FLUID_SLOT_A = 0
local FLUID_SLOT_B = 1
local FLUID_VOLUME_A = 0
local FLUID_VOLUME_B = 1
local FLUID_VOLUME_PROBE = 2

local FILTERS_FLUIDS = (
	1 -- Water
	+ 2 -- Diesel
	+ 4 -- Jet
	+ 32 -- Oil
	+ 64 -- Sea water
	+ 256 -- Slurry
	+ 512 -- Sat. slurry
)
local FILTERS_GASES = (
	8 -- O2
	+ 16 -- CO2
	+ 128 -- Steam
	+ 1024 -- O2
	+ 2048 -- N2
	+ 4096 -- H2
)

local DATA_OUT_SLOT = 0

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
		FILTERS_FLUIDS,
		-1 -- index_fluid_contents_transfer
	)
end

---@param slot_a integer
---@param slot_b integer
---@param filters integer
---@param measure boolean
---@return number|nil, number|nil
local function resolveFluidFlow(slot_a, slot_b, filters, measure)
	local index_fluid_contents_transfer = -1
	if measure == true then
		index_fluid_contents_transfer = FLUID_VOLUME_PROBE
	end

	component.slotFluidResolveFlowToSlot(
		slot_a,
		slot_b,
		0.0, -- pump_pressure
		1.0, -- flow_factor
		false, -- is_one_way
		filters,
		index_fluid_contents_transfer
	)

	local pressure, volume = nil, nil
	if measure == true then
		pressure, _ = component.fluidContentsGetPressure(FLUID_VOLUME_PROBE)
		volume, _ = component.fluidContentsGetVolume(FLUID_VOLUME_PROBE)
		-- TODO: Check if we need to clear the FLUID_VOLUME_PROBE volume
	end
	return pressure, volume
end

-- local function initialize()
-- 	initialized = true
-- end

function onTick(_)
	component.fluidContentsSetCapacity(FLUID_VOLUME_A, 10)
	component.fluidContentsSetCapacity(FLUID_VOLUME_B, 10)
	component.fluidContentsSetCapacity(FLUID_VOLUME_PROBE, 10)
	-- if not initialized then
	-- 	initialize()
	-- end

	resolveFluidFlow(FLUID_SLOT_A, FLUID_SLOT_B, FILTERS_GASES, false)

	-- Resolve the fluid flow for the volumes connected to the slots
	-- resolveFluidVolumeFlow(FLUID_SLOT_A, FLUID_VOLUME_A)
	-- resolveFluidVolumeFlow(FLUID_SLOT_B, FLUID_VOLUME_B)

	-- TODO: Check if we even need to do this
	local pressure_a, _ = component.fluidContentsGetPressure(FLUID_VOLUME_A)
	local pressure_b, _ = component.fluidContentsGetPressure(FLUID_VOLUME_B)

	local pressure_diff = pressure_a - pressure_b

	-- Move fluids between the two slots and measure how much fluid was moved
	local volume, pressure = resolveFluidFlow(FLUID_SLOT_A, FLUID_SLOT_B, FILTERS_FLUIDS, true)

	local rps_before, rps_after, rps_delta = nil, nil, nil

	-- local rps_slot_connected = component.slotTorqueIsConnected(RPS_SLOT)
	--if not rps_slot_connected then
	--	-- TODO: Allow fluid to pass freely
	--	return
	--else
	-- TODO: This is naive, improve calculation
	local mass = MASS * math.abs(pressure or 0)
	rps_delta = volume or 0
	rps_before, _ = component.slotTorqueApplyMomentum(RPS_SLOT, 0, 0)
	rps_after, _ = component.slotTorqueApplyMomentum(RPS_SLOT, mass, rps_before + rps_delta)
	-- end

	component.setOutputLogicSlotComposite(DATA_OUT_SLOT, {
		bool_values = {},
		float_values = {
			[1] = pressure,
			[2] = volume,
			[3] = rps_before,
			[4] = rps_after,
			[5] = rps_delta,
			[6] = pressure_diff,
		},
	})
end
