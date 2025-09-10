local TICK_RATE = 62
local MASS = 6
local FLUID_VOLUME_SIZE = 1 -- Liters
local DISPLACEMENT = 0.01 -- L/rev (calibrated for 100 RPS @ 1 L/s)
local LEAK_COEFF = 0.001 -- L/s/atm (internal leakage)
local MAX_FLOW_LPS = 10.0 -- Configurable max flow
local MECHANICAL_EFF = 0.8 -- 80% mechanical efficiency

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

local initialized = false

---@param slot integer
---@param volume integer
local function resolveFluidVolumeFlow(slot, volume)
	component.slotFluidResolveFlow(slot, volume, 0.0, 1.0, false, false, FILTERS_FLUIDS + FILTERS_GASES, -1)
end

---@return number rps
local function getRPS()
	local rps, _ = component.slotTorqueApplyMomentum(RPS_SLOT, 0, 0)
	return rps
end

---@return number pressure_diff
local function getFluidPressureDiff()
	local pressure_a, _ = component.fluidContentsGetPressure(FLUID_VOLUME_A)
	local pressure_b, _ = component.fluidContentsGetPressure(FLUID_VOLUME_B)
	return pressure_a - pressure_b
end

---@param index integer
---@return number
local function getAmount(index)
	local amount, _ = component.fluidContentsGetVolume(index)
	return amount
end

---@param amount number
---@param vol_a number
---@param vol_b number
---@return number clamped Amount that respects volume limits
local function clampTransferAmount(amount, vol_a, vol_b)
	local max_a_to_b = math.min(vol_a, FLUID_VOLUME_SIZE - vol_b)
	local max_b_to_a = math.min(vol_b, FLUID_VOLUME_SIZE - vol_a)

	if amount > 0 then
		return math.min(amount, max_a_to_b)
	elseif amount < 0 then
		return math.max(amount, -max_b_to_a)
	end
	return 0
end

---@param amount number
local function transferFluid(amount)
	if amount > 0 then
		component.fluidContentsTransferVolume(FLUID_VOLUME_A, FLUID_VOLUME_B, amount)
	elseif amount < 0 then
		component.fluidContentsTransferVolume(FLUID_VOLUME_B, FLUID_VOLUME_A, -amount)
	end
end

---@param target_rps number
---@param force number
---@return number rps_after
local function setRPS(target_rps, force)
	local mass = MASS * force
	local rps_after, _ = component.slotTorqueApplyMomentum(RPS_SLOT, mass, target_rps)
	return rps_after
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

	-- Get current shaft state (critical for load detection)
	local current_rps = getRPS()
	local vol_a = getAmount(FLUID_VOLUME_A)
	local vol_b = getAmount(FLUID_VOLUME_B)
	local force = (vol_a + vol_b) / 2 -- Average fluid volume (0-1)
	local delta_P = getFluidPressureDiff() -- Pressure difference (atm)

	-- Calculate hydraulic torque effect (Nm equivalent)
	local hydraulic_torque = 0.1 * delta_P * MECHANICAL_EFF

	-- Convert torque to RPS adjustment (prevents slippage under load)
	local adjustment = 0
	if force > 0 then
		adjustment = hydraulic_torque / (6 * force)
	end
	local target_rps = current_rps + adjustment

	-- Apply hydraulic torque physics (key fix for responsiveness)
	local actual_rps = setRPS(target_rps, force)

	-- Calculate fluid flows (L/tick)
	local pump_flow = DISPLACEMENT * actual_rps / TICK_RATE
	local leakage_flow = LEAK_COEFF * delta_P / TICK_RATE
	local total_flow = pump_flow + leakage_flow

	-- Enforce max flow constraint (L/tick)
	local max_flow_per_tick = MAX_FLOW_LPS / TICK_RATE
	total_flow = math.max(-max_flow_per_tick, math.min(total_flow, max_flow_per_tick))

	-- Transfer fluid with physical clamping
	local clamped_flow = clampTransferAmount(total_flow, vol_a, vol_b)
	transferFluid(clamped_flow)

	-- Output diagnostic data (includes torque feedback)
	component.setOutputLogicSlotComposite(DATA_OUT_SLOT, {
		bool_values = {},
		float_values = {
			[1] = current_rps, -- RPS before adjustment
			[2] = actual_rps, -- Actual RPS after torque application
			[3] = delta_P, -- Pressure difference (atm)
			[4] = hydraulic_torque, -- Mechanical load estimate (torque units)
			[5] = pump_flow * TICK_RATE, -- Pump flow (L/s)
			[6] = leakage_flow * TICK_RATE, -- Leakage flow (L/s)
			[7] = total_flow * TICK_RATE, -- Total flow before clamp (L/s)
			[8] = clamped_flow * TICK_RATE, -- Actual transferred flow (L/s)
			[9] = vol_a, -- Volume A (L)
			[10] = vol_b, -- Volume B (L)
			[11] = force, -- Average fluid volume (0-1)
			[12] = adjustment, -- RPS adjustment amount
			[13] = target_rps, -- Target RPS
		},
	})
end
