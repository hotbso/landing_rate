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

-- landing_rate.lua

-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ start of customizations ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

local show_time = 40    -- time in seconds to show result window
local textual_rating = true
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ end of customizations ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

require("rwdb")

local VERSION = "1.3"

local M_2_FT = 3.2808

-- Source of data (among others)
-- https://www.pprune.org/tech-log/510634-definition-hard-landing-maintenance.html

local a3xx_ratings = {
    {180, "Smooth landing"},
    {240, "Firm landing"},
    {600, "Uncomfortable landing"},
    {830, "Hard landing, requires inspection"},
    {100000, "Severe hard landing, damage likely"}
}

local acf_model, p3d_directory, script_directory

local was_airborne = false

local vs, rw, rw_dist, thr_dist, thr_crossed, thr_ra

local function get_pos()
    local lat = ipc.readDD(0x560) * 90.0 / (10001750.0 * 2^32)
    local lon = ipc.readDD(0x568) * 360.0 / 2^64
    return lat, lon
end

-- m/s
local function get_vs()
    local vs = ipc.readDBL(0x31A0) -- vertical GS fpm (Y axis)
    return vs / M_2_FT
end


local function get_a3xx_rating(vs)
    for i, r in ipairs(a3xx_ratings) do
        if vs <= r[1] then return r[2] end
    end
    return ""
end

local function display_data()
    -- the last recorded vs before touch down is the correct one
    local td_vs = vs

    local ias = ipc.readSD(0x02BC) / 128
    local pitch = ipc.readUD(0x578) * 360 / 2^32
    if pitch > 180 then pitch = 360 - pitch end -- normalize

    local vs_fpm = -td_vs * M_2_FT * 60
    local line = string.format("vs: %0.0f fpm, IAS: %0.0f kn, pitch: %.1f°", vs_fpm, ias, pitch)

    if textual_rating and (acf_model == "A320" or acf_model == "A321" or acf_model == "A319") then
        local rating = get_a3xx_rating(vs_fpm)
        line = line .. "\n" .. rating
    end

    if rw ~=nil then
        local lat, lon = get_pos()
        ipc.log(string.format("td rw %s %s %f,%f", rw[rw_icao_], rw[rw_designator_], rw[rw_lat_], rw[rw_lon_]))
        ipc.log(string.format("td lat,lon %f,%f", lat, lon))

        local td_x, td_y = rwdb.mk_thr_vec(rw, lat, lon)
        local td_dist = rwdb.vec_length(td_x, td_y)         -- dist from threshold
        local crl_x, crl_y = rwdb.mk_ctrl_uvec(rw)          -- centerline unit vector
        local d_crl = td_x * crl_y - td_y * crl_x           -- ofs from centerline

        local true_hdg = ipc.readUD(0x580) * 360 / 2^32
        local true_rw = rw[rw_hdg_] + rw[rw_mag_var_]
        local crab = true_hdg - true_rw

        -- normalize, a 36 rwy might give -356°
        if crab < -180 then
            crab = crab + 360
        elseif crab > 180 then
            crab = crab - 360
        end

        -- make sure it never bombs
        if thr_ra == nil then thr_ra = 0.0 end

        line = line ..
            string.format("\nThreshold %s/%s\nAbove: %.f ft / %.f m, Distance: %.f ft / %.f m\n" ..
                          "from CL: %.f ft / %.f m / %.1f°",
                           rw[rw_icao_], rw[rw_designator_], thr_ra * M_2_FT, thr_ra, td_dist * M_2_FT, td_dist,
                           d_crl * M_2_FT, d_crl, crab)
    end

    ipc.setdisplay(30, 600, 600,  200)
    ipc.display(line, show_time)

    local pline = "\n--------------------------------------------------------------------\n" ..
                  line ..
                  "\n--------------------------------------------------------------------\n"
    ipc.log(pline)
end

-- emulate continue via return
local function loop()
    if ipc.readUW(0x0366) == 1 then  -- on ground flag
        if was_airborne then
            display_data()
            was_airborne = false
        end

        ipc.sleep(5000)
        return
    end

    local ra = ipc.readSD(0x31E4) / 65636.0 -- radar altitude m

    if ra > 20 and not was_airborne then    -- transition to airborne
        was_airborne = true
        rw = nil
        rw_dist = 1.0E20
        thr_dist = 1.0E20
        thr_crossed = false
        thr_ra = nil
    end

    if ra >= 500 then
        ipc.sleep(5000) -- dormant
        return
    end

    if ra > 150 then
        if rw ~= nil then   -- zap takeoff rwy
            rw = nil
            rw_dist = 1.0E20
            thr_dist = 1.0E20
            thr_crossed = false
            thr_ra = nil
        end

        ipc.sleep(1000) -- start getting nervous
        return
    end

    -- select runway
    if ra >= 40 then
        local lat, lon = get_pos()
        local r, d = rwdb.nearest_rw(lat, lon)

        if r ~= nil and d < rw_dist then
            rw = r
            rw_dist = d
        end

        ipc.sleep(250)
        return
    end

    -- track crossing of threshold
    if not thr_crossed and rw ~= nil then
        local lat, lon = get_pos()
        local d = rwdb.thr_distance(rw, lat, lon)

        if d < thr_dist then
            thr_dist = d
            thr_ra = ra
        else
            thr_crossed = true  -- distance is increasing again
        end
    end

    if ra > 15 then
        ipc.sleep(250)
        return
    end

    -- come here in touchdown phase
    vs =  get_vs()
    ipc.sleep(25)  -- FSUIPC seems to pick up data with 18 Hz
end

ipc.log("landing_rate " .. VERSION .. " startup")
ipc.setdisplay(30, 600, 600,  180)

_, _, acf_model = string.find(ipc.readSTR(0x3500, 24), "([%a%d]+)")
ipc.log("ACF model: '" .. acf_model .. "'")

_, _, p3d_directory = string.find(ipc.readSTR(0x3E00, 256), "([%a%d%s:\\_%-]+)")
ipc.log("p3d_directory: '" .. p3d_directory .. "'")

script_directory = debug.getinfo(1, "S").source:sub(2)
script_directory = script_directory:match("(.*[/\\])")
ipc.log("script_directory: '" .. script_directory .. "'")

rwdb.build_cache({p3d_directory .. "r5.csv", script_directory .. "r5_patch.csv"})

while true do
    loop()
end