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
            arg_type = String
        "--iterations", "-n"
            help = "Number of iterations"
            required = true
            arg_type = Int
        "--output", "-o"
            help = "Output filepath for the final image"
            arg_type = String
            default = nothing
    end

    return parse_args(s)
end

# Bresenham's line algorithm (more direct implementation)
# adapted from https://github.com/rdeits/convex-segmentation/blob/master/julia/bresenham.jl
function Line(x1::Int, y1::Int, x2::Int, y2::Int)
    dx = abs(x2 - x1)
    dy = abs(y2 - y1)

    sx = x1 < x2 ? 1 : -1
    sy = y1 < y2 ? 1 : -1

    err = dx - dy

    x = x1
    y = y1

    x_coords = Int[]
    y_coords = Int[]

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

function Line(x1::Real, y1::Real, x2::Real, y2::Real)
	Line(round(Int, x1), round(Int, y1), round(Int, x2), round(Int, y2))
    # rounds the given values into integers
end

function apply!(approx::AbstractMatrix{<:Colorant}, changes::Vector{Tuple{CartesianIndex{2}, RGB{Float32}}})
    @inbounds for (pos, new_colour) in changes
        approx[pos] = new_colour
    end
end


function tick!(rng::AbstractRNG, target::AbstractMatrix{<:Colorant}, approx::AbstractMatrix{<:Colorant})::Bool

    size(target) == size(approx) || error("Target and approx matrices must have same dimensions.")

    img_rows, img_cols = size(target)

    # Randomly pick start and end points for the line within image dimensions
    beg_row = rand(rng, 1:img_rows)
    beg_col = rand(rng, 1:img_cols)
    end_row = rand(rng, 1:img_rows)
    end_col = rand(rng, 1:img_cols)

    r = rand(rng)
    g = rand(rng)
    b = rand(rng)

    colour = RGB{Float32}(r, g, b)
    row_coords, col_coords = Line(beg_row, beg_col, end_row, end_col)

    changes = Tuple{CartesianIndex{2}, RGB{Float32}}[]
    for (r, c) in zip(row_coords, col_coords)
        if 1 <= r <= img_rows && 1 <= c <= img_cols
            push!(changes, (CartesianIndex(r, c), colour))
        end
    end

    loss_delta_val = loss_delta(target, approx, changes)
    # println("Loss delta: ", loss_delta_val)
    if loss_delta_val >= 0
        return false
    end

    apply!(approx, changes)
    return true
end


function pixel_loss(a::Colorant, b::Colorant)
    a_rgb = convert(RGB{Float32}, a)
    b_rgb = convert(RGB{Float32}, b)

    r_diff = (red(a_rgb) - red(b_rgb))^2
    g_diff = (green(a_rgb) - green(b_rgb))^2
    b_diff = (blue(a_rgb) - blue(b_rgb))^2

    return r_diff + g_diff + b_diff
end

function pixel_loss(a::AbstractMatrix{<:Colorant}, b::AbstractMatrix{<:Colorant})
    size(a) == size(b) || throw(DimensionMismatch("Matrices must have the same size"))

    total_diff = 0.0
    @inbounds for i in eachindex(a)
        total_diff += pixel_loss(a[i], b[i])
    end
    return total_diff
end

function loss_delta(target::AbstractMatrix{<:Colorant}, source::AbstractMatrix{<:Colorant}, changes::Vector{Tuple{CartesianIndex{2}, RGB{Float32}}})
    total_delta_loss = 0.0

    for (pos, new_colour) in changes
        target_colour = convert(RGB{Float32}, target[pos])
        current_source_colour = convert(RGB{Float32}, source[pos])
        proposed_new_colour = convert(RGB{Float32}, new_colour)

        loss_without_change = pixel_loss(target_colour, current_source_colour)
        loss_with_change = pixel_loss(target_colour, proposed_new_colour)

        total_delta_loss += (loss_with_change - loss_without_change)
    end

    return total_delta_loss
end

function approx_encode!(approx::AbstractMatrix{<:Colorant}, canvas::Vector{UInt32})
    rows = size(approx, 1)
    cols = size(approx, 2)
    idx = 1

    for r_idx in 1:rows
        for c_idx in 1:cols
            pixel = approx[r_idx, c_idx]

            r = round(UInt32, red(pixel) * 255)
            g = round(UInt32, green(pixel) * 255)
            b = round(UInt32, blue(pixel) * 255)
            canvas[idx] = (0xFF << 24) | (r << 16) | (g << 8) | b
            idx += 1
        end
    end
    return nothing
end

function main()
    parsed_args = parse_commandline()
    img_filepath = parsed_args["image"]
    iterations = parsed_args["iterations"]
    output_filepath = parsed_args["output"]

    target = load(img_filepath)
    if !(eltype(target) <: Colorant)
        error("Expected a colour image file, but load returned type $(eltype(target)). Please provide a standard image format.")
    end

    img_rows, img_cols = size(target)
    approx = zeros(eltype(target), img_rows, img_cols)

    rng = Random.default_rng()
    canvas = zeros(UInt32, img_rows * img_cols)

    WINDOW_TITLE = "Lines Reconstruction"
    WINDOW_FLAGS = MiniFB.WF_RESIZABLE

    window = mfb_open_ex(WINDOW_TITLE, img_cols, img_rows, WINDOW_FLAGS)

    if window === C_NULL
        error("Failed to open MiniFB window.")
    end

    approx_encode!(approx, canvas)

    while mfb_update(window, canvas) == MiniFB.STATE_OK
        got_improvement = false

        for _ in 1:iterations
            got_improvement = got_improvement || tick!(rng, target, approx)
        end

        if got_improvement
            approx_encode!(approx, canvas)
        end
    end

    if output_filepath !== nothing
        try
            save(output_filepath, approx)
            println("Final image saved to: $output_filepath")
        catch e
            println("Error saving final image: $e")
        end
    end

    println("Application loop finished.")
    # println("Pixel loss is ", pixel_loss(img, img2))
    # println("Line coordinates are:", Line(2, 0, 5, 6))

    # @btime pixel_loss(img, img2)
    println("Final pixel loss is ", pixel_loss(target, approx))
end

main()
