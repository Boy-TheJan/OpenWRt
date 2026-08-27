#!/bin/bash
# diy‑part2.sh feeds安装后执行
# 设置LuCI默认语言中文
mkdir -p files/etc/config
cat > files/etc/config/luci <<EOF
config core
        option lang 'zh_cn'
        option mediaurl ''
        option ubus_timeout '10'
EOF
