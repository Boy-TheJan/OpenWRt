#!/bin/bash
# 关闭严格报错，防止单次网络失败直接终止脚本
# set -e

# 重试函数
retry_curl(){
  local url=$1
  local out=$2
  for i in {1..3}; do
    echo "curl尝试第${i}次: $url"
    curl -m 40 -sSL "$url" -o "$out"
    [ -f "$out" ] && [ -s "$out" ] && return 0
    sleep 30
  done
  echo "!!! curl下载失败: $url"
}

retry_git(){
  local repo=$1
  local dir=$2
  if [ -d "$dir" ]; then
    echo "$dir 已存在，跳过克隆"
    return 0
  fi
  for i in {1..3}; do
    echo "git克隆尝试第${i}次: $repo"
    git clone "$repo" "$dir" && return 0
    sleep 30
  done
  echo "!!! git克隆失败 $repo"
}

# feeds.conf.default链接替换
sed -i 's|https://git.openwrt.org/feed|https://github.com/openwrt|g' feeds.conf.default

# =========第三方插件源=========
# TurboACC
retry_curl "https://raw.githubusercontent.com/chenmozhijin/turboacc/luci/add_turboacc.sh" "add_turboacc.sh"
if [ -f "add_turboacc.sh" ] && [ -s "add_turboacc.sh" ];then
  bash add_turboacc.sh --no-sfe
fi
rm -f add_turboacc.sh

# 添加插件源地址
echo "src-git adguardhome https://github.com/rufengsuixing/luci-app-adguardhome.git" >> feeds.conf.default
echo "src-git passwall https://github.com/xiaorouji/openwrt-passwall.git;main" >> feeds.conf.default
echo "src-git passwall_packages https://github.com/xiaorouji/openwrt-passwall-packages.git;main" >> feeds.conf.default

# 更新 feeds
./scripts/feeds update -a
./scripts/feeds install -a

# LuCI简体中文
sed -i 's/option lang auto/option lang zh_cn/' feeds/luci/modules/luci-base/root/etc/config/luci

# 创建预置文件目录
mkdir -p files/etc/config
mkdir -p files/etc
mkdir -p files/etc/adguardhome
mkdir -p files/usr/bin
mkdir -p files/etc/crontabs

# ====================== ROOT账号密码 root / Admin@123456 ======================
echo "root:\$1\$VrW0lK1C\$t2xQn5nR5tFwO/hFv2oXn0" > files/etc/shadow

# ========== 网络配置 eth0=WAN PPPoE / eth1 eth2 eth3 LAN桥 192.168.1.1 ==========
cat > files/etc/config/network <<EOF
config interface 'loopback'
	option proto 'static'
	option ipaddr '127.0.0.1'
	option netmask '255.0.0.0'
	option ifname 'lo'

config globals 'globals'
	option ula_prefix 'fd55:aaaa:bbbb::/48'

config interface 'wan'
	option ifname 'eth0'
	option proto 'pppoe'
	option username ''
	option password ''
	option ipv6 '1'
	option peerdns '0'
	option metric '10'

config interface 'lan'
	option type 'bridge'
	option ifname 'eth1 eth2 eth3'
	option proto 'static'
	option ipaddr '192.168.1.1'
	option netmask '255.255.0.0'
	option gateway ''
	option dns '192.168.1.1#3053'
EOF

# ========== 防火墙配置（含WOL外网唤醒UDP9放行） ==========
cat > files/etc/config/firewall <<EOF
config defaults
	option syn_flood '1'
	option input 'ACCEPT'
	option output 'ACCEPT'
	option forward 'REJECT'

config zone
	option name 'lan'
	option network 'lan'
	option input 'ACCEPT'
	option output 'ACCEPT'
	option forward 'ACCEPT'

config zone
	option name 'wan'
	option network 'wan'
	option input 'REJECT'
	option output 'ACCEPT'
	option forward 'REJECT'
	option masq '1'
	option mtu_fix '1'

config forwarding
	option src 'lan'
	option dest 'wan'

config rule
	option name 'Allow-DHCP-Renew'
	option src 'wan'
	option proto 'udp'
	option dest_port '68'
	option target 'ACCEPT'
	option family 'ipv4'

config rule
	option name 'Allow-Ping'
	option src 'wan'
	option proto 'icmp'
	option icmp_type 'echo-request'
	option family 'ipv4'
	option target 'ACCEPT'

config rule
	option name 'Allow-IGMP'
	option src 'wan'
	option proto 'igmp'
	option family 'ipv4'
	option target 'ACCEPT'

config rule
	option name 'Allow-DHCPv6'
	option src 'wan'
	option proto 'udp'
	option dest_port '546'
	option family 'ipv6'
	option target 'ACCEPT'

config rule
	option name 'Allow-MLD'
	option src 'wan'
	option proto 'icmpv6'
	option icmp_type '130/0'
	option family 'ipv6'
	option target 'ACCEPT'

config rule
	option name 'Allow-ICMPv6-Input'
	option src 'wan'
	option proto 'icmpv6'
	option family 'ipv6'
	option target 'ACCEPT'

config rule
	option name 'Allow-ICMPv6-Forward'
	option src 'wan'
	option proto 'icmpv6'
	option family 'ipv6'
	option target 'ACCEPT'

config rule
	option name 'WOL-WAN'
	option src 'wan'
	option proto 'udp'
	option dest_port '9'
	option target 'ACCEPT'
EOF

# ========== 时区 Shanghai ==========
echo "Asia/Shanghai" > files/etc/timezone
cat > files/etc/config/system <<EOF
config system
	option hostname 'OpenWrt'
	option timezone 'CST-8'
	option zonename 'Asia/Shanghai'
EOF

# ========== dnsmasq仅DHCP，关闭53端口，DNS交给AdGuardHome ==========
cat > files/etc/config/dhcp <<EOF
config dnsmasq
	option domainneeded '1'
	option localise_queries '1'
	option rebind_protection '1'
	option rebind_localhost '1'
	option local '/lan/'
	option domain 'lan'
	option expandhosts '1'
	option cachesize '0'
	option authoritative '1'
	option readethers '1'
	option leasefile '/tmp/dhcp.leases'
	option resolvfile '/tmp/resolv.conf.d/resolv.conf.auto'
	option port '0'
	option noresolv '1'

config dhcp 'lan'
	option interface 'lan'
	option start '100'
	option limit '150'
	option leasetime '12h'
	option dhcpv4 'server'
	option dhcpv6 'server'
	option ra 'server'
	option ra_management '1'

config dhcp 'wan'
	option interface 'wan'
	option ignore '1'

config odhcpd 'odhcpd'
	option maindhcp '0'
	option leasefile '/tmp/hosts/odhcpd'
	option leasetrigger '/usr/sbin/odhcpd-update'
	option loglevel '4'
EOF

# ========== 初始兜底 GitHub Hosts ==========
cat > files/etc/adguardhome/github_hosts.txt <<EOF
# GitHub Hosts Initial Backup
140.82.112.4 github.com
140.82.112.5 github.com
185.199.108.153 githubpages.net
185.199.109.153 githubpages.net
185.199.110.153 githubpages.net
185.199.111.153 githubpages.net
199.232.68.133 raw.githubusercontent.com
EOF

# ========== AdGuard广告订阅源 ==========
cat > files/etc/adguardhome/adblock_subs.txt <<EOF
# AdBlock Filter List
https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt
https://cdn.jsdelivr.net/gh/privacy-protection-tools/anti-AD/anti-ad-domain.txt
https://cdn.jsdelivr.net/gh/Loyalsoldier/surge-rules@release/direct.txt
https://malware-filter.gitlab.io/malware-filter/phishing-filter-domain.txt
EOF

# ========== 定时自动更新Github Hosts脚本 ==========
cat > files/usr/bin/update_github_hosts.sh <<'EOF'
#!/bin/bash
HOSTS_FILE="/etc/adguardhome/github_hosts.txt"
TMP_FILE="/tmp/github_hosts.tmp"
SOURCE_URL="https://raw.githubusercontent.com/521xueweihan/GitHub520/main/hosts"

if curl -m 15 -sL "${SOURCE_URL}" -o "${TMP_FILE}"; then
    grep -E 'github|raw.githubusercontent|github.io|githubpages' ${TMP_FILE} | sed '/^#/d;/^$/d' > ${TMP_FILE}.filter
    if [ -s "${TMP_FILE}.filter" ]; then
        echo "# Auto update GitHub Hosts $(date "+%Y-%m-%d %H:%M:%S")" > ${HOSTS_FILE}
        cat ${TMP_FILE}.filter >> ${HOSTS_FILE}
        /etc/init.d/adguardhome reload
        logger "GitHub Hosts 更新成功，已重载AdGuardHome"
    else
        logger "GitHub Hosts过滤无有效内容，放弃更新"
    fi
else
    logger "GitHub Hosts下载失败，保留旧文件"
fi
rm -f ${TMP_FILE} ${TMP_FILE}.filter
EOF
chmod +x files/usr/bin/update_github_hosts.sh

# ========== Cron定时：每日03:10更新 ==========
cat > files/etc/crontabs/root <<EOF
# 每日03:10 更新GitHub Hosts
10 3 * * * /usr/bin/update_github_hosts.sh
EOF

# 启用定时任务
cat > files/etc/config/cron <<EOF
config cron
	option enabled '1'
EOF

echo "==================== DIY脚本执行完成 ===================="
echo "集成清单：PassWall/TurboACC/WireGuard/SQM/AdGuardHome/DDNS/WOL"
echo "⚠️启用PassWall时，关闭TurboACC【软件流量分载】防止冲突"
