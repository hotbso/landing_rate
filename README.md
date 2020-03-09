# landing_rate
prepar3d landing rate monitor / dist from threshold / height above threshold / crab


The program utilizes the runway database extracted from p3d
by Peter Dowson's (free) MakeRwys tool (http://www.fsuipc.com/).
The created file r5.csv is expected in the default location, the main directory of prepar3d.

Unfortunately fields "displacement" and "threshold" are mostly relevant for default markings and of not much
use for payware sceneries with their own textures.
(Per documentation of ADE it should be: threshold = beginning of rw, displacement = distance from beginning to landing threshold).
Some specify coordinates of the landing threshold, some the beginning of the runway.
The displacement may be missing or totally random.

As we want to report height above threshold and distance from threshold there is obviously a problem.

Therefore there is a file r5_patch.csv to be found in fsuipc's main directory, the Modules folder,
where these values can be corrected.
Correct data can be obtained from web sites of relevant authorities (Eurocontrol, FAA) or a measurement in google maps will do as well.

Example:

in r5.csv: (fields are described in docs of MakeRwys)
EDDF,0253,50.045120,8.587028,364,247.630,13099,111.55BDG,230,2.000,50.038868,8.560805,1640,,
     ^    ^                                                                           ^
     25C  rwy start                                                                   displacement in feet

there is no displaced threshold so displacement is wrong, set to 0
in r5_path.csv:
EDDF,0253,50.045120,8.587028,364,247.630,13099,111.55BDG,230,2.000,50.038868,8.560805,0,,

See accompanied r5_patch.csv for more examples.