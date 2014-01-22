
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