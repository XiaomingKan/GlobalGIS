using FileIO, GeoMakie, Makie, ColorSchemes

export createmaps, plotmap

function createmap(gisregion, regions, regionlist, lons, lats, colors, source, dest, xs, ys,
                    landcenters, popcenters, connected, connectedoffshore;
                    lines=false, labels=false, resolutionscale=1, textscale=1, legend=false)
    nreg = length(regionlist)
    scale = maximum(size(regions))/6500

    regions[regions.==NOREGION] .= nreg + 1

    xmin, xmax = extrema(xs)
    ymin, ymax = extrema(ys)
    aspect_ratio = (ymax - ymin) / (xmax - xmin)
    pngwidth = round(Int, resolutionscale*1.02*size(regions,1))                 # allow for margins (+1% on both sides)
    pngsize = pngwidth, round(Int, pngwidth * aspect_ratio)     # use aspect ratio after projection transformation

    println("...constructing map...")
    scene = surface(xs, ys; color=float.(regions), colormap=colors,
                            shading=false, show_axis=false, scale_plot=false, interpolate=false)
    ga = geoaxis!(scene, lons[1], lons[end], lats[end], lats[1]; crs=(src=source, dest=dest,))[end]
    ga.x.tick.color = RGBA(colorant"black", 0.4)
    ga.y.tick.color = RGBA(colorant"black", 0.4)
    ga.x.tick.width = scale
    ga.y.tick.width = scale

    if lines
        println("...drawing transmission lines...")
        for (i,conn) in enumerate([connected, connectedoffshore])
            for reg1 = 1:nreg, reg2 = 1:nreg
                reg1 <= reg2 && continue
                !conn[reg1, reg2] && continue
                # line = [lonlatpoint(popcenters[reg1,:]), lonlatpoint(popcenters[reg2,:])]     # straight line on projected map
                line = greatcircletrack(popcenters[reg1,:], popcenters[reg2,:], 50)             # great circle segments
                projectedline = Point2f0.(GeoMakie.transform.(source, dest, line))
                color = (i == 1) ? :black : :white
                lines!(scene, projectedline, color=color, linewidth=resolutionscale*scale*3)
            end
        end
    end
    if labels
        for reg = 1:nreg
            pos = Point2f0(GeoMakie.transform(source, dest, lonlatpoint(landcenters[reg,:])))
            text!(scene, string(regionlist[reg]); position=pos, align=(:center,:center), textsize=textscale*scale*50000)
        end
    end

    println("...saving...")
    mkpath(in_datafolder("output"))
    filename = in_datafolder("output", "$gisregion.png")
    isfile(filename) && rm(filename)
    Makie.save(filename, scene, resolution=pngsize)
    if legend
        makelegend(regionlist, colors[2:end-1])
        img = load(filename)
        legend = autocrop(load(in_datafolder("output", "legend.png")))
        height = max(size(img,1), size(legend,1))
        legendwidth = size(legend, 2)
        combined = [ypad(img, height) ypad(legend, height) fill(RGB{N0f8}(1.0,1.0,1.0), (height, 550 - legendwidth))]
        FileIO.save(filename, combined)
        rm(in_datafolder("output", "legend.png"))
    end
end

function createmaps(gisregion; scenarioyear="ssp2_2050", lines=true, labels=true, resolutionscale=1, textscale=1, randseed=1, downsample=1)
    regions, offshoreregions, regionlist, lonrange, latrange = loadregions(gisregion)
    regions = regions[1:downsample:end, 1:downsample:end]
    offshoreregions = offshoreregions[1:downsample:end, 1:downsample:end]
    lonrange = lonrange[1:downsample:end]
    latrange = latrange[1:downsample:end]
    textscale *= downsample
    nreg = length(regionlist)

    println("Mapping colors to regions (avoid same color in adjacent regions)...")
    mergeregions = copy(regions)
    mergeregions[regions.==0] .= offshoreregions[regions.==0]
    mergeconnected = connectedregions(mergeregions, nreg)
    colorindices = greedycolor(mergeconnected, 1:7, 1:nreg, randseed=randseed)
    onshorecolors = [RGB(0.2,0.3,0.4); colorschemes[:Set2_7].colors[colorindices]; RGB(0.4,0.4,0.4)]
    offshorecolors = [RGB(0.4,0.4,0.4); colorschemes[:Set2_7].colors[colorindices]; RGB(0.2,0.3,0.4)]

    println("\nProjecting coordinates (Mollweide)...")
    res = 0.01
    res2 = res/2
    lons = (-180+res2:res:180-res2)[lonrange]         # longitude values (pixel center)
    lats = (90-res2:-res:-90+res2)[latrange]          # latitude values (pixel center)
    source = LonLat()
    dest = Projection("+proj=moll +lon_0=$(mean(lons))")
    xs, ys = xygrid(lons, lats)
    Proj4.transform!(source, dest, vec(xs), vec(ys))

    println("\nFinding interregional transmission lines...")
    geocenters, popcenters = getregioncenters(regions, nreg, lonrange, latrange, res, scenarioyear)   # column order (lat,lon)
    landcenters = find_landarea_near_popcenter(regions, nreg, popcenters, lonrange, latrange, res)
    connected = connectedregions(regions, nreg)
    connectedoffshore = connectedregions(offshoreregions, nreg)
    connectedoffshore[connected] .= false

    println("\nOnshore map...")
    createmap(gisregion, regions, regionlist, lons, lats, onshorecolors, source, dest, xs, ys,
        landcenters, popcenters, connected, connectedoffshore, lines=lines, labels=labels, resolutionscale=resolutionscale, textscale=textscale)
    println("\nOffshore map...")
    createmap("$(gisregion)_offshore", offshoreregions, regionlist, lons, lats, offshorecolors, source, dest, xs, ys,
        landcenters, popcenters, connected, connectedoffshore, lines=false, labels=false, resolutionscale=resolutionscale, textscale=textscale)
    # exit()
    return nothing
end

# ColorBrewer Set2_7:  https://juliagraphics.github.io/ColorSchemes.jl/stable/basics/#colorbrewer-1
function maskmap(mapname, regions, regionlist, lonrange, latrange;
                    resolutionscale=1, textscale=1, randseed=1, legend=false, downsample=1)
    regions = regions[1:downsample:end, 1:downsample:end]
    lonrange = lonrange[1:downsample:end]
    latrange = latrange[1:downsample:end]
    nreg = length(regionlist)

    colors = [
        RGB([174,140,114]/255...),  # bad land type
        RGB([214,64,64]/255...),    # high population
        RGB([255,100,255]/255...),  # protected area
        RGB([120,170,80]/255...),   # no grid
        RGB([255,217,47]/255...),   # solar plant A
        RGB([215,160,0]/255...),    # solar plant B
        RGB([140,156,209]/255...),  # wind plant A
        RGB([110,136,169]/255...),  # wind plant B
    ]

    println("Mapping colors to regions (avoid same color in adjacent regions)...")
    connected = connectedregions(regions, nreg)
    # colorindices = (nreg > 7) ? greedycolor(connected, 1:7, 1:nreg, randseed=randseed) : collect(1:nreg)
    # colors = colorschemes[Symbol("Set2_$nreg")].colors[colorindices]
    onshorecolors = [RGB(0.3,0.3,0.45); colors; RGB(0.4,0.4,0.4)]

    println("\nProjecting coordinates (Mollweide)...")
    res = 0.01
    res2 = res/2
    lons = (-180+res2:res:180-res2)[lonrange]         # longitude values (pixel center)
    lats = (90-res2:-res:-90+res2)[latrange]          # latitude values (pixel center)
    source = LonLat()
    dest = Projection("+proj=moll +lon_0=$(mean(lons))")
    xs, ys = xygrid(lons, lats)
    Proj4.transform!(source, dest, vec(xs), vec(ys))

    println("\nOnshore map...")
    scene = createmap(mapname, regions, regionlist, lons, lats, onshorecolors, source, dest, xs, ys,
        [], [], connected, connected, lines=false, labels=false, resolutionscale=resolutionscale, textscale=textscale, legend=legend)
    return nothing
end

function autocrop(img, padding::Int=0)
    rowrange = dataindexes_lat(vec(any(img .!= RGB(1.0,1.0,1.0), dims=2)), padding)
    colrange = dataindexes_lat(vec(any(img .!= RGB(1.0,1.0,1.0), dims=1)), padding)   # use _lat both times (_lon does it circularly) 
    return img[rowrange, colrange]
end

function ypad(img, newheight)
    height, width = size(img)
    height == newheight && return img
    height > newheight && error("Can't pad an image to a smaller size.")
    firstrow = (newheight - height) ÷ 2
    newimg = fill(RGB{N0f8}(1.0,1.0,1.0), (newheight, width))
    newimg[firstrow:(firstrow + height - 1), :] = img
    return newimg
end

function makelegend(labels, colors; scale=2)
    i = .!isempty.(labels)
    labels = labels[i]     # don't plot legend entries with empty labels
    colors = colors[i]
    len = length(labels)
    markerpositions = Point2f0.(0, len:-1:1) .* scale
    textpositions = Point2f0.(0.7, (len:-1:1) .+ 0.03) .* scale
    scene = scatter(
        markerpositions,
        color = colors,
        marker = :rect,
        markersize = 0.8 * scale,
        show_axis = false
    )
    annotations!(
        scene,
        labels,
        textpositions,
        align = (:left, :center),
        textsize = 0.4 * scale,
        raw = true
    )
    update_cam!(scene, FRect(-scale, 0, 2, 10 + 1))     # allow for 10 lines (to get constant text size for any number of labels)
    filename = in_datafolder("output", "legend.png")
    isfile(filename) && rm(filename)
    Makie.save(filename, scene, resolution = scene.resolution.val .* scale)
end

# first color in colorlist that is not in columncolors (which may have many repeated elements)
function firstcolor(columncolors, colorlist)
    colorcounts = zeros(Int, length(colorlist))
    for c in columncolors
        if c > 0
            colorcounts[colorlist[c]] += 1
        end
    end
    goodcolors = colorlist[colorcounts.==0]
    return isempty(goodcolors) ? 0 : rand(goodcolors)
end

function greedycolor(connected, colorlist, order; randseed=0)
    randseed > 0 && Random.seed!(randseed)
    n = size(connected, 1)
    colors = zeros(Int, n)
    for i in order
        columncolors = colors[connected[:,i]]
        col = firstcolor(columncolors, colorlist)
        if col == 0
            println("All colors used, retrying with randseed=$(randseed+1)...")
            return greedycolor(connected, colorlist, order; randseed=randseed+1)
        end
        colors[i] = col
    end
    # display(countmap(colors))
    return colors
end

# reverse coordinate order 
lonlatpoint(latlon) = Point2f0(latlon[2], latlon[1])

# returns great circle track between points given as Point2f0 objects (lon, lat order, in degrees).
greatcircletrack(point1::AbstractArray, point2::AbstractArray, segments) = Point2f0.(greatcircletrack(Tuple(point1), Tuple(point2), segments))

# returns great circle track between points given as (lon, lat) tuples (in degrees).
greatcircletrack(point1::Tuple, point2::Tuple, segments) = [reverse(intermediatepoint(point1, point2, f)) for f in LinRange(0, 1, segments)]



# intermediatepoint() ported from Javascript to Julia
# Source: https://www.movable-type.co.uk/scripts/latlong.html, original name 'intermediatePointTo()'
#
# Returns the point on a great circle at given fraction between point1 and point2.
# 
# @param   {Tuple} point1 - (latitude,longitude) of starting point in degrees.
# @param   {Tuple} point2 - (latitude,longitude) of destination point in degrees.
# @param   {number} fraction - Fraction between the two points (0 = starting point, 1 = destination point).
# @returns {Tuple} Intermediate point between this point and destination point (latitude,longitude).
# 
# @example
#   p1 = (52.205, 0.119)
#   p2 = (48.857, 2.351)
#   pInt = intermediatePointTo(p1, p2, 0.25)    # 51.3721°N, 0.7073°E
function intermediatepoint(point1::Tuple, point2::Tuple, fraction)
    φ1, λ1 = point1
    φ2, λ2 = point2
    
    Δφ = φ2 .- φ1   # distance between points
    Δλ = λ2 .- λ1   # distance between points
    a = sind(Δφ/2)*sind(Δφ/2) + cosd(φ1)*cosd(φ2)*sind(Δλ/2)*sind(Δλ/2)
    δ = 2 * atan(sqrt(a), sqrt(1-a))   # radians

    A = sin((1-fraction)*δ) / sin(δ)
    B = sin(fraction*δ) / sin(δ)

    x = A*cosd(φ1)*cosd(λ1) + B*cosd(φ2)*cosd(λ2)
    y = A*cosd(φ1)*sind(λ1) + B*cosd(φ2)*sind(λ2)
    z = A*sind(φ1) + B*sind(φ2)

    lat = atand(z, sqrt(x^2 + y^2))
    lon = atand(y, x)
    return (lat, lon)
end

plotmap(x; args...) = heatmap(reverse(x, dims=2); scale_plot=false, args...)

function plottraining(countryname)
    df, _ = loadtrainingdata()
    cc = df[:, :country] .== countryname
    normdemand = loaddemanddata()[cc, :normdemand]
    # normalize temp1 to the range [0.5, 1.5] for the 5%-95% quantiles
    normtemp1 = (df[cc,:temp1] .- df[cc,:temp1_qlow]) ./ (df[cc,:temp1_qhigh] .- df[cc,:temp1_qlow]) .+ 0.5
    t = 1:8760
    plot(t, normdemand, color=:black, limits=FRect(0,0,9000,50))
    plot!(t, normtemp1, color=:blue)
end

function plottimezones()
    tzindices, tznames = loadtimezones(1:36000, 1:18000)
    nreg = length(tznames)
    cc = connectedregions(tzindices, nreg)
    colorindices = greedycolor(cc, 1:12, 1:nreg, randseed=494)
    cs = colorschemes[:Set3_12].colors[colorindices]
    plotmap(tzindices[1:5:end, 1:5:end], colormap=cs)
end

function plottimeoffsets()
    tzindices, tznames = loadtimezones(1:36000, 1:18000)
    tz = [n[1:3] == "Etc" ? TimeZone(n, TimeZones.Class(:LEGACY)) : TimeZone(n) for n in tznames]
    offsetlist = tzoffset.(tz)
    offsetvalues = sort(unique(offsetlist))
    offsetdata = [offsetlist[tzi] for tzi in tzindices]
    offsetindices = indexin(offsetdata, offsetvalues)
    nreg = length(offsetvalues)
    cc = connectedregions(offsetindices, nreg)
    colorindices = greedycolor(cc, 1:12, 1:nreg, randseed=1)
    cs = colorschemes[:Set3_12].colors[colorindices]
    plotmap(offsetindices[1:5:end, 1:5:end], colormap=cs)
end
