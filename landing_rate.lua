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

local acf_model

local was_airborne = false
local td_phase = false -- touchdown phase

-- we use a mild exponential smoother to unjitter vs
local alpha = 0.9
local vs_sm = 0.0

local rw, rw_dist, thr_dist, thr_ra

local function get_pos()
    local lat = ipc.readDD(0x560) * 90.0 / (10001750.0 * 2^32)
    local lon = ipc.readDD(0x568) * 360.0 / 2^64
    return lat, lon
end

local function get_a3xx_rating(vs)
    for i, r in ipairs(a3xx_ratings) do
        if vs <= r[1] then return r[2] end
    end
    return ""
end

local function display_data()
    local vs_td = -ipc.readSD(0x030C) * 60 * 3.28084 / 256 -- vs at touch down fpm
    vs_sm = alpha * vs_td + (1.0 - alpha) * vs_sm

    -- unreliable local g = ipc.readSW(0x11B8) / 624.0
    local ias = ipc.readSD(0x02B8) / 128

    local line = string.format("vs : %0.0f fpm\nIAS: %0.1f kn", vs_sm, ias)

    if acf_model == "A320" or acf_model == "A321" or acf_model == "A319" then
        local rating = get_a3xx_rating(vs_td)
        line = line .. "\n" .. rating
    end

    if rw ~=nil then
        ipc.log(string.format("nearest rw %s %s", rw[rw_icao_], rw[rw_designator_]))
        local lat, lon = get_pos()
        local td_x, td_y = rwdb.mk_thr_vec(rw, lat, lon)
        local td_dist = rwdb.vec_length(td_x, td_y)         -- dist from threshold
        local crl_x, crl_y = rwdb.mk_ctrl_uvec(rw)          -- centerline unit vector
        local d_crl = td_x * crl_y - td_y * crl_x           -- ofs from centerline

        local true_hdg = ipc.readUD(0x580) * 360 / 2^32
        local true_rw = rw[rw_hdg_] + rw[rw_mag_var_]
        local crab = true_hdg - true_rw

        ipc.log(string.format("lat: %0.5f, lon: %0.5f, dist: %0.0f ofs: %0.0f", lat, lon, td_dist, d_crl))
        ipc.log(string.format("height above thr: %0.1f", thr_ra))
        line = line ..
            string.format("\nThreshold %s/%s\nAbove: %.f ft / %.f m, Distance: %.f ft / %.f m\n" ..
                          "from CL: %.f ft / %.f m / %.1f°",
                           rw[rw_icao_], rw[rw_designator_], thr_ra * M_2_FT, thr_ra, td_dist * M_2_FT, td_dist,
                           d_crl * M_2_FT, d_crl, crab)
    end

    ipc.setdisplay(30, 600, 600,  200)
    ipc.display(line, 30)
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
        td_phase = false
        rw = nil
        rw_dist = 1.0E20
        thr_dist = 1.0E20
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
    if rw ~= nil then
        local lat, lon = get_pos()
        local d = rwdb.thr_distance(rw, lat, lon)
        if d < thr_dist then
            thr_dist = d
            thr_ra = ra
        end
    end

    if ra > 15 then
        ipc.sleep(250)
        return
    end

    -- come here in touchdown phase
    local vs = -ipc.readSD(0x02C8) * 60 * 3.28084 / 256  -- fpm

    if not td_phase then -- catch the transition to td_phase
        td_phase = true
        vs_sm = vs
    else
        vs_sm = alpha * vs + (1.0 - alpha) * vs_sm
    end

    ipc.sleep(30) -- ~ 1 frame
end

ipc.log("landing_rate startup")
ipc.setdisplay(30, 600, 600,  180)
rwdb = require("rwdb")

_, _, acf_model = string.find(ipc.readSTR(0x3500, 24), "([%a%d]+)")
ipc.log("ACF model: '" .. acf_model .. "'")

while true do
    loop()
end