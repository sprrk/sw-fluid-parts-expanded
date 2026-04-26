---@class PIDsettings
---@field Kp number Proportional gain. Higher = faster response, more oscillation
---@field Ki number Integral gain. Higher = faster steady-state error elimination, more windup
---@field Kd number Derivative gain. Higher = more damping, more noise sensitivity
---@field min number Output lower bound (saturation limit)
---@field max number Output upper bound (saturation limit). Must be > min
---@field b number? Setpoint weight on P, range [0..1] (default: 1). Use 0 for no kick on SP change, 1 for tracking
---@field c number? Setpoint weight on D, range [0..1] (default: 0). Use 0 for no kick on SP change (recommended), 1 for rare cases
---@field N number? Derivative filter pole in rad/s (default: 20). Higher = less filtering, more noise

---@param settings PIDsettings
---@return fun(sp: number, pv: number, dt: number?): number output
--- A PID controller. Example usage:
--- local pid = PID({ Kp = 0.5, Ki = 1.0, Kd = 0.01, min = 0, max = 1, b = 0.3, c = 0, N = 20 })
--- local output = pid(setpoint, processVariable)
local function PID(settings)
	local defaultDt = 1 / 60

	local Kp = settings.Kp
	local Ki = settings.Ki
	local Kd = settings.Kd
	local min = settings.min
	local max = settings.max
	local b = settings.b or 1
	local c = settings.c or 0
	local N = settings.N or 20

	local integral = 0
	local prevErrorForD = nil -- stores (c*sp - pv) from previous call
	local prevFilteredDerivative = 0

	local _min, _max = math.min, math.max

	---@param sp number Setpoint
	---@param pv number Process variable
	---@param dt number? Seconds since last call (default: 1/60)
	---@return number output Clamped controller output
	return function(sp, pv, dt)
		dt = dt or defaultDt

		-- Weighted error for derivative term: c*sp - pv
		-- When c=0: derivative acts on -pv (measurement only, no kick)
		-- When c=1: derivative acts on sp-pv = error (kick on SP change)
		local weightedErrorForD = c * sp - pv

		-- Initialize on first call to avoid derivative spike
		if prevErrorForD == nil then
			prevErrorForD = weightedErrorForD
		end

		local error = sp - pv

		-- Proportional term with setpoint weighting
		local proportional = Kp * b * (sp - pv)

		-- Derivative with filter
		local rawDerivative = (weightedErrorForD - prevErrorForD) / dt
		prevErrorForD = weightedErrorForD

		local filterAlpha = (N * dt) / (1 + N * dt)
		local filteredDerivative = prevFilteredDerivative + filterAlpha * (rawDerivative - prevFilteredDerivative)
		prevFilteredDerivative = filteredDerivative

		local derivative = Kd * filteredDerivative

		-- Output without integral for anti-windup clamping
		local outputWithoutIntegral = proportional + derivative

		-- Clamp integral to keep total output in bounds
		local integralMin = min - outputWithoutIntegral
		local integralMax = max - outputWithoutIntegral

		integral = integral + Ki * error * dt
		integral = _max(integralMin, _min(integralMax, integral))

		local output = outputWithoutIntegral + integral

		-- Numerical safety clamp
		return _max(min, _min(max, output))
	end
end

return PID
