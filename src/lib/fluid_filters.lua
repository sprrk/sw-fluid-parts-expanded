return {
	-- Liquid:
	WATER = 1,
	DIESEL = 2,
	JET = 4,
	OIL = 32,
	SEA_WATER = 64,
	SLURRY = 256,
	SATURATED_SLURRY = 512,
	-- Gas:
	AIR = 8, -- NOTE: Not sure if this is actually used in-game.
	CO2 = 16,
	STEAM = 128,
	O2 = 1024,
	N2 = 2048,
	H2 = 4096,
	-- Combinations:
	ALL_LIQUIDS = 871, -- 1 + 2 + 4 + 32 + 64 + 256 + 512
	ALL_GASES = 7320, -- 8 + 16 + 128 + 1024 + 2048 + 4096
	ALL = 8191,
}
