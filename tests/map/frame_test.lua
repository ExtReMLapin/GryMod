-- Tests of the big map's frame (lua/grymod/client/map/frame.lua), GLuaTest format, client realm: the maths between the world and the window of the
-- map (pure, no engine call). The map is NOT turned: world +X is up on the screen and world -Y is to the right, which is the way a captured tile
-- is stored, so a tile is drawn without any rotation. The numbers: bounds 0..1000 on both axes, a window of 500 x 500 pixels at (100, 50), so one
-- world unit is 0.5 pixel at zoom 1.

local function F()
	local frame = GryMod and GryMod.Map and GryMod.Map.Frame

	expect(frame ~= nil).to.beTrue()

	return frame
end

local BOUNDS = {x0 = 0, x1 = 1000, y0 = 0, y1 = 1000}
local RECT = {x = 100, y = 50, w = 500, h = 500}

local function fresh()
	return F().New(RECT, BOUNDS)
end

return {
	groupName = "GryMod big map frame",
	cases = {
		-- fails without Frame.WindowSize
		{
			name = "the window has the shape of the bounds (width over height from 1:2 to 2:1) and fits in the room it is given",
			func = function()
				local frame = F()
				local w, h = frame.WindowSize(1000, 800, {x0 = 0, x1 = 1000, y0 = 0, y1 = 1000})

				expect(w).to.equal(800)
				expect(h).to.equal(800)

				-- wider than high (the screen's horizontal axis is world Y): 2000 along Y, 1000 along X
				w, h = frame.WindowSize(1000, 800, {x0 = 0, x1 = 1000, y0 = 0, y1 = 2000})
				expect(w).to.equal(1000)
				expect(h).to.equal(500)

				-- very long: the shape stops at 2:1, the picture covers it and a pan stays possible on the long axis
				w, h = frame.WindowSize(1000, 800, {x0 = 0, x1 = 1000, y0 = 0, y1 = 9000})
				expect(w).to.equal(1000)
				expect(h).to.equal(500)

				-- tall: 1000 along Y, 4000 along X: 1:2 at the most, height limited by the room
				w, h = frame.WindowSize(1000, 800, {x0 = 0, x1 = 4000, y0 = 0, y1 = 1000})
				expect(w).to.equal(400)
				expect(h).to.equal(800)
			end
		},
		-- fails when the scale at zoom 1 does not make the bounds cover the window
		{
			name = "at zoom 1 the bounds exactly fill the window (0.5 pixel a unit), and the view is centred on the bounds",
			func = function()
				local v = fresh()

				expect(v.zoom).to.equal(1)
				expect(F().Scale(v)).to.aboutEqual(0.5, 1e-12)
				expect(v.cx).to.equal(500)
				expect(v.cy).to.equal(500)
			end
		},
		-- fails when the orientation is not +X up and -Y right
		{
			name = "world +X is up on the screen and world -Y is to the right: the centre is the middle of the window",
			func = function()
				local frame = F()
				local v = fresh()
				local sx, sy = frame.ToScreen(v, 500, 500)

				expect(sx).to.aboutEqual(350, 1e-9)
				expect(sy).to.aboutEqual(300, 1e-9)

				-- x = 1000 is the top edge, y = 0 the right edge
				sx, sy = frame.ToScreen(v, 1000, 0)
				expect(sx).to.aboutEqual(600, 1e-9)
				expect(sy).to.aboutEqual(50, 1e-9)

				-- x = 0 is the bottom edge, y = 1000 the left edge
				sx, sy = frame.ToScreen(v, 0, 1000)
				expect(sx).to.aboutEqual(100, 1e-9)
				expect(sy).to.aboutEqual(550, 1e-9)
			end
		},
		{
			name = "ToWorld is the inverse of ToScreen at any zoom and centre",
			func = function()
				local frame = F()
				local v = fresh()

				frame.ZoomAt(v, 3.4, 250, 200)

				for _, p in ipairs({{300, 400}, {750, 620}, {500, 500}}) do
					local sx, sy = frame.ToScreen(v, p[1], p[2])
					local x, y = frame.ToWorld(v, sx, sy)

					expect(x).to.aboutEqual(p[1], 1e-6)
					expect(y).to.aboutEqual(p[2], 1e-6)
				end
			end
		},
		-- fails when the zoom goes toward the centre of the window instead of the cursor
		{
			name = "the wheel zooms toward the mouse: the world point under the cursor stays under the cursor",
			func = function()
				local frame = F()
				local v = fresh()
				local mx, my = 400, 150
				local wx, wy = frame.ToWorld(v, mx, my)

				frame.ZoomAt(v, 2, mx, my)

				expect(v.zoom).to.equal(2)
				expect(F().Scale(v)).to.aboutEqual(1, 1e-12)

				local sx, sy = frame.ToScreen(v, wx, wy)

				expect(sx).to.aboutEqual(mx, 1e-6)
				expect(sy).to.aboutEqual(my, 1e-6)
				-- the numbers by hand: under (400, 150) is x = 800, y = 400; the centre becomes x = 650, y = 450
				expect(wx).to.aboutEqual(800, 1e-6)
				expect(wy).to.aboutEqual(400, 1e-6)
				expect(v.cx).to.aboutEqual(650, 1e-6)
				expect(v.cy).to.aboutEqual(450, 1e-6)
			end
		},
		-- fails when the clamp lets an empty margin show
		{
			name = "the picture never leaves the window: zooming out in a corner is pushed back so that the bounds still fill it",
			func = function()
				local frame = F()
				local v = fresh()

				frame.SetZoom(v, 4)
				frame.CentreOn(v, 900, 100)

				-- pinned in the corner: the window shows 250 units, x from 750 to 1000, y from 0 to 250
				local minx, maxx, miny, maxy = frame.View(v)

				expect(maxx).to.aboutEqual(1000, 1e-6)
				expect(miny).to.aboutEqual(0, 1e-6)

				-- zoom 2 toward the middle of the window: the window would show x from 625 to 1125 if nothing pushed it back
				frame.ZoomAt(v, 2, v.x + v.w / 2, v.y + v.h / 2)
				minx, maxx, miny, maxy = frame.View(v)

				expect(minx >= -1e-6).to.beTrue()
				expect(maxx <= 1000 + 1e-6).to.beTrue()
				expect(miny >= -1e-6).to.beTrue()
				expect(maxy <= 1000 + 1e-6).to.beTrue()
				expect(maxx).to.aboutEqual(1000, 1e-6)
				expect(miny).to.aboutEqual(0, 1e-6)
				expect(maxx - minx).to.aboutEqual(500, 1e-6)
			end
		},
		-- fails when a cursor in the very corner does not keep the corner
		{
			name = "a zoom toward the very corner of the window keeps that corner of the map in it",
			func = function()
				local frame = F()
				local v = fresh()

				-- the top right corner of the window is x = 1000, y = 0
				frame.ZoomAt(v, 4, 600, 50)

				local _, maxx, miny = frame.View(v)

				expect(maxx).to.aboutEqual(1000, 1e-6)
				expect(miny).to.aboutEqual(0, 1e-6)
			end
		},
		-- fails when a pan is allowed at zoom 1
		{
			name = "at zoom 1 there is no pan: the bounds fill the window exactly",
			func = function()
				local frame = F()
				local v = fresh()

				frame.Pan(v, 120, -80)

				expect(v.cx).to.aboutEqual(500, 1e-9)
				expect(v.cy).to.aboutEqual(500, 1e-9)
			end
		},
		-- fails when the drag moves the picture the wrong way or beyond the bounds
		{
			name = "dragging moves the picture with the mouse (the world follows the hand) and stops at the bounds",
			func = function()
				local frame = F()
				local v = fresh()

				frame.SetZoom(v, 2)

				local sx0, sy0 = frame.ToScreen(v, 600, 500)

				frame.Pan(v, 40, 30)

				local sx1, sy1 = frame.ToScreen(v, 600, 500)

				expect(sx1 - sx0).to.aboutEqual(40, 1e-6)
				expect(sy1 - sy0).to.aboutEqual(30, 1e-6)

				-- a huge drag: the picture stops with its edge on the window's edge
				frame.Pan(v, 100000, 100000)

				local minx, maxx, miny, maxy = frame.View(v)

				expect(maxx).to.aboutEqual(1000, 1e-6)
				expect(maxy).to.aboutEqual(1000, 1e-6)
				expect(maxx - minx).to.aboutEqual(500, 1e-6)
				expect(maxy - miny).to.aboutEqual(500, 1e-6)

				-- and a drag the other way works at once (no "wound up" distance to undo)
				frame.Pan(v, -10, 0)

				local _, _, miny2, maxy2 = frame.View(v)

				expect(maxy2 < maxy).to.beTrue()
			end
		},
		-- fails when the zoom is not clamped to 1..8
		{
			name = "the zoom is kept from 1 to 8",
			func = function()
				local frame = F()
				local v = fresh()

				frame.SetZoom(v, 50)
				expect(v.zoom).to.equal(8)
				frame.SetZoom(v, 0.1)
				expect(v.zoom).to.equal(1)
			end
		},
		-- fails when a window of another shape than the bounds does not get the covering scale
		{
			name = "a window that is wider than the bounds' shape is covered: the long axis can still be panned at zoom 1",
			func = function()
				local frame = F()
				-- bounds 1000 along Y and 4000 along X (a 1:4 strip), window 500 x 500: not the same shape
				local v = frame.New({x = 0, y = 0, w = 500, h = 500}, {x0 = 0, x1 = 4000, y0 = 0, y1 = 1000})

				-- covering: the scale is the larger of 500 / 1000 and 500 / 4000
				expect(frame.Scale(v)).to.aboutEqual(0.5, 1e-12)

				local minx, maxx, miny, maxy = frame.View(v)

				-- the whole width of the bounds, a quarter of their height
				expect(maxy - miny).to.aboutEqual(1000, 1e-6)
				expect(maxx - minx).to.aboutEqual(1000, 1e-6)

				frame.Pan(v, 0, 200)

				local minx2 = frame.View(v)

				expect(minx2 ~= minx).to.beTrue()
				expect(minx2 >= -1e-6).to.beTrue()
			end
		},
		-- fails when CentreOn does not clamp
		{
			name = "CentreOn puts a world point in the middle of the window, as far as the bounds allow",
			func = function()
				local frame = F()
				local v = fresh()

				frame.SetZoom(v, 4)
				frame.CentreOn(v, 600, 300)
				expect(v.cx).to.aboutEqual(600, 1e-9)
				expect(v.cy).to.aboutEqual(300, 1e-9)

				frame.CentreOn(v, 5000, -5000)
				expect(v.cx).to.aboutEqual(875, 1e-9)
				expect(v.cy).to.aboutEqual(125, 1e-9)
			end
		},
		-- fails when the rectangle of a tile is not the screen rectangle of its corners
		{
			name = "the rectangle of a tile is its corners on the screen: left = its largest Y, top = its largest X",
			func = function()
				local frame = F()
				local v = fresh()
				local left, top, right, bottom = frame.TileRect(v, 0, 0, 500, 500, 500, 500)

				-- the tile minx 0..500, miny 0..500 is the bottom right quarter of the window
				expect(left).to.aboutEqual(350, 1e-9)
				expect(top).to.aboutEqual(300, 1e-9)
				expect(right).to.aboutEqual(600, 1e-9)
				expect(bottom).to.aboutEqual(550, 1e-9)
			end
		},
		-- fails when SetBounds keeps a centre that is outside the new bounds
		{
			name = "new bounds keep the zoom and the centre as far as they fit, the scale follows the bounds",
			func = function()
				local frame = F()
				local v = fresh()

				frame.SetZoom(v, 2)
				frame.CentreOn(v, 900, 900)
				frame.SetBounds(v, {x0 = 0, x1 = 500, y0 = 0, y1 = 500})

				expect(frame.Scale(v)).to.aboutEqual(2, 1e-9) -- 500 pixels over 500 units at zoom 1 is 1, times 2
				expect(v.cx <= 500 - 125 + 1e-6).to.beTrue()
				expect(v.cy <= 500 - 125 + 1e-6).to.beTrue()
			end
		}
	}
}
