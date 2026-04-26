---@alias AdvancedPIDAntiWindupMode
---| "clamp"           -- Default: bounds integral to available headroom
---| "backcalculation" -- Reset integral to exact saturation value
---| "freeze"          -- Stop integral update during saturation

---@class AdvancedPIDSettings
---@field Kp number Proportional gain. Higher = faster response, more oscillation
---@field Ki number Integral gain. Higher = faster steady-state error elimination, more windup
---@field Kd number Derivative gain. Higher = more damping, more noise sensitivity
---@field min number Output lower bound (saturation limit)
---@field max number Output upper bound (saturation limit). Must be > min
---@field b number? Setpoint weight on P, range [0..1] (default: 1). Use 0 for no kick on SP change, 1 for tracking
---@field c number? Setpoint weight on D, range [0..1] (default: 0). Use 0 for no kick on SP change (recommended), 1 for rare cases
---@field N number? Derivative filter pole in rad/s (default: 20). Higher = less filtering, more noise
---@field antiWindupMode AdvancedPIDAntiWindupMode? Anti-windup strategy (default: "clamp")

---@param settings AdvancedPIDSettings
---@return AdvancedPID
--- A PID controller. Example usage:
--- local pid = PID({ Kp = 0.5, Ki = 1.0, Kd = 0.01, min = 0, max = 1, b = 0.3, c = 0, N = 20 })
--- local output = pid:run(setpoint, processVariable)
local function AdvancedPID(settings)
	---@class (exact) AdvancedPID
	local instance = {}

	local defaultDt = 1 / 60

	local Kp = settings.Kp
	local Ki = settings.Ki
	local Kd = settings.Kd
	local min = settings.min
	local max = settings.max
	local b = settings.b or 1
	local c = settings.c or 0
	local N = settings.N or 20
	local antiWindupMode = settings.antiWindupMode or "clamp"

	---@param newSettings AdvancedPIDSettings
	function instance:updateSettings(newSettings)
		Kp = newSettings.Kp
		Ki = newSettings.Ki
		Kd = newSettings.Kd
		min = newSettings.min
		max = newSettings.max
		b = newSettings.b or b
		c = newSettings.c or c
		N = newSettings.N or N
		antiWindupMode = newSettings.antiWindupMode or antiWindupMode
	end

	local integral = 0
	local prevErrorForD = nil -- stores (c*sp - pv) from previous call
	local prevFilteredDerivative = 0

	local _min, _max = math.min, math.max

	---@param sp number Setpoint
	---@param pv number Process variable
	---@return number proportional Proportional term
	local function _calculateProportional(sp, pv)
		-- Proportional term with setpoint weighting
		return Kp * b * (sp - pv)
	end

	---@param sp number Setpoint
	---@param pv number Process variable
	---@param dt number Time step
	---@return number derivative Derivative term
	local function _calculateDerivative(sp, pv, dt)
		-- Weighted error for derivative term: c*sp - pv
		-- When c=0: derivative acts on -pv (measurement only, no kick)
		-- When c=1: derivative acts on sp-pv = error (kick on SP change)
		local weightedErrorForD = c * sp - pv

		if prevErrorForD == nil then
			-- Initialize on first call to avoid derivative spike
			prevErrorForD = weightedErrorForD
		end

		local rawDerivative = (weightedErrorForD - prevErrorForD) / dt
		prevErrorForD = weightedErrorForD

		local filterAlpha = (N * dt) / (1 + N * dt)
		local filteredDerivative = prevFilteredDerivative + filterAlpha * (rawDerivative - prevFilteredDerivative)
		prevFilteredDerivative = filteredDerivative

		return Kd * filteredDerivative
	end

	---@param sp number Setpoint
	---@param pv number Process variable
	---@param proportional number Calculated P
	---@param derivative number Calculated D
	---@param dt number Time step
	---@return number integral Integral term
	local function _calculateIntegralClamp(sp, pv, proportional, derivative, dt)
		-- Output without integral for anti-windup clamping
		local outputWithoutIntegral = proportional + derivative

		-- Clamp integral to keep total output in bounds
		local integralMin = min - outputWithoutIntegral
		local integralMax = max - outputWithoutIntegral
		local error = sp - pv
		local newIntegral = integral + Ki * error * dt
		return _max(integralMin, _min(integralMax, newIntegral))
	end

	---@param sp number Setpoint
	---@param pv number Process variable
	---@param proportional number Calculated P
	---@param derivative number Calculated D
	---@param dt number Time step
	---@return number integral Integral term
	local function _calculateIntegralBackcalculation(sp, pv, proportional, derivative, dt)
		local error = sp - pv
		local output = proportional + integral + derivative

		if output > max then
			return max - proportional - derivative
		elseif output < min then
			return min - proportional - derivative
		else
			return integral + Ki * error * dt
		end
	end

	---@param sp number Setpoint
	---@param pv number Process variable
	---@param proportional number Calculated P
	---@param derivative number Calculated D
	---@param dt number Time step
	---@return number integral Integral term
	local function _calculateIntegralFreeze(sp, pv, proportional, derivative, dt)
		local output = proportional + integral + derivative

		if output > max or output < min then
			return integral -- frozen
		else
			return integral + Ki * error * dt
		end
	end

	---@param mode AdvancedPIDAntiWindupMode
	---@return fun(sp: number, pv:number, proportional:number,derivative:number, dt:number): number
	local function _makeIntegralCalculationFunc(mode)
		if mode == "clamp" then
			return _calculateIntegralClamp
		elseif mode == "backcalculation" then
			return _calculateIntegralBackcalculation
		elseif mode == "freeze" then
			return _calculateIntegralFreeze
		else
			error()
		end
	end

	local _calculateIntegral = _makeIntegralCalculationFunc(antiWindupMode)

	---@param sp number Setpoint
	---@param pv number Process variable
	---@param dt number? Seconds since last call (default: 1/60)
	---@return number output Clamped controller output
	function instance:run(sp, pv, dt)
		dt = dt or defaultDt

		local proportional = _calculateProportional(sp, pv)
		local derivative = _calculateDerivative(sp, pv, dt)

		integral = _calculateIntegral(sp, pv, proportional, derivative, dt)

		local output = proportional + integral + derivative

		-- Numerical safety clamp
		return _max(min, _min(max, output))
	end

	return instance
end

return AdvancedPID
