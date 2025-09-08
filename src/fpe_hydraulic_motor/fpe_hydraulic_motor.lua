local MASS = 1.0
local RPS_FACTOR = 100

local RPS_SLOT = 0
local FLUID_SLOT_A = 0
local FLUID_SLOT_B = 1
local DATA_OUT_SLOT = 0

local FLUID_VOLUME_A = 0
local FLUID_VOLUME_B = 1

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
		-- FILTERS_FLUIDS,
		FILTERS_FLUIDS + FILTERS_GASES,
		-1 -- index_fluid_contents_transfer
	)
end

function onTick(_)
	component.fluidContentsSetCapacity(FLUID_VOLUME_A, 1)
	component.fluidContentsSetCapacity(FLUID_VOLUME_B, 1)

	-- Resolve the fluid flow for the volumes connected to the slots
	resolveFluidVolumeFlow(FLUID_SLOT_A, FLUID_VOLUME_A)
	resolveFluidVolumeFlow(FLUID_SLOT_B, FLUID_VOLUME_B)

	local pressure_a, _ = component.fluidContentsGetPressure(FLUID_VOLUME_A)
	local pressure_b, _ = component.fluidContentsGetPressure(FLUID_VOLUME_B)
	local volume_a, _ = component.fluidContentsGetVolume(FLUID_VOLUME_A)
	local volume_b, _ = component.fluidContentsGetVolume(FLUID_VOLUME_B)

	local pressure_diff = 0
	local direction = 0
	local amount = 0

	-- Get the current RPS
	local current_rps, _ = component.slotTorqueApplyMomentum(RPS_SLOT, 0, 0)

	-- Calculate the fluid amount to transfer between the two volumes
	amount = (volume_a - volume_b) / 2

	-- Multipy by pressure diff to add additional force
	pressure_diff = pressure_a - pressure_b
	amount = amount * pressure_diff

	-- Adjust the amount based on the RPS to apply backforce
	amount = amount - current_rps / RPS_FACTOR -- TODO: Fix runaway

	-- Apply the fluid transfer
	if amount > 0 then
		direction = 1
		component.fluidContentsTransferVolume(FLUID_VOLUME_A, FLUID_VOLUME_B, amount)
	elseif amount < 0 then
		direction = -1
		component.fluidContentsTransferVolume(FLUID_VOLUME_B, FLUID_VOLUME_A, -amount)
	end

	-- Calculate the 'mass' / torque, based on the pressure
	local mass = MASS * (((pressure_a / 60) + (pressure_b / 60)) / 2)

	-- Update the torque slot output
	local target_rps = amount * direction * RPS_FACTOR
	local rps_after, _ = component.slotTorqueApplyMomentum(RPS_SLOT, mass, target_rps)

	component.setOutputLogicSlotComposite(DATA_OUT_SLOT, {
		bool_values = {},
		float_values = {
			[1] = 0,
			[2] = 0,
			[3] = 0,
			[4] = rps_after,
			[5] = 0,
			[6] = pressure_diff,
		},
	})
end
