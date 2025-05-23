using MiniFB
using ArgParse
using Images
using BenchmarkTools
using Random

function black_window()
    WIDTH = 800
    HEIGHT = 600
    WINDOW_TITLE = "A Black Window"
    WINDOW_FLAGS = MiniFB.WF_RESIZABLE

    window = mfb_open_ex("$WINDOW_TITLE", WIDTH, HEIGHT, WINDOW_FLAGS)
    buffer = zeros(UInt32, WIDTH * HEIGHT)
    while true

        state = mfb_update(window, buffer)
        if state != MiniFB.STATE_OK
            break
        end
    end
end


function plasma()
    palette = zeros(UInt32, 512)
    WIDTH = 320
    HEIGHT = 240
    inc = 90 / 64;

    for c in 1:64
        col = round(Int, (
            255 * sin( (c-1) *  inc * π / 180) + 0.5
        ))

        palette[64 + c] = mfb_rgb(col, 0, 0)
        palette[64*1 + c] = mfb_rgb(255, col,0)
        palette[64*2 + c] = mfb_rgb(255-col, 255, 0)
        palette[64*3 + c] = mfb_rgb(0, 255, 0)
        palette[64*4 + c] = mfb_rgb(0, 255-col, 255)
        palette[64*5 + c] = mfb_rgb(col, 0, 255)
        palette[64*6 + c] = mfb_rgb(255, 0, 255-col)
        palette[64*7 + c] = mfb_rgb(255-col, 0, 0)
    end

    window = mfb_open_ex("Plasma Test", WIDTH, HEIGHT, MiniFB.WF_RESIZABLE)
    buffer = zeros(UInt32, WIDTH * HEIGHT)
    mfb_set_target_fps(10)

    time = 0
    while mfb_wait_sync(window)
        time_x = sin(time * π / 180)
        time_y = cos(time * π / 180)
        i = 1
        for y in 1:HEIGHT
            dy = cos((y * time_y) * π / 180)
            for x in 1:WIDTH
                dx = sin((x * time_x) * π / 180)
                idx = round(Int, ((2 + dx + dy) * 0.25* 511) + 1)
                buffer[i] = palette[idx]
                i = i + 1
            end
        end
        time += 1
        state = mfb_update(window, buffer)
        if state !=MiniFB.STATE_OK
            break;
        end
    end
    mfb_close(window)
end

# plasma()

function parse_commandline()
    s = ArgParseSettings(
        description = "Description: ",
        version = "Version 0.1",
        add_version = true
    )

    @add_arg_table s begin
        "--image", "-i"
            help = "Pass image filepath"
            required = true
    end

    return parse_args(s)
end

# Bresenham's line algorithm (more direct implementation)
# adapted from https://github.com/rdeits/convex-segmentation/blob/master/julia/bresenham.jl
function Line(x1::Int64, y1::Int64, x2::Int64, y2::Int64)
    dx = abs(x2 - x1)
    dy = abs(y2 - y1)

    sx = x1 < x2 ? 1 : -1
    sy = y1 < y2 ? 1 : -1

    err = dx - dy

    x = x1
    y = y1

    x_coords = Int64[]
    y_coords = Int64[]

    while true
        push!(x_coords, x)
        push!(y_coords, y)

        if x == x2 && y == y2
            break
        end

        e2 = 2 * err
        if e2 > -dy
            err -= dy
            x += sx
        end
        if e2 < dx
            err += dx
            y += sy
        end
    end

    x_coords, y_coords
end

function Line(x1, y1, x2, y2)
	Line([int(round(z)) for z in [x1, y1, x2, y2]]...)
    # rounds the given values into integers
end

function apply!(approx, changes)
    for (pos, new_colour) in changes
        approx[pos] = new_colour
    end
end

function tick!(rng::AbstractRNG, target::Matrix{<:Colorant}, approx::Matrix{<:Colorant})

    beg_x = rand(rng, 1:1:size(target, 1))
    beg_y = rand(rng, 1:1:size(target, 2))

    end_x = rand(rng, 1:1:size(target, 1))
    end_y = rand(rng, 1:1:size(target, 2))

    r = rand(rng)
    g = rand(rng)
    b = rand(rng)

    colour = RGB{Float32}(r, g, b)
    x_coords, y_coords = Line(beg_x, beg_y, end_x, end_y)

    changes = [(CartesianIndex(x, y), colour) for (x, y) in zip(x_coords, y_coords)]

    loss_delta_val = loss_delta(target, approx, changes)

    if loss_delta_val >= 0
        return false
    end

    apply!(approx, changes)
    return true
end


function pixel_loss(a::Matrix{<:Colorant}, b::Matrix{<:Colorant})
    a = convert(Matrix{RGB{Float32}}, a)
    b = convert(Matrix{RGB{Float32}}, b)

    r_diffs = (red.(a) .- red.(b)).^2
    g_diffs = (green.(a) .- green.(b)).^2 
    b_diffs = (blue.(a) .- blue.(b)).^2

    return sum(r_diffs .+ g_diffs .+ b_diffs)
end

function loss_delta(target::Matrix{<:Colorant}, source::Matrix{<:Colorant}, changes::Vector{Tuple{CartesianIndex{2}, RGB{Float32}}})
    total_loss = 0.0

    for (pos, new_colour) in changes
        target_colour = convert(RGB{Float32}, target[pos])
        approx_colour = convert(RGB{Float32}, approx[pos])
        new_colour_f32 = convert(RGB{Float32}, new_colour)

        loss_without_changes = pixel_loss(reshape([target_colour],1,1), reshape([approx_colour],1,1))
        loss_with_changes = pixel_loss(reshape([target_colour],1,1), reshape([new_colour_f32],1,1))

        total_loss += (loss_with_changes - loss_without_changes)
    end

    return total_loss
end    

function main()
    parsed_args = parse_commandline()
    img_filepath = parsed_args["image"]
    # global img = load("test.jpg")
    global img = load(img_filepath)
    global img2 = copy(img)
    println("Pixel loss is ", pixel_loss(img, img2))
    # println("Line coordinates are:", Line(2, 0, 5, 6))

    # @btime pixel_loss(img, img2)
end

main()