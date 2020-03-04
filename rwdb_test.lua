ipc = {}


function ipc.log(line)
    print(line)
end

r5csv_path = "..\\"

rwdb = require("rwdb")

-- rwdb.dump_cache()

-- less than 0.001 cpu
local rw, rw_dist = rwdb.nearest_rw(50.046735, 8.593897)

print(string.format("%s %s %f %f %f", rw[rw_icao_], rw[rw_designator_], rw_dist, rw[rw_lat_], rw[rw_lon_]))

local td_dist = rwdb.thr_distance(rw, 50.043633, 8.580658)
print(string.format("touch down distance %f", td_dist))

-- less than 0.001 cpu
rw, rw_dist = rwdb.nearest_rw(51.299213, 6.781378)
print(string.format("%s %s %f %f %f", rw[rw_icao_], rw[rw_designator_], rw_dist, rw[rw_lat_], rw[rw_lon_]))
td_dist = rwdb.thr_distance(rw, 51.294948, 6.772293)
print(string.format("touch down distance %f", td_dist))

local lat = 58.356540
local lon = -134.588810

rw, rw_dist = rwdb.nearest_rw(lat, lon)
print(string.format("%s %s %f %f %f", rw[rw_icao_], rw[rw_designator_], rw_dist, rw[rw_lat_], rw[rw_lon_]))

td_dist = rwdb.thr_distance(rw, lat, lon)
print(string.format("touch down distance %f", td_dist))

local td_x, td_y = rwdb.mk_thr_vec(rw, lat, lon)
print(rwdb.vec_length(td_x, td_y))

local crl_x, crl_y = rwdb.mk_ctrl_uvec(rw)
local d_crl = td_x * crl_y - td_y * crl_x
print("Ofs: ", d_crl)