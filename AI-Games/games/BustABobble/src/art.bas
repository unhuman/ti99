bub_base:	' sprite colour per bubble colour 1..8
	DATA BYTE $09,$03,$05,$0B,$07,$0D,$0E,$0F

	' Aim table: 32 steps from vertical to 80 degrees, speed 5 px/frame, 8.8 fixed
	' point. BOTH MAGNITUDES ARE POSITIVE -- direction is a separate flag, because
	' CVBasic compiles every #var comparison UNSIGNED (a signed velocity would
	' silently misbehave at every sign test).
#aimdx:
	DATA 0,58,115,172,229,286,342,397
	DATA 451,505,557,609,659,707,755,800
	DATA 845,887,928,967,1003,1038,1071,1101
	DATA 1129,1155,1179,1200,1219,1235,1249,1261
#aimdy:
	DATA 1280,1279,1275,1268,1259,1248,1234,1217
	DATA 1198,1176,1152,1126,1098,1067,1034,999
	DATA 962,923,882,839,795,749,701,652
	DATA 602,551,498,445,390,335,279,222
