using MiniFB
using ArgParse
using Images
using BenchmarkTools
using Random

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

    return parse_args(s) # Returns Dict{String, Any}
end

# Bresenham's line algorithm (more direct implementation)
# adapted from https://github.com/rdeits/convex-segmentation/blob/master/julia/bresenham.jl
function Line(x1::Int, y1::Int, x2::Int, y2::Int)
    dx = abs(x2 - x1)
    dy = abs(y2 - y1)

    sx = x1 < x2 ? 1 : -1
    sy = y1 < y2 ? 1 : -1

    err = dx - dy

    curr_x = x1 
    curr_y = y1 

    x_coords = Int[]
    y_coords = Int[]

    while true
        push!(x_coords, curr_x)
        push!(y_coords, curr_y)

        if curr_x == x2 && curr_y == y2
            break
        end

        e2 = 2 * err
        if e2 > -dy
            err -= dy
            curr_x += sx
        end
        if e2 < dx 
            err += dx
            curr_y += sy
        end
    end

    return x_coords, y_coords 
end

function Line(x1::Real, y1::Real, x2::Real, y2::Real)
	Line(round(Int, x1), round(Int, y1), round(Int, x2), round(Int, y2))
end

function apply!(approx::AbstractMatrix{<:Colorant}, changes::Vector{Tuple{CartesianIndex{2}, RGB{Float32}}})
     for (pos, new_colour) in changes
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

    r_rand = rand(rng) # Float64
    g_rand = rand(rng) # Float64
    b_rand = rand(rng) # Float64

    colour = RGB{Float32}(r_rand, g_rand, b_rand) # Explicit RGB{Float32}
    row_coords, col_coords = Line(beg_row, beg_col, end_row, end_col) # Calls Line(Int,Int,Int,Int)

    changes = Vector{Tuple{CartesianIndex{2}, RGB{Float32}}}()

    for (r_coord, c_coord) in zip(row_coords, col_coords) 
        if (1 <= r_coord <= img_rows) && (1 <= c_coord <= img_cols) 
            push!(changes, (CartesianIndex(r_coord, c_coord), colour))
        end
    end

    if isempty(changes)
        return false
    end

    loss_delta_val = loss_delta(target, approx, changes) 
    # println("Loss delta: ", loss_delta_val)
    if loss_delta_val >= 0 # No improvement or worse
        return false
    end

    apply!(approx, changes)
    return true
end


function pixel_loss(a::Colorant, b::Colorant)::Float64
    a_rgb = convert(RGB{Float32}, a)
    b_rgb = convert(RGB{Float32}, b)

    r_diff_sq = (Float64(red(a_rgb)) - Float64(red(b_rgb)))^2
    g_diff_sq = (Float64(green(a_rgb)) - Float64(green(b_rgb)))^2
    b_diff_sq = (Float64(blue(a_rgb)) - Float64(blue(b_rgb)))^2

    return r_diff_sq + g_diff_sq + b_diff_sq
end

function pixel_loss(a::AbstractMatrix{<:Colorant}, b::AbstractMatrix{<:Colorant})::Float64
    size(a) == size(b) || throw(DimensionMismatch("Matrices must have the same size"))

    total_diff = 0.0 
     for i in eachindex(a) 
        total_diff += pixel_loss(a[i], b[i]) 
    end
    return total_diff
end

function loss_delta(target::AbstractMatrix{<:Colorant}, source::AbstractMatrix{<:Colorant}, changes::Vector{Tuple{CartesianIndex{2}, RGB{Float32}}})::Float64
    total_delta_loss = 0.0 

    for (pos, new_colour) in changes
        target_at_pos = convert(RGB{Float32}, target[pos])
        source_at_pos = convert(RGB{Float32}, source[pos])

        loss_without_change = pixel_loss(target_at_pos, source_at_pos)
        loss_with_change = pixel_loss(target_at_pos, new_colour) 

        total_delta_loss += (loss_with_change - loss_without_change)
    end

    return total_delta_loss
end

function approx_encode!(approx::AbstractMatrix{<:Colorant}, canvas::Vector{UInt32})
    rows, cols = size(approx)

    current_canvas_idx = 1
    for r_idx in 1:rows
        for c_idx in 1:cols
            pixel = approx[r_idx, c_idx] # eltype(approx)

            r_comp = round(UInt32, clamp(red(pixel) * 255, 0, 255))
            g_comp = round(UInt32, clamp(green(pixel) * 255, 0, 255))
            b_comp = round(UInt32, clamp(blue(pixel) * 255, 0, 255))

            canvas[current_canvas_idx] = (0xFF000000) | (r_comp << 16) | (g_comp << 8) | b_comp
            current_canvas_idx += 1
        end
    end
    return nothing 
end


function main()
    parsed_args = parse_commandline()
    img_filepath = parsed_args["image"]::String
    iterations = parsed_args["iterations"]::Int
    output_filepath = parsed_args["output"]

    target = load(img_filepath)
    if !(eltype(target) <: Colorant)
        error("Expected a colour image file, but not type $(eltype(target)).")
    end

    img_rows, img_cols = size(target)
    approx = zeros(eltype(target), img_rows, img_cols)

    rng = Random.default_rng() 
    canvas = zeros(UInt32, img_rows * img_cols)

    WINDOW_TITLE = "Lines Reconstruction"

    window = mfb_open_ex(WINDOW_TITLE, img_cols, img_rows, 0)

    approx_encode!(approx, canvas)

    while mfb_update(window, canvas) == MiniFB.STATE_OK
        got_improvement = false

        for _ in 1:iterations 
            got_improvement = got_improvement || tick!(rng, target, approx) # tick! returns Bool
        end

        if got_improvement
            approx_encode!(approx, canvas)
        end
    end

    mfb_close(window)

    if output_filepath !== nothing && output_filepath isa String
        try
            save(output_filepath, approx)
            println("Final image saved to: $output_filepath")
        catch e
            println("Error saving final image: $e")
        end
    end

    # @btime pixel_loss(img, img2)
    println("Final pixel loss is ", pixel_loss(target, approx))
end

main()