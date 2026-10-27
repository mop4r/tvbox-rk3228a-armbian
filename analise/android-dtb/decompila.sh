#!/bin/bash
cd "$(dirname "$0")"
dtc -I dtb -O dts -o fabrica.dts dtbs/dtb-00010487b4.dtb 2>/dev/null
wc -l fabrica.dts
grep -nE 'model =|compatible = "rockchip,rk32' fabrica.dts | head -4
