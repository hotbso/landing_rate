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


ipc.setdisplay(30, 600, 300,  120)

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

local rw, rw_dist

local function get_a3xx_rating(vs)
    for i, r in ipairs(a3xx_ratings) do
        if vs <= r[1] then return r[2] end
    end
    return ""
end

local function logvs()
    local vs_td = -ipc.readSD(0x030C) * 60 * 3.28084 / 256 -- vs at touch down fpm
    vs_sm = alpha * vs_td + (1.0 - alpha) * vs_sm

    local g = ipc.readSW(0x11B8) / 624.0
    local ias = ipc.readSD(0x02B8) / 128
    
    if vs_td > 25 then
        local line = string.format("vs : %0.0f fpm\nIAS: %0.1f kn", vs_sm, ias)

        if acf_model == "A320" or acf_model == "A321" or acf_model == "A319" then
            local rating = get_a3xx_rating(vs_td)
            line = line .. "\n" .. rating
        end
        
        ipc.display(line, 30)
    end
end

local function get_pos()
    local lat = ipc.readDBL(0x6010)
    local lon = ipc.readDBL(0x6018)
    return lat, lon
end

-- emulate continue via return
local function loop()
    if ipc.readUW(0x0366) == 1 then  -- on ground flag
        if was_airborne then
            if rw ~=nil then
                ipc.log(string.format("nearest rw %s %s", rw[rw_icao_], rw[rw_designator_]))
                local lat, lon = get_pos()
                local td_x, td_y = rwdb.mk_thr_vec(rw, lat, lon)
                local td_dist = rwdb.vec_length(td_x, td_y)
                local crl_x, crl_y = rwdb.mk_ctrl_uvec(rw)
                local d_crl = td_x * crl_y - td_y * crl_x
                ipc.log(string.format("lat: %0.5f, lon: %0.5f, dist: %0.0f ofs: %0.0f", lat, lon, td_dist, d_crl))
            end
            logvs()
            was_airborne = false
        end

        ipc.sleep(5000)
        return
    end

    local ra = ipc.readSD(0x31E4) / 65636.0 -- radar altitude m

    if ra > 20 and not was_airborne then
        was_airborne = true
        td_phase = false
        rw = nil
        rw_dist = 1.0E20
    end
    
    if ra > 500 then
        ipc.sleep(5000)
        return
    end

    -- select runway
    if 150 > ra and ra > 40 then
        local lat, lon = get_pos()
        local r, d = rwdb.nearest_rw(lat, lon)

        if r ~= nil and d < rw_dist then
            rw = r
            rw_dist = d
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
r5csv_path = "..\\"
rwdb = require("rwdb")

_, _, acf_model = string.find(ipc.readSTR(0x3500, 24), "([%a%d]+)")
ipc.log("ACF model: '" .. acf_model .. "'")

while true do
    loop()
end