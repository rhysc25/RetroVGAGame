## How it works

A sync generator counts through the 640 by 480 pixels of each frame at 60 Hz. Inside that frame an 8x8 arena of 32-pixel wall tiles is drawn from a small lookup table. The player is a tank that turns in place and drives a fixed distance per frame; two enemies home in on the tank, alternating between the horizontal and vertical axis as they close in. Pressing advance fires a short laser beam that destroys any enemy lined up with the tank. Each enemy contact costs one of three health points, with a brief red screen flash. After two kills the exit tile unlocks: drive onto it to win, and a green banner appears. Losing all three health ends the round with a red banner. The HUD shows a health bar and an exit-status indicator.

## How to test

Use a 25.175 MHz clock and hold rst_n low for a few cycles, then raise it. The picture appears on a monitor connected through a TinyVGA PMOD. Tap ui[0] or ui[1] to turn the tank, hold ui[2] to drive forward and fire, and hold ui[0] and ui[1] together to reverse. Press ui[2] again on the banner to restart.

## External hardware

A TinyVGA PMOD, a VGA monitor, and three buttons or switches on ui[0], ui[1] and ui[2].
