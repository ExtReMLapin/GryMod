-- Real samples of gm_fork recorded for the tests of the floors rule (stairs and ramps the owner shows), by tests/minimap/stairs_record_job.lua and dev_resources/save_stairs.py.
return {
	-- fork_stairs_1 (recorded 2026-11-22 at the owner's request): pos 11374.38,-1754.83,-7655.97, angles (pitch, yaw, roll) 33.44,-1.2,0, the level of the rule here: fn7680c160, ceiling 159.93 units over the feet.
	-- The ground followed straight ahead every 12 units with down rays: 15 samples, 168 units, z -7655.97 to -7727.97, stopped by: wall. Format: {x, y, feet z, highest ceiling that is not the sky
	-- (-99999: none), 1 when the centre ray saw the sky or nothing, height of the sky or 0}.
	fork_stairs_1 = {
		{11374.4, -1754.8, -7655.97, -7496.03, 0, 0.00},
		{11386.4, -1755.1, -7663.97, -7496.03, 0, 0.00},
		{11398.4, -1755.3, -7671.97, -7496.03, 0, 0.00},
		{11410.4, -1755.6, -7679.97, -7496.03, 0, 0.00},
		{11422.4, -1755.8, -7687.97, -7496.03, 0, 0.00},
		{11434.4, -1756.1, -7695.97, -7496.03, 0, 0.00},
		{11446.4, -1756.3, -7703.97, -7496.03, 0, 0.00},
		{11458.4, -1756.6, -7711.97, -7496.03, 0, 0.00},
		{11470.4, -1756.8, -7719.97, -7496.03, 0, 0.00},
		{11482.4, -1757.1, -7727.97, -7496.03, 0, 0.00},
		{11494.4, -1757.3, -7727.97, -7496.03, 0, 0.00},
		{11506.4, -1757.6, -7727.97, -7488.03, 0, 0.00},
		{11518.4, -1757.8, -7727.97, -7488.03, 0, 0.00},
		{11530.4, -1758.1, -7727.97, -7488.03, 0, 0.00},
		{11542.4, -1758.3, -7727.97, -7488.03, 0, 0.00},
	},
}
