
`default_nettype none

module tt_um_rhysc25_arena_shooter (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire ena,
    input  wire clk,
    input  wire rst_n
);

    // ============================================================
    // VGA
    // ============================================================

    wire hsync, vsync, video_active;
    wire [9:0] pix_x, pix_y;

    hvsync_generator hvsync_gen (
        .clk(clk),
        .reset(~rst_n),
        .hsync(hsync),
        .vsync(vsync),
        .display_on(video_active),
        .hpos(pix_x),
        .vpos(pix_y)
    );

    wire frame_tick = (pix_x == 10'd0) &&
                      (pix_y == 10'd480);

    // ============================================================
    // INPUTS
    // ============================================================

    reg [2:0] buttons_meta;
    reg [2:0] buttons;

    reg left_q;
    reg right_q;
    reg action_q;

    always @(posedge clk) begin
        if (!rst_n) begin
            buttons_meta <= 3'b000;
            buttons      <= 3'b000;

            left_q       <= 1'b0;
            right_q      <= 1'b0;
            action_q     <= 1'b0;
        end else begin
            buttons_meta <= ui_in[2:0];
            buttons      <= buttons_meta;

            if (frame_tick) begin
                left_q   <= buttons[0];
                right_q  <= buttons[1];
                action_q <= buttons[2];
            end
        end
    end

    wire left    = buttons[0];
    wire right   = buttons[1];
    wire action  = buttons[2];
    wire retreat = left && right;

    wire turn_left  = left  && !left_q  && !right;
    wire turn_right = right && !right_q && !left;

    // ============================================================
    // MAP
    // ============================================================

    function map_wall;
        input [2:0] x;
        input [2:0] y;
        reg [7:0] row;
        begin
            case (y)
                0: row = 8'b11111111;
                1: row = 8'b10000001;
                2: row = 8'b10001001;
                3: row = 8'b10000001;
                4: row = 8'b10010001;
                5: row = 8'b10000001;
                6: row = 8'b10000001;
                7: row = 8'b11111111;
                default: row = 8'b11111111;
            endcase

            map_wall = row[x];
        end
    endfunction

    // ============================================================
    // GAME STATE
    // ============================================================

    reg [7:0] player_x;
    reg [7:0] player_y;

    // 0 = east, 1 = south, 2 = west, 3 = north
    reg [1:0] direction;

    reg [3:0] health;
    reg [1:0] kills;

    reg [2:0] shot_timer;
    reg [2:0] laser_timer;
    reg [4:0] hurt_timer;

    reg game_over;
    reg won;

    reg [1:0] frame_tick_counter;
    reg enemy_axis;

    wire exit_open = (kills == 2);

    // ============================================================
    // PLAYER MOVEMENT
    // 2x movement speed
    // ============================================================

    reg [7:0] next_x;
    reg [7:0] next_y;

    always @(*) begin
        next_x = player_x;
        next_y = player_y;

        if (action || retreat) begin
            case (direction)
                2'd0: next_x = retreat ?
                               player_x - 8'd2 :
                               player_x + 8'd2;

                2'd1: next_y = retreat ?
                               player_y - 8'd2 :
                               player_y + 8'd2;

                2'd2: next_x = retreat ?
                               player_x + 8'd2 :
                               player_x - 8'd2;

                2'd3: next_y = retreat ?
                               player_y + 8'd2 :
                               player_y - 8'd2;
            endcase
        end
    end

    wire player_in_bounds =
        (next_x >= 8'd16)  &&
        (next_x <= 8'd240) &&
        (next_y >= 8'd16)  &&
        (next_y <= 8'd240);

    wire player_can_move =
        player_in_bounds &&
        !map_wall(next_x[7:5], next_y[7:5]);

    // ============================================================
    // ENEMIES
    // ============================================================

    reg [7:0] enemy0_x;
    reg [7:0] enemy0_y;
    reg [7:0] enemy1_x;
    reg [7:0] enemy1_y;

    reg enemy0_alive;
    reg enemy1_alive;

    // ============================================================
    // SHOOTING AND LASERS
    // ============================================================

    wire enemy0_hit =
        enemy0_alive &&
        (
            (direction == 2'd0 &&
             enemy0_x > player_x &&
             enemy0_y[7:3] == player_y[7:3]) ||

            (direction == 2'd1 &&
             enemy0_y > player_y &&
             enemy0_x[7:3] == player_x[7:3]) ||

            (direction == 2'd2 &&
             enemy0_x < player_x &&
             enemy0_y[7:3] == player_y[7:3]) ||

            (direction == 2'd3 &&
             enemy0_y < player_y &&
             enemy0_x[7:3] == player_x[7:3])
        );

    wire enemy1_hit =
        enemy1_alive &&
        (
            (direction == 2'd0 &&
             enemy1_x > player_x &&
             enemy1_y[7:3] == player_y[7:3]) ||

            (direction == 2'd1 &&
             enemy1_y > player_y &&
             enemy1_x[7:3] == player_x[7:3]) ||

            (direction == 2'd2 &&
             enemy1_x < player_x &&
             enemy1_y[7:3] == player_y[7:3]) ||

            (direction == 2'd3 &&
             enemy1_y < player_y &&
             enemy1_x[7:3] == player_x[7:3])
        );

    reg [7:0] laser_x;
    reg [7:0] laser_y;
    reg [1:0] laser_direction;

    // ============================================================
    // ENEMY CONTACT / DAMAGE
    // ============================================================

    wire enemy0_contact =
        enemy0_alive &&
        enemy0_x[7:4] == player_x[7:4] &&
        enemy0_y[7:4] == player_y[7:4];

    wire enemy1_contact =
        enemy1_alive &&
        enemy1_x[7:4] == player_x[7:4] &&
        enemy1_y[7:4] == player_y[7:4];

    wire enemy_contact = enemy0_contact || enemy1_contact;

    // ============================================================
    // MAIN GAME UPDATE
    // ============================================================

    always @(posedge clk) begin

        if (!rst_n) begin

            player_x <= 8'd48;
            player_y <= 8'd48;
            direction <= 2'd0;

            // Player now takes 3 hits to die
            health <= 4'd3;
            kills <= 2'd0;

            shot_timer <= 3'd0;
            laser_timer <= 3'd0;
            hurt_timer <= 5'd0;

            laser_x <= 8'd0;
            laser_y <= 8'd0;
            laser_direction <= 2'd0;

            game_over <= 1'b0;
            won <= 1'b0;

            frame_tick_counter <= 2'd0;
            enemy_axis <= 1'b0;

            enemy0_x <= 8'd32;
            enemy0_y <= 8'd32;

            enemy1_x <= 8'd224;
            enemy1_y <= 8'd224;

            enemy0_alive <= 1'b1;
            enemy1_alive <= 1'b1;

        end else if (frame_tick) begin

            frame_tick_counter <= frame_tick_counter + 1'b1;

            // ----------------------------------------------------
            // COOLDOWNS
            // ----------------------------------------------------

            if (shot_timer != 0)
                shot_timer <= shot_timer - 1'b1;

            if (laser_timer != 0)
                laser_timer <= laser_timer - 1'b1;

            if (hurt_timer != 0)
                hurt_timer <= hurt_timer - 1'b1;

            // ----------------------------------------------------
            // GAME OVER / VICTORY RESTART
            // ----------------------------------------------------

            if (game_over || won) begin

                if (action && !action_q) begin

                    player_x <= 8'd48;
                    player_y <= 8'd48;
                    direction <= 2'd0;

                    // Reset to 3 health
                    health <= 4'd3;
                    kills <= 2'd0;

                    shot_timer <= 3'd0;
                    laser_timer <= 3'd0;
                    hurt_timer <= 5'd0;

                    laser_x <= 8'd0;
                    laser_y <= 8'd0;
                    laser_direction <= 2'd0;

                    game_over <= 1'b0;
                    won <= 1'b0;

                    frame_tick_counter <= 2'd0;
                    enemy_axis <= 1'b0;

                    enemy0_x <= 8'd32;
                    enemy0_y <= 8'd32;

                    enemy1_x <= 8'd224;
                    enemy1_y <= 8'd224;

                    enemy0_alive <= 1'b1;
                    enemy1_alive <= 1'b1;

                end

            end else begin

                // ------------------------------------------------
                // TURNING
                // ------------------------------------------------

                if (turn_left)
                    direction <= direction - 1'b1;
                else if (turn_right)
                    direction <= direction + 1'b1;

                // ------------------------------------------------
                // PLAYER MOVEMENT
                // ------------------------------------------------

                if ((action || retreat) && player_can_move) begin
                    player_x <= next_x;
                    player_y <= next_y;
                end

                // ------------------------------------------------
                // ENEMY MOVEMENT
                // 2x movement speed
                // ------------------------------------------------

                if (frame_tick_counter == 2'd0) begin

                    enemy_axis <= !enemy_axis;

                    if (!enemy_axis) begin

                        if (enemy0_alive) begin
                            if (enemy0_x < player_x)
                                enemy0_x <= enemy0_x + 8'd4;
                            else if (enemy0_x > player_x)
                                enemy0_x <= enemy0_x - 8'd4;
                        end

                        if (enemy1_alive) begin
                            if (enemy1_x < player_x)
                                enemy1_x <= enemy1_x + 8'd4;
                            else if (enemy1_x > player_x)
                                enemy1_x <= enemy1_x - 8'd4;
                        end

                    end else begin

                        if (enemy0_alive) begin
                            if (enemy0_y < player_y)
                                enemy0_y <= enemy0_y + 8'd4;
                            else if (enemy0_y > player_y)
                                enemy0_y <= enemy0_y - 8'd4;
                        end

                        if (enemy1_alive) begin
                            if (enemy1_y < player_y)
                                enemy1_y <= enemy1_y + 8'd4;
                            else if (enemy1_y > player_y)
                                enemy1_y <= enemy1_y - 8'd4;
                        end

                    end
                end

                // ------------------------------------------------
                // DAMAGE
                // One contact = one hit
                // Three hits = death
                // ------------------------------------------------

                if (hurt_timer == 0 && enemy_contact) begin

                    if (health != 0)
                        health <= health - 1'b1;

                    hurt_timer <= 5'd20;

                end

                // ------------------------------------------------
                // SHOOTING
                // One shot still kills one enemy
                // ------------------------------------------------

                if (action && shot_timer == 0) begin

                    shot_timer <= 3'd5;

                    laser_x <= player_x;
                    laser_y <= player_y;
                    laser_direction <= direction;
                    laser_timer <= 3'd4;

                    if (enemy0_hit) begin
                        enemy0_alive <= 1'b0;
                        kills <= kills + 1'b1;
                    end else if (enemy1_hit) begin
                        enemy1_alive <= 1'b0;
                        kills <= kills + 1'b1;
                    end

                end

                // ------------------------------------------------
                // EXIT / GAME STATE
                // ------------------------------------------------

                if (health == 0)
                    game_over <= 1'b1;

                if (exit_open &&
                    player_x >= 8'd192 &&
                    player_y >= 8'd192)
                    won <= 1'b1;

            end
        end
    end

    // ============================================================
    // VGA RENDERER
    // ============================================================

    wire in_arena =
        (pix_x >= 10'd192) &&
        (pix_x < 10'd448) &&
        (pix_y >= 10'd80) &&
        (pix_y < 10'd336);

    wire [7:0] world_x = pix_x[7:0] - 8'd192;
    wire [7:0] world_y = pix_y[7:0] - 8'd80;

    wire [2:0] tile_x = world_x[7:5];
    wire [2:0] tile_y = world_y[7:5];

    wire wall = map_wall(tile_x, tile_y);

    wire is_exit = (tile_x == 3'd6) &&
                   (tile_y == 3'd6);

    // ------------------------------------------------------------
    // SMOOTH SPRITES
    // ------------------------------------------------------------

    wire [7:0] player_dx = world_x - player_x;
    wire [7:0] player_dy = world_y - player_y;

    wire [7:0] enemy0_dx = world_x - enemy0_x;
    wire [7:0] enemy0_dy = world_y - enemy0_y;

    wire [7:0] enemy1_dx = world_x - enemy1_x;
    wire [7:0] enemy1_dy = world_y - enemy1_y;

    wire player_sprite =
        (player_dx < 8'd8) &&
        (player_dy < 8'd8);

    wire enemy0_sprite =
        enemy0_alive &&
        (enemy0_dx < 8'd8) &&
        (enemy0_dy < 8'd8);

    wire enemy1_sprite =
        enemy1_alive &&
        (enemy1_dx < 8'd8) &&
        (enemy1_dy < 8'd8);

    wire enemy_sprite = enemy0_sprite || enemy1_sprite;

    // ------------------------------------------------------------
    // LASER RENDERING
    // ------------------------------------------------------------

    wire [8:0] laser_east_dx =
        {1'b0, world_x} - {1'b0, laser_x};

    wire [8:0] laser_south_dy =
        {1'b0, world_y} - {1'b0, laser_y};

    wire [8:0] laser_west_dx =
        {1'b0, laser_x} - {1'b0, world_x};

    wire [8:0] laser_north_dy =
        {1'b0, laser_y} - {1'b0, world_y};

    wire laser_sprite =
        (laser_timer != 0) &&
        (
            // East
            (laser_direction == 2'd0 &&
             world_y == laser_y + 8'd4 &&
             world_x > laser_x &&
             laser_east_dx >= 9'd8 &&
             laser_east_dx < 9'd328) ||

            // South
            (laser_direction == 2'd1 &&
             world_x == laser_x + 8'd4 &&
             world_y > laser_y &&
             laser_south_dy >= 9'd8 &&
             laser_south_dy < 9'd328) ||

            // West
            (laser_direction == 2'd2 &&
             world_y == laser_y + 8'd4 &&
             world_x < laser_x &&
             laser_west_dx <= 9'd320) ||

            // North
            (laser_direction == 2'd3 &&
             world_x == laser_x + 8'd4 &&
             world_y < laser_y &&
             laser_north_dy <= 9'd320)
        );

    // ============================================================
    // COLOUR
    // ============================================================

    reg [5:0] colour;

    always @(*) begin

        colour = 6'b000000;

        if (video_active) begin

            if (in_arena) begin

                colour = wall ? 6'b101000 : 6'b010100;

                // Tile borders
                if (world_x[4:0] == 0 ||
                    world_y[4:0] == 0)
                    colour = 6'b001000;

                // Exit
                if (is_exit && !wall)
                    colour = exit_open ?
                             6'b001100 : 6'b100000;

                // Enemies
                if (enemy_sprite)
                    colour = 6'b110000;

                // Extended laser beam
                if (laser_sprite)
                    colour = 6'b001111;

                // Player
                if (player_sprite)
                    colour = 6'b111100;

                // Direction marker removed.
                // No white artifact beside the player.

            end

            // ----------------------------------------------------
            // HUD BACKGROUND
            // ----------------------------------------------------

            if (pix_y >= 10'd360 &&
                pix_y < 10'd440)
                colour = 6'b010101;

            // ----------------------------------------------------
            // HEALTH BAR
            // ----------------------------------------------------

            if (pix_x >= 10'd192 &&
                pix_x < (10'd192 +
                         {3'b000, health, 3'b000}) &&
                pix_y >= 10'd380 &&
                pix_y < 10'd394)

                colour = health > 4'd1 ?
                         6'b001100 : 6'b110000;

            // ----------------------------------------------------
            // EXIT STATUS
            // ----------------------------------------------------

            if (pix_x >= 10'd400 &&
                pix_x < 10'd432 &&
                pix_y >= 10'd380 &&
                pix_y < 10'd412)

                colour = exit_open ?
                         6'b001100 : 6'b110000;

            // ----------------------------------------------------
            // DEATH / VICTORY
            // ----------------------------------------------------

            if (game_over || won) begin

                if (pix_x >= 10'd160 &&
                    pix_x < 10'd480 &&
                    pix_y >= 10'd180 &&
                    pix_y < 10'd300) begin

                    if (won)
                        colour = 6'b001100;
                    else
                        colour = 6'b110000;

                    if (pix_x < 10'd176 ||
                        pix_x >= 10'd464 ||
                        pix_y < 10'd196 ||
                        pix_y >= 10'd284)
                        colour = 6'b111111;

                end
            end

            // ----------------------------------------------------
            // DAMAGE FLASH
            // ----------------------------------------------------

            if (hurt_timer > 5'd16 &&
                (pix_x < 10'd12 ||
                 pix_x >= 10'd628 ||
                 pix_y < 10'd12 ||
                 pix_y >= 10'd468))
                colour = 6'b110000;

        end
    end

    // ============================================================
    // OUTPUT
    // ============================================================

    wire [1:0] R = colour[5:4];
    wire [1:0] G = colour[3:2];
    wire [1:0] B = colour[1:0];

    assign uo_out = {
        hsync,
        B[0], G[0], R[0],
        vsync,
        B[1], G[1], R[1]
    };

    assign uio_out = 8'h00;
    assign uio_oe  = 8'h00;

    wire _unused_ok = &{ena, uio_in, ui_in[7:3]};

endmodule
