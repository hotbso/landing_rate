# landing_rate
prepar3d landing rate monitor<br/>
report vs, IAS / dist from threshold / height above threshold / crab angle

It's all LUA and needs a registered version of fsuipc.

The program utilizes the runway database extracted from p3d by Peter Dowson's (free) MakeRwys tool (http://www.fsuipc.com/).
The created file `r5.csv` is expected in the default location, the main directory of prepar3d.

Unfortunately the field "ThresholdOffset" is mostly relevant for default markings and of not much
use for payware sceneries with their own textures.
(Per documentation of ADE it should be: lat/lon = start of rw, ThresholdOffset = distance from start to landing threshold).
Some authors omit a ThresholdOffset or supply totally wrong values.

As we want to report height above threshold and distance from threshold there is obviously a problem.

Therefore there is a file `r5_patch.csv` to be found in fsuipc's main directory, the Modules folder, where these values can be overwritten.
Correct data can be obtained from web sites of relevant authorities (Eurocontrol, FAA, ...), LIDO charts or a bit more involved from Jeppesen charts.<br/>
In general a measurement in google maps will do as well.

Example:
```
Aerosoft EDDF in r5.csv: (fields are described in docs of MakeRwys)
EDDF,0253,50.045120,8.587028,364,247.630,13099,111.55BDG,230,2.000,50.038868,8.560805,1640,,
     ^    ^                                                                           ^
     25C  rwy start                                                                   offset in feet
```
there is no displaced threshold so offset is wrong, set to 0
```
in r5_path.csv:
EDDF,0253,50.045120,8.587028,364,247.630,13099,111.55BDG,230,2.000,50.038868,8.560805,0,,
```

See accompanied r5_patch.csv for more examples.

Installation:
- obtain MakeRwys tool (http://www.fsuipc.com/), extract into p3d top folder
- run MakeRwys as administrator (don't forget to redo after scenery instattions)
- unzip this tool into `Modules` folder
- edit `FSUIPC5.ini` as shown below

```
[Auto]
1=Lua landing_rate
```
The number may vary depending on other lua stuff in your installation.
