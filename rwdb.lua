-- MIT License

-- Copyright (c) 2020 Holger Teutsch

-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:

-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.

-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

-- module table
rwdb = {}

-- index into rw table
rw_icao_ = 1
rw_designator_ = 2
rw_lat_ = 3
rw_lon_ = 4
rw_alt_ = 5
rw_hdg_ = 6
rw_mag_var_ = 10
rw_lat_ctr_ = 11  -- center of rw
rw_lon_ctr_ = 12
rw_thresh_ofs_ = 13

local R = 6371001.0 -- IUGG average radius of earth in m
local d_1deg = R * math.pi / 180 -- distance 1 deg in m, ~ 60 sm

local cache = nil

-- cache by lower left corner of 1x1 deg tile
local function mk_cache_key(lat, lon)
    -- date line
    if lon < -180 then
        lon = lon + 360
    end

    local lat_e = math.floor(lat)
    local lon_e = math.floor(lon)
    return string.format("%+04d_%+04d", lat_e, lon_e)
end

function rwdb.build_cache(rwdb_files)
    local t1
    t1 = os.clock()

    cache = {}

    for _, fn in ipairs(rwdb_files) do
        f = io.open(fn, "r")

        if f ~= nil then
           ipc.log("Processing: " .. fn)

            local line
            for line in f:lines() do
                -- ipc.log(line)
                if line:sub(1, 1) ~= '#' then
                    local i = 1

                    local rw = {}
                    for word in string.gmatch(line, '[^,]+') do
                        if (rw_lat_ <= i and i <= rw_hdg_) or (rw_mag_var_ <= i and i <= rw_thresh_ofs_) then
                            rw[i] = tonumber(word)
                        else
                            rw[i] = word
                        end
                        i = i + 1
                    end

                    if rw[14] ~= "CL" then  -- landing must be allowed
                        -- pretty format runway designator
                        local d = rw[rw_designator_]
                        local num = d:sub(2,3)
                        local c = tonumber(d:sub(4,4))
                        rw[rw_designator_] = num .. ({'', 'L', 'R', 'C'})[c+1]

                        local lat = rw[rw_lat_]
                        local lon = rw[rw_lon_]
                        local disp = rw[rw_thresh_ofs_]

                        -- set threshold to displaced threshold
                        if disp > 0 then
                            disp = disp * 0.3048 -- m
                            local dir = math.rad(rw[rw_hdg_] + rw[rw_mag_var_])  -- true
                            lat = lat + disp * math.cos(dir) / d_1deg
                            lon = lon + disp * math.sin(dir) / math.cos(math.rad(lat)) / d_1deg
                            rw[rw_lat_] = lat
                            rw[rw_lon_] = lon
                        end

                        local cache_key = mk_cache_key(lat, lon)
                        local rw_key = rw[rw_icao_] .. "_" .. rw[rw_designator_]

                        -- ipc.log(string.format("%s %s %f %f %s %s",
                        --                    rw[rw_icao_], rw[rw_designator_], lat, lon, cache_key, rw_key))

                        local rw_list = cache[cache_key]
                        if rw_list == nil then
                            rw_list = {}
                            cache[cache_key] = rw_list
                        end
                        rw_list[rw_key] = rw
                    end
                end
            end

        io.close(f)
        end
    end

    if (next(cache) == nil) then
        cache = nil
    end

    ipc.log(string.format("rwdb: cache built with %0.3fs CPU", os.clock() - t1))
end

function rwdb.dump_cache()
    if cache == nil then
        ipc.log("cache is nil")
        return
    end

    local cache_key, rw_list
    for cache_key, rw_list in pairs(cache) do
        ipc.log(cache_key)
        local rw_key, rw
        for rw_key, rw in pairs(rw_list) do
            ipc.log(string.format("%s %f %f", rw_key, rw[rw_lat_], rw[rw_lon_]))
        end
        ipc.log()
    end
end

-- euclidian vector (lat1, lon1) - (lat0, lon0) : x to east y to north
-- small distances only
function rwdb.mk_vec(lat0, lon0, lat1, lon1)
    return (lon1 - lon0) * math.cos(math.rad((lat0 + lat1)/2)) * d_1deg, (lat1 - lat0) * d_1deg
end


function rwdb.vec_length(x, y)
    return math.sqrt(x * x + y * y)
end

-- vector to threshold
function rwdb.mk_thr_vec(rw, lat, lon)
    return rwdb.mk_vec(rw[rw_lat_], rw[rw_lon_], lat, lon)
end

-- center line unit vector
function rwdb.mk_ctrl_uvec(rw)
    local dir = math.rad(rw[rw_hdg_] + rw[rw_mag_var_])
    return math.sin(dir), math.cos(dir)
end

-- https://stackoverflow.com/questions/639695/how-to-convert-latitude-or-longitude-to-meters
local function geo_dist(lat, lon, lat1, lon1)
    lat = math.rad(lat)
    lon = math.rad(lon)
    lat1 = math.rad(lat1)
    lon1 = math.rad(lon1)
    local dlat = lat1 - lat
    local dlon = lon1 - lon
    local a = math.sin(dlat/2) * math.sin(dlat/2) +
        math.cos(lat) * math.cos(lat1) * math.sin(dlon/2) * math.sin(dlon/2)
    local c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    return R * c
end

-- find nearest rw in tile for lat_tile, lon_tile closer than min_dist
local function nearest_rw_tile(lat, lon, lat_tile, lon_tile, min_rw, min_dist)
    local cache_key = mk_cache_key(lat_tile, lon_tile)
    local rw_list = cache[cache_key]

    if rw_list == nil then
        return nil, min_dist
    end

    local rw_key, rw
    for rw_key, rw in pairs(rw_list) do
        -- ipc.log(string.format("%s %f %f", rw_key, rw[rw_lat_], rw[rw_lon_]))
        local dist = geo_dist(lat, lon, rw[rw_lat_], rw[rw_lon_])

        -- select only runways where the bearing to the thr matched the rwy hdg
        -- otherwise you pick the wrong one with parallel rwys
        local x, y = rwdb.mk_thr_vec(rw, lat, lon) -- threshold to pos
        local bearing = math.fmod(90 - math.atan2(-y, -x) * 180 / math.pi + 360, 360) -- true bearing
        --ipc.log(string.format("%s dist %0.2f bearing %.0f", rw_key, dist, bearing))

        if dist < min_dist and math.abs(bearing - rw[rw_hdg_]) < 5 then
            -- ipc.log(string.format("%s dist %0.2f bearing %.0f", rw_key, dist, bearing))
            min_dist = dist
            min_rw = rw
        end
    end

    return min_rw, min_dist
end

-- find nearest runway
function rwdb.nearest_rw(lat, lon)
   if cache == nil then
        return nil, nil
    end

    local min_dist = 1.0E20
    local min_rw

    -- find nearest in plane's own tile
    min_rw, min_dist = nearest_rw_tile(lat, lon, lat, lon, nil, min_dist)

    -- relative within tile
    local lon_rel = lon - math.floor(lon)
    local lat_rel = lat - math.floor(lat)

    -- if close to an edge, check neighbor tiles as well
    if lon_rel < 0.1 then
        min_rw, min_dist = nearest_rw_tile(lat, lon, lat, lon - 1, min_rw, min_dist)

        if lat_rel < 0.05 then
            min_rw, min_dist = nearest_rw_tile(lat, lon, lat - 1, lon - 1, min_rw, min_dist)
        elseif lat_rel > 0.95 then
            min_rw, min_dist = nearest_rw_tile(lat, lon, lat + 1, lon - 1, min_rw, min_dist)
        end

    elseif lon_rel > 0.9 then
        min_rw, min_dist = nearest_rw_tile(lat, lon, lat, lon + 1, min_rw, min_dist)

        if lat_rel < 0.05 then
            min_rw, min_dist = nearest_rw_tile(lat, lon, lat - 1, lon + 1, min_rw, min_dist)
        elseif lat_rel > 0.95 then
            min_rw, min_dist = nearest_rw_tile(lat, lon, lat + 1, lon + 1, min_rw, min_dist)
        end
    end

    if lat_rel < 0.05 then
        min_rw, min_dist = nearest_rw_tile(lat, lon, lat - 1, lon, min_rw, min_dist)
    elseif lat_rel > 0.95 then
        min_rw, min_dist = nearest_rw_tile(lat, lon, lat + 1, lon, min_rw, min_dist)
    end

    return min_rw, min_dist
end

-- distance to threshold
function rwdb.thr_distance(rw, lat, lon)
    return geo_dist(lat, lon, rw[rw_lat_], rw[rw_lon_])
end

return rwdb
