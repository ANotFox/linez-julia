using MiniFB
using ArgParse
using Images
using Random

# Buffers make it so much better for performance
const LINE_BUF = Vector{Tuple{Int32,Int32}}(undef, 4096)
const CHANGES_BUF = Vector{Tuple{CartesianIndex{2}, RGB{Float32}}}()
const MAIN_RNG = Xoshiro() 


function parse_commandline()
    s = ArgParseSettings(
        description = "Description: ",
        version = "Version 0.3",
        add_version = true
    )

    @add_arg_table s begin
        "--image", "-i"
            help = "Pass image filepath"
            required = true
            arg_type = String
        "--iterations", "-n"
            help = "Number of iterations to sample a line"
            required = true
            arg_type = Int
        "--display-interval", "-d"
            help = "Update display every N iterations"
            arg_type = Int
            default = 1
        "--output", "-o"
            help = "Output filepath for the final image"
            arg_type = String 
            default = nothing
    end

    return parse_args(s) # Returns Dict{String, Any}
end

# --- Bresenham's line algorithm (more direct implementation)
# adapted from https://github.com/rdeits/convex-segmentation/blob/master/julia/bresenham.jl
function bresenham_line!(x1::Int32, y1::Int32, x2::Int32, y2::Int32)::Int32
    dx = abs(x2 - x1)
    dy = -abs(y2 - y1)
    sx = x1 < x2 ? Int32(1) : Int32(-1)
    sy = y1 < y2 ? Int32(1) : Int32(-1)
    err = dx + dy
    i = Int32(1)
    
    curr_x = x1
    curr_y = y1
    
     while true
        LINE_BUF[i] = (curr_x, curr_y)
        i += Int32(1)
        (curr_x == x2 && curr_y == y2) && break
        
        e2 = Int32(2) * err
        if e2 >= dy
            err += dy
            curr_x += sx
        end
        if e2 <= dx
            err += dx
            curr_y += sy
        end
    end
    
    return i - Int32(1)  # Return number of points
end

@inline function bresenham_line!(x1::Int, y1::Int, x2::Int, y2::Int)::Int32
    bresenham_line!(Int32(x1), Int32(y1), Int32(x2), Int32(y2))
end

# --- Sampling the line and calculating loss

function tick!(rng::AbstractRNG, target::AbstractMatrix{<:Colorant}, approx::AbstractMatrix{<:Colorant})::Bool
    img_rows, img_cols = size(target)

    beg_row = rand(rng, Int32(1):Int32(img_rows))
    beg_col = rand(rng, Int32(1):Int32(img_cols))
    end_row = rand(rng, Int32(1):Int32(img_rows))
    end_col = rand(rng, Int32(1):Int32(img_cols))

    colour = RGB{Float32}(rand(rng), rand(rng), rand(rng))
    
    num_points = bresenham_line!(beg_col, beg_row, end_col, end_row)  # Note: x,y order
    
    empty!(CHANGES_BUF)
    
     for i in 1:num_points
        x, y = LINE_BUF[i]
        if (1 <= y <= img_rows) && (1 <= x <= img_cols)
            push!(CHANGES_BUF, (CartesianIndex(y, x), colour))
        end
    end

    isempty(CHANGES_BUF) && return false

    loss_delta_val = loss_delta_fast(target, approx, CHANGES_BUF)
    loss_delta_val >= 0.0 && return false

    apply!(approx, CHANGES_BUF)
    return true
end

@inline function pixel_loss_fast(a::RGB{Float32}, b::RGB{Float32})::Float64
    dr = Float64(a.r) - Float64(b.r)
    dg = Float64(a.g) - Float64(b.g)
    db = Float64(a.b) - Float64(b.b)
    return dr*dr + dg*dg + db*db
end

function pixel_loss(a::Colorant, b::Colorant)::Float64
    a_rgb = convert(RGB{Float32}, a)
    b_rgb = convert(RGB{Float32}, b)
    return pixel_loss_fast(a_rgb, b_rgb)
    # more performant
end

function pixel_loss(a::AbstractMatrix{<:Colorant}, b::AbstractMatrix{<:Colorant})::Float64
    size(a) == size(b) || throw(DimensionMismatch("Matrices must have the same size"))

    total_diff = 0.0 
     for i in eachindex(a) 
        total_diff += pixel_loss(a[i], b[i]) 
    end
    return total_diff
end

function loss_delta_fast(target::AbstractMatrix{<:Colorant}, source::AbstractMatrix{<:Colorant}, 
    changes::Vector{Tuple{CartesianIndex{2}, RGB{Float32}}})::Float64
    total_delta_loss = 0.0

    for (pos, new_colour) in changes
        target_rgb = convert(RGB{Float32}, target[pos])
        source_rgb = convert(RGB{Float32}, source[pos])

        loss_without = pixel_loss_fast(target_rgb, source_rgb)
        loss_with = pixel_loss_fast(target_rgb, new_colour)

        total_delta_loss += (loss_with - loss_without)
    end

    return total_delta_loss
end

# --- Encoding the approx image to a canvas buffer (MiniFB compliant)
function approx_encode!(approx::AbstractMatrix{<:Colorant}, canvas::Vector{UInt32})
    rows, cols = size(approx)

    current_canvas_idx = 1
    for r_idx in 1:rows
        for c_idx in 1:cols
            pixel = approx[r_idx, c_idx] # eltype(approx)

            r_comp = UInt32(round(clamp(red(pixel) * 255, 0, 255)))
            g_comp = UInt32(round(clamp(green(pixel) * 255, 0, 255)))
            b_comp = UInt32(round(clamp(blue(pixel) * 255, 0, 255)))

            canvas[current_canvas_idx] = (0xFF000000) | (r_comp << 16) | (g_comp << 8) | b_comp
            current_canvas_idx += 1
        end
    end
    return nothing 
end

@inline function apply!(approx::AbstractMatrix{<:Colorant}, changes::Vector{Tuple{CartesianIndex{2}, RGB{Float32}}})
    for (pos, new_colour) in changes
       approx[pos] = new_colour 
   end
end

# --- Main
function main()
    parsed_args = parse_commandline()
    img_filepath = parsed_args["image"]::String
    iterations = parsed_args["iterations"]::Int
    output_filepath = parsed_args["output"] # either String or nothing
    display_interval = parsed_args["display-interval"]::Int

    target = load(img_filepath)
    if !(eltype(target) <: Colorant)
        error("Expected a colour image file, but not type $(eltype(target)).")
    end

    img_rows, img_cols = size(target)
    approx = zeros(eltype(target), img_rows, img_cols)

    canvas = zeros(UInt32, img_rows * img_cols)
    window = mfb_open_ex("Lines Reconstruction", img_cols, img_rows, 0)

    approx_encode!(approx, canvas)

    # some statistical plotting
    iteration_count = 0
    total_improvements = 0

    while mfb_update(window, canvas) == MiniFB.STATE_OK
        got_improvement = false

        for _ in 1:iterations 
            if tick!(MAIN_RNG, target, approx)
                got_improvement = true
                total_improvements += 1
            end
            iteration_count += 1       
        end

        if got_improvement && (iteration_count % display_interval == 0)
            approx_encode!(approx, canvas)
        end
        
        if iteration_count % 10000 == 0
            current_loss = pixel_loss(target, approx)
            println("Iterations: $(iteration_count), Improvements: $(total_improvements), Current loss: $(round(current_loss, digits=2))")
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

    println("Final statistics:")
    println("  Total iterations: $(iteration_count)")
    println("  Total improvements: $(total_improvements)")
    println("  Improvement rate: $(round(100 * total_improvements / iteration_count, digits=4))%")
    println("  Final pixel loss: $(round(pixel_loss(target, approx), digits=2))")
end

main()