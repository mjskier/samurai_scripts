#!/usr/bin/env python3

# This is a Python test driver to exercise the samurai interface originally developed
# to be called from the Fortran COAMPS-TC driver.
# It reads a file of background observations and puts the data in 3D arrays
# that are then passed to the run command.
#
# Note that Samurai can read that file directly and call the other form of the run command
# So this is really just a way to make sure the array passing interface works.
#
# Bruno Melli Feb 15, 2018

import sys
import pprint

from ctypes import *

libSamPath  = "/home/bpmelli/devel/samurai.mycoamps/build/release/lib/libsamurai.so"
samConfPath = "/home/bpmelli/devel/tryit/psamurai/data/conf.xml"

# Load the samurai library

libSam = cdll.LoadLibrary(libSamPath)

# Create a driver. Use the xml config file call

driver = libSam.create_vardriver3D_From_File(c_char_p(samConfPath.encode('utf-7')), 0)

if driver == 0:
    print('Driver creation failed')
    sys.exit(1)

# Load the background observations from a file
filepath = 'data/45km_Background.in'

# Key is the lat,lon,alt. Values are the index for these given lat,lon.alt

lat_idx = {}
lon_idx = {}
alt_idx = {}

# Key is "x_y"

lats_map = {}
lons_map = {}

# Key is "x_y_z"

u = {}
v = {}
w = {}
t = {}
qv = {}
rhoa = {}
qr = {}

minlat = minlon = minalt = 1000
maxlat = maxlon = maxalt = -1

nlat = nlon = nalt = 0

with open(filepath) as fp:
    for cnt, line in enumerate(fp):
        a = line.split()
        if len(a) != 11:
            print("Bad line {}".format(cnd))
            continue

        v1 = float(a[1])
        v2 = float(a[2])
        v3 = float(a[3])

        # Add lat, lon, alt to their respective hashes if they don't exist
        
        if v1 not in lat_idx:
            lat_idx[v1] = nlat
            nlat += 1
            minlat = min(minlat, v1)
            maxlat = max(maxlat, v1)
            
        if v2 not in lon_idx:
            lon_idx[v2] = nlon
            nlon += 1
            minlon = min(minlon, v2)
            maxlon = max(maxlon, v2)

        if v3 not in alt_idx:
            alt_idx[v3] = nalt
            nalt += 1
            minalt = min(minalt, v3)
            maxalt = max(maxalt, v3)

        # Now v1, v2, v3 have an index. Use them to generate a keys
        
        x = lat_idx[v1]
        y = lon_idx[v2]
        z = alt_idx[v3]

        # 3D arrays
        
        key = "{}_{}_{}".format(x, y, z)
        
        u[key] = float(a[4])
        v[key] = float(a[5])
        w[key] = float(a[6])
        t[key] = float(a[7])
        qv[key] = float(a[8])
        # rhoa[key] = float(a[9])
        # qr[key] = float(a[10])

        # same deal with the 2D arrays

        key = "{}_{}".format(x, y)
        lats_map[key] = v1
        lons_map[key] = v2
        
print('cnt: ', cnt)

print('nlat: ', nlat, ', nlon: ', nlon, ', nalt: ', nalt)
print('minlat: ', minlat, ", maxlat: ", maxlat)
print('minlon: ', minlon, ", maxlon: ", maxlon)
print('minalt: ', minalt, ", maxalt: ", maxalt)

# Get sorted latitudes by order of their indices

salt = sorted(alt_idx, key = alt_idx.get, reverse = True )

# Set sizes.

nx = nlat
ny = nlon
nz = nalt

# Declare some array types so that we can use them in the function prototype

FLOAT_NZ = c_float * nz
FLOAT_2D = c_float * (nx * ny)
FLOAT_3D = c_float * (nx * ny * nz)

# External function prototypes

libSam.run_vardriver3D.argtypes = [c_int, c_int, c_int, c_int,
                                   c_char_p,
                                   c_int, c_int,
                                   c_float, c_float, c_float,
                                   c_float, c_float, c_float,
                                   FLOAT_NZ, FLOAT_2D, FLOAT_2D,
                                   FLOAT_3D, FLOAT_3D, FLOAT_3D,
                                   FLOAT_3D, FLOAT_3D,
                                   FLOAT_3D, FLOAT_3D, FLOAT_3D,
                                   FLOAT_3D, FLOAT_3D]

# Fill in the array arguments

sigmas = FLOAT_NZ()

latitude  = FLOAT_2D()
longitude = FLOAT_2D()
    
u1 = FLOAT_3D()
v1 = FLOAT_3D()
w1 = FLOAT_3D()
th1 = FLOAT_3D()
p1 = FLOAT_3D()

usam = FLOAT_3D()
vsam = FLOAT_3D()
wsam = FLOAT_3D()
thsam = FLOAT_3D()
psam = FLOAT_3D()

# 1D array

for i in range(0, nz):
    sigmas[i] = salt[i]

# 2D arrays

i = 0
for x in range(0, nx):
    for y in range(0, ny):
        key = "{}_{}".format(x, y);
        latitude[i]  = lats_map[key]
        longitude[i] = lons_map[key]
        i += 1

# 3D arrays

i = 0
for x in range(0, nx):
    for y in range(0, ny):
        for z in range(0, nz):
            key = "{}_{}_{}".format(x, y, z);
            u1[i] = u[key]
            v1[i] = v[key]
            w1[i] = w[key]
            th1[i] = t[key]
            p1[i] = qv[key]

            # Not needed since these are return values
            # usam[i] = 0.0
            # vsam[i] = 0.0
            # wsam[i] = 0.0
            # thsam[i] = 0.0
            # psam[i] = 0.0
            i += 1
            
# I need the date to be Sep 29 18:15:00 MDT 2015
# samurai adds delta * iter1 to the date passed in.

delta = 15
iter1 = 60

# Use the same values as the config file
imin = 0.0
imax = 12600.0
i_incr = 45.0

jmin = 0.0
jmax = 6750.0
j_incr = 45.0

# Run the driver

print("Calling run_vardriver3D")

retval =  libSam.run_vardriver3D(driver, nx, ny, nz,
                            c_char_p("2015092918".encode('utf-8')),
                            delta, iter1,
                            imin, imax, i_incr,
                            jmin, jmax, j_incr,
#                            minlat, maxlat, (maxlat - minlat) / nx,
#                            minlon, maxlon, (maxlon - minlon) / ny,
                            sigmas, latitude, longitude,
                            u1, v1, w1, th1, p1,
                            usam, vsam, wsam, thsam, psam) 
print("back from run_vardriver3D")

print(retval)




