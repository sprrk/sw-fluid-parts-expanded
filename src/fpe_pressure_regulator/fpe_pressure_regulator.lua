-- Component details:
-- Type: pressure regulator
-- Regulates output pressure by moving fluid from input to output until
-- target pressure is achieved, or pressure is equalized.

local FILTERS = require("../lib/fluid_filters").ALL_LIQUIDS + require("../lib/fluid_filters").ALL_GASES
local PID = require("../lib/pid")
local DotMatrixDisplay = require("../lib/dot_matrix_display")

local FLUID_VOLUME_SIZE_BUFFER = 2.0 -- Liters

local ELECTRIC_USAGE = 0.0005

local FLUID_SLOT_A = 0
local FLUID_SLOT_B = 1
local FLUID_SLOT_SENSING_LINE = 2

local COMPOSITE_SLOT = 0
local TARGET_PRESSURE_SLOT = 0
local ELECTRIC_SLOT = 0

local FLUID_VOLUME_BUFFER = 0

local initialized = false
local powered = false
local reverse = false
local fluidSlotIn = FLUID_SLOT_A
local fluidSlotOut = FLUID_SLOT_B

local targetPressure = 0
local prevTargetPressureInput = 0

---@return boolean
local function useEnergy()
	local chargeFactor, ok = component.slotElectricGetChargeFactor(ELECTRIC_SLOT)
	if ok and chargeFactor > ELECTRIC_USAGE then
		component.slotElectricRemoveCharge(ELECTRIC_SLOT, ELECTRIC_USAGE)
		return true
	else
		return false
	end
end

local function initialize()
	component.fluidContentsSetCapacity(FLUID_VOLUME_BUFFER, FLUID_VOLUME_SIZE_BUFFER)
	initialized = true
end

local display = DotMatrixDisplay({ x = 0, y = 0, z = 0 }, 4)

-- TODO: Make configurable via composite
local pid = PID({ Kp = 0.5, Ki = 1.0, Kd = 0.01, min = 0, max = 1, b = 0.3, c = 0, N = 20 })

---@param pressure number
---@return nil
local function run(pressure)
	local flowFactor = pid(targetPressure, pressure)

	component.slotFluidResolveFlowToSlot(
		fluidSlotIn,
		fluidSlotOut,
		0.0, -- pump_pressure
		flowFactor,
		true, -- is_one_way
		FILTERS,
		-1 -- index_fluid_contents_transfer
	)
end

function onTick(_)
	if not initialized then
		initialize()
	end

	local composite, compositeOk = component.getInputLogicSlotComposite(COMPOSITE_SLOT)

	if compositeOk then
		local floatValues = composite.float_values
		local boolValues = composite.bool_values

		display:setEnabled(not boolValues[1]) -- Disable display; enabled by default

		display:setFlipped(boolValues[2])

		if boolValues[3] then
			-- TODO: Switch to back-pressure regulator mode
		end

		local _reverse = boolValues[4]
		if _reverse ~= reverse then
			reverse = _reverse
			if reverse then
				fluidSlotIn = FLUID_SLOT_B
				fluidSlotOut = FLUID_SLOT_A
			else
				fluidSlotIn = FLUID_SLOT_A
				fluidSlotOut = FLUID_SLOT_B
			end
		end

		if boolValues[5] then
			-- TODO: Override default PID values with ones from floatValues
		end
	end

	powered = useEnergy()
	if powered then
		-- Read pressure from sensing line
		component.slotFluidResolveFlow(
			FLUID_SLOT_SENSING_LINE,
			FLUID_VOLUME_BUFFER,
			0, -- pump_pressure
			1.0, -- flow_factor
			false, -- is_one_way_in_to_slot
			false, -- is_one_way_out_of_slot
			FILTERS,
			-1 -- index_fluid_contents_transfer
		)
		local pressure = component.fluidContentsGetPressure(FLUID_VOLUME_BUFFER)

		local targetPressureInput = component.getInputLogicSlotFloat(TARGET_PRESSURE_SLOT)
		if targetPressureInput ~= prevTargetPressureInput then
			if targetPressureInput < 0 or targetPressureInput > 60 then
				display:setText("ERR")
				targetPressure = 0 -- Disable regulator if input is invalid
			else
				targetPressure = targetPressureInput
				display:setText(targetPressure)
			end

			prevTargetPressureInput = targetPressureInput
		end

		run(pressure)
	end
end

function onRender()
	if not initialized or not powered then
		return
	end

	display:render()
end
