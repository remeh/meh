#pragma once

#define MODE_INSERT 1
#define MODE_NORMAL 2
#define MODE_REPLACE 3
#define MODE_COMMAND 4
#define MODE_VISUAL 5
#define MODE_VISUAL_LINE 6
#define MODE_REPLACE_ONE 7
#define MODE_LEADER 8

#define NO_SUBMODE 0
#define SUBMODE_c 1
#define SUBMODE_cf 2
#define SUBMODE_cF 3
#define SUBMODE_ct 4
#define SUBMODE_cT 5
#define SUBMODE_f 6
#define SUBMODE_F 7
#define SUBMODE_d 8
#define SUBMODE_y 9

// Plugins have a submode >= 1000

#define SUBMODE_tasks 1000