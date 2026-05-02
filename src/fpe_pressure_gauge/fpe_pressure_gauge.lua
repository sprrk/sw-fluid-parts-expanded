local memoize = require("sw-lua-lib/cache/simple_memoize")
local clamp = require("sw-lua-lib/extramath/clamp")
local snap = require("sw-lua-lib/extramath/snap")
local FILTERS = require("../lib/fluid_filters").ALL_LIQUIDS + require("../lib/fluid_filters").ALL_GASES
local createTimer = require("sw-lua-lib/timer/callback_timer")

local SETTINGS_SLOT = 0
local FLUID_VOLUME_SIZE_BUFFER = 2.0 -- Liters
local FLUID_SLOT = 0
local FLUID_VOLUME_BUFFER = 0

local SETTINGS_READ_INTERVAL = 60
local NEEDLE_SWEEP_ANGLE_DEG = 270
local MAX_PRESSURE = 60
local SEGMENTS = 24
local DEGREES_PER_SEGMENT = NEEDLE_SWEEP_ANGLE_DEG / SEGMENTS
local PRESSURE_RESOLUTION = MAX_PRESSURE / NEEDLE_SWEEP_ANGLE_DEG

local initialized = false
local pressure = 0

local greenStartIndex = 0
local greenEndIndex = 0
local red1StartIndex = 0
local red1EndIndex = 0
local red2StartIndex = 0
local red2EndIndex = 0

local greenSegmentsEnabled = false
local red1SegmentsEnabled = false
local red2SegmentsEnabled = false

local getNeedleRot = memoize(
	---@param p number Quantized pressure
	function(p)
		local t = clamp(p / MAX_PRESSURE, 0, 1)
		local angle = math.rad(-NEEDLE_SWEEP_ANGLE_DEG * 0.5 + t * NEEDLE_SWEEP_ANGLE_DEG)
		return matrix.rotationY(angle)
	end
)

local getSegmentRot = memoize(
	---@param i integer Segment index
	function(i)
		local angle_deg = DEGREES_PER_SEGMENT * i
		local angle_rad = math.rad(-NEEDLE_SWEEP_ANGLE_DEG * 0.5 + angle_deg)
		return matrix.rotationY(angle_rad)
	end
)

---@param p number
---@return integer
local function pressureToSegmentIndex(p)
	local t = p / MAX_PRESSURE
	return clamp(math.floor(t * SEGMENTS), 0, SEGMENTS)
end

local function updateSettings()
	local composite, ok = component.getInputLogicSlotComposite(SETTINGS_SLOT)
	if not ok then
		return
	end

	local floats = composite.float_values

	local greenStart = clamp(floats[1], 0, MAX_PRESSURE)
	local greenEnd = clamp(floats[2], 0, MAX_PRESSURE)
	local red1Start = clamp(floats[3], 0, MAX_PRESSURE)
	local red1End = clamp(floats[4], 0, MAX_PRESSURE)
	local red2Start = clamp(floats[5], 0, MAX_PRESSURE)
	local red2End = clamp(floats[6], 0, MAX_PRESSURE)

	greenSegmentsEnabled = greenEnd > greenStart
	if greenSegmentsEnabled then
		greenStartIndex = pressureToSegmentIndex(greenStart)
		greenEndIndex = pressureToSegmentIndex(greenEnd) - 1
	end

	red1SegmentsEnabled = red1End > red1Start
	if red1SegmentsEnabled then
		red1StartIndex = pressureToSegmentIndex(red1Start)
		red1EndIndex = pressureToSegmentIndex(red1End) - 1
	end

	red2SegmentsEnabled = red2End > red2Start
	if red2SegmentsEnabled then
		red2StartIndex = pressureToSegmentIndex(red2Start)
		red2EndIndex = pressureToSegmentIndex(red2End) - 1
	end
end

local settingsTimer = createTimer(SETTINGS_READ_INTERVAL, updateSettings)

function onTick(_)
	if not initialized then
		component.fluidContentsSetCapacity(FLUID_VOLUME_BUFFER, FLUID_VOLUME_SIZE_BUFFER)
		updateSettings()
		initialized = true
	end

	settingsTimer()

	-- Read pressure from sensing line
	component.slotFluidResolveFlow(
		FLUID_SLOT,
		FLUID_VOLUME_BUFFER,
		0, -- pump_pressure
		1.0, -- flow_factor
		false, -- is_one_way_in_to_slot
		false, -- is_one_way_out_of_slot
		FILTERS,
		-1 -- index_fluid_contents_transfer
	)
	pressure = component.fluidContentsGetPressure(FLUID_VOLUME_BUFFER)
end

function onRender()
	if not initialized then
		return
	end

	-- Render needle
	component.renderMesh0(getNeedleRot(snap(pressure, PRESSURE_RESOLUTION)))

	-- Render segments
	if greenSegmentsEnabled then
		local renderMesh1 = component.renderMesh1
		for i = greenStartIndex, greenEndIndex do
			renderMesh1(getSegmentRot(i))
		end
	end

	if red1SegmentsEnabled then
		local renderMesh2 = component.renderMesh2
		for i = red1StartIndex, red1EndIndex do
			renderMesh2(getSegmentRot(i))
		end
	end

	if red2SegmentsEnabled then
		local renderMesh2 = component.renderMesh2
		for i = red2StartIndex, red2EndIndex do
			renderMesh2(getSegmentRot(i))
		end
	end
end
