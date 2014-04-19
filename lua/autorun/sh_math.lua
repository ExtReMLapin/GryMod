
function math.LengthSqVector(a)
	return (a.x * a.x + a.y * a.y + a.z * a.z);
end

function math.LengthVector(a)
	return math.sqrt(LengthSqVector(a));
end

function math.DistanceSqVectors(a, b)
	local x = a.x-b.x;
	local y = a.y-b.y;
	local z = a.z-b.z;
	return x*x + y*y + z*z;
end

function math.DistanceSqVectors2d(a, b)
	local x = a.x-b.x;
	local y = a.y-b.y;
	return x*x + y*y;
end

function math.DistanceVectors(a, b)
	local x = a.x-b.x;
	local y = a.y-b.y;
	local z = a.z-b.z;
	return math.sqrt(x*x + y*y + z*z);
end

function math.Delta(actual,goal)
return goal - actual;
end

function EyeFinityScrW()
	if tempscrw/tempscrh == 16/3  and EyeFinity:GetInt() > 0 then
		return tempscrw/3
	else return tempscrw
	end
end

function constrain(val, minv, maxv)
	return math.min(math.max(val, minv), maxv)
 end
 
 function math.MapSimple(numb,endA,endB) // i used the map() function in processing, i have no idea if there smthng similar here
	return numb*(endB/endA)
end