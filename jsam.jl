#!/usr/local/bin/julia-0.6

# This is a Julia test driver to exercise the samurai interface originally developed
# to be called from the Fortran COAMPS-TC driver.
# It reads a file of background observations and puts the data in 3D arrays
# that are then passed to the run command.
#
# Note that Samurai can read that file directly and call the other form of the run command
# So this is really just a way to make sure the array passing interface works.
#
# Bruno Melli Feb 15, 2018


samConfPath = "/home/bpmelli/devel/tryit/psamurai/data/conf.xml"

# The driver is an opaque structure. Create a type to make its use obvious

mutable struct opaque
end

# First step is to init a VarDriver3D.
# This shows how to call a function from a C/C++ library

# Create a driver3D, init it from an xml file

driver = ccall( (:create_vardriver3D_From_File, "libsamurai"),
           Ptr{opaque},
           (Cstring,), samConfPath)

if driver == 0
    println("Driver creation failed. Aborting")
    exit(1)
end

# Variables used to process background observatons

# 1D

lat_idx = Dict{Float64, Int32}()
lon_idx = Dict{Float64, Int32}()
alt_idx = Dict{Float64, Int32}()

# 2D

lats_map = Dict{AbstractString, Float32}()
lons_map = Dict{AbstractString, Float32}()

# 3D

u    = Dict{AbstractString, Float32}()
v    = Dict{AbstractString, Float32}()
w    = Dict{AbstractString, Float32}()
t    = Dict{AbstractString, Float32}()
qv   = Dict{AbstractString, Float32}()
rhoa = Dict{AbstractString, Float32}()
qr   = Dict{AbstractString, Float32}()

minlat = minlon = minalt = 1000
maxlat = maxlon = maxalt = -1

nlat = nlon = nalt = 1

# Load the background observations from a file, and store them in multiple arrays

filepath = "data/45km_Background.in"

open(filepath) do f
    line = 0
    for ln in eachline(f)
        line += 1
        words = split(ln)
        if size(words, 1) != 11
            println("Bad input at line ", line)
            continue
        end

        v1 = parse(Float32, words[2])
        v2 = parse(Float32, words[3])
        v3 = parse(Float32, words[4])

        # Add values to their respective dicts if they don't exist
        
        if ! haskey(lat_idx, v1)
            lat_idx[v1] = nlat
            global nlat += 1
            global minlat = min(minlat, v1)
            global maxlat = max(maxlat, v1)
        end

        if ! haskey(lon_idx, v2)
            lon_idx[v2] = nlon
            global nlon += 1
            global minlon = min(minlon, v2)
            global maxlon = max(maxlon, v2)
        end

        if ! haskey(alt_idx, v3)
            alt_idx[v3] = nalt
            global nalt += 1
            global minalt = min(minalt, v3)
            global maxalt = max(maxalt, v3)
        end

        # Now that we know v* have entries in the index maps, get their stored index
        
        x = lat_idx[v1]
        y = lon_idx[v2]
        z = alt_idx[v3]

        # use them to create a key
        
        key = "$x-$y-$z"

        # And use that key to store the data values in the 3D arrays
        
        u[key] = parse(Float32, words[5])
        v[key] = parse(Float32, words[6])
        w[key] = parse(Float32, words[7])
        t[key] = parse(Float32, words[8])
        qv[key] = parse(Float32, words[9])

        # Same deal for the 2D arrays
        
        key = "$x-$y"
        lats_map[key] = v1
        lons_map[key] = v2
        
        # what about rhoa and qr ???
    end # each line
end # processing file

nlat -= 1
nlon -= 1
nalt -= 1
    
println("nlat: ", nlat, ", nlon: ", nlon, ", nalt: ", nalt)

# Get arrays of alts by sorting the dictionary by values

salts = sort(collect(zip(values(alt_idx), keys(alt_idx))), rev=true)

# Fill in the array arguments

# 1D array

sigma = Array{Float32}(nalt)

for i = 1:nalt
    sigma[i] = salts[i][2];
end

# 2D arrays

latitude  = Array{Float32}(nlat * nlon)
longitude = Array{Float32}(nlat * nlon)

i = 1
for x = 1:nlat
    for y = 1:nlon
        key = "$x-$y"
        latitude[i]  = lats_map[key]
        longitude[i] = lons_map[key]
        i += 1
    end
end

# 3D arrays

u1  = Array{Float32}(nlat * nlon * nalt)
v1  = Array{Float32}(nlat * nlon * nalt)
w1  = Array{Float32}(nlat * nlon * nalt)
th1 = Array{Float32}(nlat * nlon * nalt)
p1  = Array{Float32}(nlat * nlon * nalt)

usam  = Array{Float32}(nlat * nlon * nalt)      # These are return values, so no need to initialize
vsam  = Array{Float32}(nlat * nlon * nalt)
wsam  = Array{Float32}(nlat * nlon * nalt)
thsam = Array{Float32}(nlat * nlon * nalt)
psam  = Array{Float32}(nlat * nlon * nalt)

i = 1
for x = 1:nlat
    for y = 1:nlon
        for z = 1:nalt
            key = "$x-$y-$z"
            u1[i]  = u[key]
            v1[i]  = v[key]
            w1[i]  = w[key]
            th1[i] = t[key]
            p1[i]  = qv[key]
            i += 1
        end
    end
end


# I need the date to be Sep 29 18:15:00 MDT 2015
# samurai adds delta * iter1 to the date passed in.
# TODO make these arguments to the script so that we can test multiple
# calls

date = "2015092918"
delta = 15
iter1 = 60

# Use the same values that were in the config file for the 45km test case.
# TODO: These too could be read from arguments.

imin = 0.0
imax = 12600.0
iincr = 45.0

jmin = 0.0
jmax = 6750.0
jincr = 45.0

println("Running driver")

# ccall needs:
# function name
# library (you might need to set LD_LIBRARY_PATH to find it)
# return type
# parameter types
# the actual parameters

retval = ccall( (:run_vardriver3D, "libsamurai"),
                Int32,                          # return value
                
                (Ptr{opaque},                   # driver handle
                 Int32, Int32, Int32,           # nx, ny, nz
                 Cstring,                       # date and hour
                 Int32, Int32,                  # delta and ierator
                 Float32, Float32, Float32,     # imin, imax, iincr
                 Float32, Float32, Float32,     # jmin, jmax, jincr
                 Ptr{Float32},                  # sigma
                 Ptr{Float32},                  # latitude
                 Ptr{Float32},                  # longitude
                 Ptr{Float32},                  # u1
                 Ptr{Float32},                  # v1
                 Ptr{Float32},                  # w1
                 Ptr{Float32},                  # th1
                 Ptr{Float32},                  # p1

                 Ptr{Float32},                  # usam
                 Ptr{Float32},   
                 Ptr{Float32},
                 Ptr{Float32},
                 Ptr{Float32},),
                
                driver, nlat, nlon, nalt,
                date, delta, iter1,
                imin, imax, iincr,
                jmin, jmax, jincr,
                sigma, latitude, longitude,
                u1, v1, w1, th1, p1,
                usam, vsam, wsam, thsam, psam)

println("retval: ", retval)

# TODO: process the return values (*sam)

