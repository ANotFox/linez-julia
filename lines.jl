using MiniFB

function lines()
    WIDTH = 800
    HEIGHT = 600
    WINDOW_TITLE = "Lines"
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

plasma()
