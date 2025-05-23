using ArgParse

function parse_commandline()
    s = ArgParseSettings(
        description = "Description: 
        I am testing how this ArgParse package works.",
        version = "Version 0.1",
        add_version = true
    )

    @add_arg_table s begin

        "--opt1"
            help = "option 1 with an argument"
        "--opt2", "-o"
            help = "another option with an arg"
            arg_type = Int
            default = 0
        "--flag1"
            help = "this is just a flag, no arg is passed"
            action = :store_true
        "arg1"
            help = "positional arg"
            required = true

    end
    return parse_args(s)
    # result is a Dict{String, Any} object
end

function main()
    parsed_args = parse_commandline()
    println("Parsed args:")
    for (arg, val) in parsed_args
        println("  $arg: $val")
    end
end

main()