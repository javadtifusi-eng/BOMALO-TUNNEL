#!/usr/bin/env bash
# Bomalo Tunnel installer / manager
#   bash <(curl -fsSL https://raw.githubusercontent.com/javadtifusi-eng/BOMALO-TUNNEL/main/install.sh)
set -uo pipefail

REPO_USER="javadtifusi-eng"
REPO_NAME="BOMALO-TUNNEL"
BRANCH="main"
RAW="https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${BRANCH}"
RELEASE="https://github.com/${REPO_USER}/${REPO_NAME}/releases/latest/download"

BIN=/usr/local/bin/bomalo
MENU=/usr/local/bin/bomalo-menu
CFG_DIR=/etc/bomalo
CFG=$CFG_DIR/config.json
UNIT=/etc/systemd/system/bomalo.service
CRON=/etc/cron.d/bomalo
SRC_DIR=/opt/bomalo-src
GO_MIN=1.21

# palette: text is white, numbers are red, only "running" is green
W=$'\e[97m'; R=$'\e[91m'; G=$'\e[92m'; BL=$'\e[94m'; D=$'\e[90m'; N=$'\e[0m'; BD=$'\e[1m'

info() { echo "${W}==>${N} ${W}$*${N}"; }
ok()   { echo "${G} ok ${N} ${W}$*${N}"; }
warn() { echo "${R} !! ${N} ${W}$*${N}"; }
die()  { echo "${R}fail${N} ${W}$*${N}"; exit 1; }

cols() { local c; c=$(tput cols 2>/dev/null || echo 80); [ -n "$c" ] && echo "$c" || echo 80; }

banner() {
  clear 2>/dev/null || true
  printf '%s' "${G}${BD}"
  cat <<'EOF'
████████     ██████   ██      ██   ██████   ██           ██████
██      ██ ██      ██ ████  ████ ██      ██ ██         ██      ██
██      ██ ██      ██ ██  ██  ██ ██      ██ ██         ██      ██
████████   ██      ██ ██  ██  ██ ██████████ ██         ██      ██
██      ██ ██      ██ ██      ██ ██      ██ ██         ██      ██
██      ██ ██      ██ ██      ██ ██      ██ ██         ██      ██
████████     ██████   ██      ██ ██      ██ ██████████   ██████
EOF
  printf '%s' "${N}${W}"
  cat <<'EOF'
               █████ █   █ █   █ █   █ █████ █
                 █   █   █ ██  █ ██  █ █     █
                 █   █   █ █ █ █ █ █ █ █     █
                 █   █   █ █ █ █ █ █ █ ████  █
                 █   █   █ █  ██ █  ██ █     █
                 █   █   █ █   █ █   █ █     █
                 █    ███  █   █ █   █ █████ █████
EOF
  printf '%s' "$N"
  echo "  ${BL}reverse tunnel${N}  ${D}client-initiated${N}"
  echo
}

pause() { echo; read -r -p "  ${D}press Enter${N} " _; }

require_root() { [ "$(id -u)" = 0 ] || die "run this script as root (sudo -i)"; }

pkg_install() {
  if command -v apt-get >/dev/null 2>&1; then
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@"
  elif command -v dnf >/dev/null 2>&1; then dnf install -y -q "$@"
  elif command -v yum >/dev/null 2>&1; then yum install -y -q "$@"
  elif command -v apk >/dev/null 2>&1; then apk add --no-cache "$@"
  else warn "unknown package manager, please install manually: $*"; fi
}

ensure_deps() {
  local need=()
  command -v curl >/dev/null 2>&1 || need+=(curl)
  command -v tar  >/dev/null 2>&1 || need+=(tar)
  command -v jq   >/dev/null 2>&1 || need+=(jq)
  if [ ${#need[@]} -gt 0 ]; then
    info "installing dependencies: ${need[*]}"
    pkg_install "${need[@]}"
  fi
  command -v jq >/dev/null 2>&1 || die "jq is required and could not be installed"
}

arch_tag() {
  case "$(uname -m)" in
    x86_64|amd64)  echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    armv7l)        echo armv6l ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
}

# ------------------------------------------------------------------ toolchain

have_go() {
  local g v
  g=$(command -v go 2>/dev/null); [ -z "$g" ] && g=/usr/local/go/bin/go
  [ -x "$g" ] || return 1
  v=$("$g" version 2>/dev/null | awk '{print $3}' | sed 's/^go//')
  [ -n "$v" ] || return 1
  [ "$(printf '%s\n%s\n' "$GO_MIN" "$v" | sort -V | head -1)" = "$GO_MIN" ]
}

persist_path() {
  grep -q '/usr/local/go/bin' /etc/profile 2>/dev/null || \
    echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
}

ensure_go() {
  export PATH=$PATH:/usr/local/go/bin
  if have_go; then ok "using $(go version | awk '{print $3}')"; return; fi

  local ver a url
  ver=$(curl -fsSL --max-time 10 "https://go.dev/VERSION?m=text" 2>/dev/null | head -1 | tr -d '[:space:]')
  [ -z "$ver" ] && ver="go1.22.5"
  a=$(arch_tag)

  for url in "https://go.dev/dl/${ver}.linux-${a}.tar.gz" \
             "https://dl.google.com/go/${ver}.linux-${a}.tar.gz"; do
    info "downloading $ver"
    if curl -fsSL --max-time 600 "$url" -o /tmp/go.tgz && [ -s /tmp/go.tgz ]; then
      rm -rf /usr/local/go && tar -C /usr/local -xzf /tmp/go.tgz && rm -f /tmp/go.tgz
      export PATH=$PATH:/usr/local/go/bin
      if have_go; then ok "go installed"; persist_path; return; fi
    fi
    rm -f /tmp/go.tgz
  done

  # Google's download hosts are blocked from many Iranian networks
  warn "the Go download servers are unreachable from this network"
  info "falling back to the distribution package"
  pkg_install golang-go >/dev/null 2>&1 || pkg_install golang >/dev/null 2>&1 || true
  export PATH=$PATH:/usr/local/go/bin
  if have_go; then ok "using $(go version | awk '{print $3}')"; return; fi

  die "no usable Go toolchain (need >= $GO_MIN). Build elsewhere with build.sh and
     upload dist/* to a GitHub release tagged \"latest\", then run option 1 again."
}

# ------------------------------------------------------------------ binary

bin_version() {
  [ -x "$BIN" ] || return 1
  local v; v=$("$BIN" -version 2>/dev/null | head -1)
  case "$v" in bomalo\ *) echo "$v" ;; *) return 1 ;; esac
}

stop_legacy() {
  bin_version >/dev/null 2>&1 && return
  [ -x "$BIN" ] || return
  warn "an older bomalo (the iptables/bash version) is installed at $BIN"
  local units u
  units=$(systemctl list-units --all --plain --no-legend 2>/dev/null \
          | awk '{print $1}' | grep -E '^(bomalo|tunnel)' | grep -v '^bomalo.service$')
  if [ -n "$units" ]; then
    for u in $units; do systemctl disable --now "$u" >/dev/null 2>&1; done
    echo "   ${D}stopped legacy services${N}"
  fi
  if iptables -t nat -S PREROUTING 2>/dev/null | grep -q 'DNAT'; then
    warn "old DNAT rules are still present:"
    iptables -t nat -S PREROUTING | grep DNAT | sed 's/^/     /'
    echo "   ${D}remove them one by one: iptables -t nat -D PREROUTING <n>${N}"
  fi
  cp -f "$BIN" "${BIN}.legacy.bak" 2>/dev/null
}

install_shortcut() {
  if [ -f ./install.sh ]; then
    install -m 0755 ./install.sh "$MENU" 2>/dev/null
  else
    curl -fsSL "$RAW/install.sh" -o "$MENU" 2>/dev/null && chmod 0755 "$MENU"
  fi
  [ -x "$MENU" ] || return 1
  ln -sf "$MENU" /usr/local/bin/bm
  return 0
}

install_binary() {
  stop_legacy
  local a; a=$(arch_tag)
  info "looking for a prebuilt binary"
  if curl -fsSL "${RELEASE}/bomalo-linux-${a}" -o /tmp/bomalo 2>/dev/null && [ -s /tmp/bomalo ]; then
    install -m 0755 /tmp/bomalo "$BIN"; rm -f /tmp/bomalo
    ok "installed $(bin_version)"
  else
    warn "no release binary found, building from source"
    ensure_go
    mkdir -p "$SRC_DIR"
    if [ -f ./main.go ] && [ -f ./go.mod ]; then
      cp ./main.go ./go.mod "$SRC_DIR/"
    else
      curl -fsSL "$RAW/main.go" -o "$SRC_DIR/main.go" || die "could not download main.go"
      curl -fsSL "$RAW/go.mod"  -o "$SRC_DIR/go.mod"  || die "could not download go.mod"
    fi
    ( cd "$SRC_DIR" && CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o "$BIN" . ) || die "build failed"
    chmod 0755 "$BIN"
    ok "built and installed $(bin_version)"
  fi
  install_shortcut && ok "type ${R}bm${N}${W} to open this menu again"
}

# ------------------------------------------------------------------ service

write_unit() {
  cat > "$UNIT" <<EOF
[Unit]
Description=Bomalo Tunnel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$BIN -config $CFG
Restart=always
RestartSec=3
LimitNOFILE=1048576
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
}

save_cfg() {
  mkdir -p "$CFG_DIR"
  echo "$1" | jq . > "$CFG" || die "could not write config"
  chmod 600 "$CFG"
}

restart_service() {
  write_unit
  systemctl enable bomalo >/dev/null 2>&1
  systemctl restart bomalo
  sleep 1
  if systemctl is-active --quiet bomalo; then ok "service is running"
  else warn "service failed - check the logs in Manage"; fi
}

open_port() {
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow "$1/$2" >/dev/null 2>&1 && echo "   ${D}ufw: opened $1/$2${N}"
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port="$1/$2" >/dev/null 2>&1
    firewall-cmd --reload >/dev/null 2>&1 && echo "   ${D}firewalld: opened $1/$2${N}"
  fi
}

ask() {
  local p="$1" d="${2:-}" a
  if [ -n "$d" ]; then read -r -p "  ${W}$p${N} [$d]: " a; echo "${a:-$d}"
  else read -r -p "  ${W}$p${N}: " a; echo "$a"; fi
}

pick_transport() {
  {
    echo
    echo "  ${W}Transport:${N}"
    echo "    ${R}1${N}) ${W}tls${N}   TLS with a self-signed certificate"
    echo "    ${R}2${N}) ${W}wss${N}   HTTP/WebSocket upgrade inside TLS  ${D}(best against DPI)${N}"
    echo "    ${R}3${N}) ${W}ws${N}    plain HTTP/WebSocket upgrade"
    echo "    ${R}4${N}) ${W}tcp${N}   raw TCP, fastest, no disguise"
  } >&2
  local c; read -r -p "  ${W}choice${N} [1]: " c
  case "${c:-1}" in 2) echo wss ;; 3) echo ws ;; 4) echo tcp ;; *) echo tls ;; esac
}

# ------------------------------------------------------------------ setup

setup_server() {
  echo
  info "Configuring this machine as the IRAN server (public entry point)"
  local port token transport sni path cfg ip
  port=$(ask "Tunnel port (the foreign server dials this)" 8443)
  token=$(ask "Shared token (leave empty to generate)" "")
  [ -z "$token" ] && token=$("$BIN" -gen-token)
  transport=$(pick_transport)
  sni=$(ask "SNI / fake hostname" "www.bing.com")
  path=$(ask "HTTP path (ws/wss only)" "/tunnel")

  cfg=$(jq -n --arg l "0.0.0.0:$port" --arg t "$transport" --arg tok "$token" \
              --arg s "$sni" --arg p "$path" \
        '{mode:"server", listen:$l, transport:$t, token:$tok, sni:$s, path:$p, forwards:[]}')
  save_cfg "$cfg"
  open_port "$port" tcp
  ip=$(curl -fsSL --max-time 5 https://api.ipify.org 2>/dev/null || echo YOUR_IRAN_IP)
  echo
  ok "server configured"
  echo
  echo "  ${W}Copy these values to the foreign server:${N}"
  echo "    server    : ${W}$ip:$port${N}"
  echo "    token     : ${W}$token${N}"
  echo "    transport : ${W}$transport${N}"
  echo "    sni       : ${W}$sni${N}"
  echo "    path      : ${W}$path${N}"
  echo
  read -r -p "  ${W}Add forwarded ports now?${N} [Y/n]: " a
  [[ "${a:-y}" =~ ^[Yy]?$ ]] && add_forward
  restart_service
}

setup_client() {
  echo
  info "Configuring this machine as the FOREIGN server (exit node)"
  local ip port token transport sni path pool cfg
  ip=$(ask "Iran server IP" "")
  [ -z "$ip" ] && { warn "IP is required"; return; }
  port=$(ask "Tunnel port" 8443)
  token=$(ask "Shared token (from the Iran server)" "")
  [ -z "$token" ] && { warn "token is required"; return; }
  transport=$(pick_transport)
  sni=$(ask "SNI (must match the Iran server)" "www.bing.com")
  path=$(ask "HTTP path (ws/wss only)" "/tunnel")
  pool=$(ask "Warm connections to keep open" 8)

  cfg=$(jq -n --arg s "$ip:$port" --arg t "$transport" --arg tok "$token" \
              --arg sn "$sni" --arg p "$path" --argjson pool "$pool" \
        '{mode:"client", server:$s, transport:$t, token:$tok, sni:$sn, path:$p, pool:$pool}')
  save_cfg "$cfg"
  ok "client configured"
  echo "  ${D}Ports are chosen on the Iran side; this machine only dials out.${N}"
  restart_service
}

# ------------------------------------------------------------------ forwards

add_entry() {
  local name="$1" proto="$2" port="$3" rport="${4:-$3}" tmp
  [ -z "$port" ] && { warn "port is required"; return; }
  if [ "$port" = 22 ] || [ "$port" = "$(jq -r '.listen // ""' "$CFG" | sed 's/.*://')" ]; then
    warn "refusing to forward port $port - it would break SSH or the tunnel itself"
    return
  fi
  tmp=$(jq --arg n "$name" --arg p "$proto" \
           --arg l "0.0.0.0:$port" --arg t "127.0.0.1:$rport" \
        '.forwards |= (map(select(.listen != $l or .net != $p)) + [{name:$n, listen:$l, net:$p, target:$t}])' "$CFG")
  echo "$tmp" | jq . > "$CFG"
  open_port "$port" "$proto"
  ok "$proto $port -> 127.0.0.1:$rport ($name)"
}

add_forward() {
  [ -f "$CFG" ] || { warn "no config yet, run option 2 first"; return; }
  [ "$(jq -r .mode "$CFG")" = "server" ] || { warn "forwards belong on the Iran server"; return; }
  while true; do
    echo
    echo "  ${W}Which service should this Iran server publish?${N}"
    echo "    ${R}1${N}) ${W}OpenVPN${N}         UDP 1194"
    echo "    ${R}2${N}) ${W}OpenVPN${N}         TCP 1194"
    echo "    ${R}3${N}) ${W}L2TP/IPsec${N}      UDP 500, 4500, 1701"
    echo "    ${R}4${N}) ${W}IKEv2${N}           UDP 500, 4500"
    echo "    ${R}5${N}) ${W}WireGuard${N}       UDP 51820"
    echo "    ${R}6${N}) ${W}VLESS / Xray${N}    TCP 443"
    echo "    ${R}7${N}) ${W}vpn-ui panel${N}    TCP 8081"
    echo "    ${R}8${N}) ${W}Custom port${N}"
    echo "    ${R}0${N}) ${W}Done${N}"
    local c n p pr t; read -r -p "  ${W}choice:${N} " c
    case "$c" in
      1) add_entry "OpenVPN" udp 1194 ;;
      2) add_entry "OpenVPN" tcp 1194 ;;
      3) add_entry "L2TP-IKE" udp 500; add_entry "L2TP-NATT" udp 4500
         echo "   ${D}port 1701 is not forwarded on purpose - with IPsec enabled,${N}"
         echo "   ${D}L2TP data travels inside the ESP/NAT-T flow on port 4500 and${N}"
         echo "   ${D}is delivered locally by the kernel; forwarding 1701 directly${N}"
         echo "   ${D}bypasses IPsec and confuses the session.${N}" ;;
      4) add_entry "IKEv2" udp 500; add_entry "IKEv2-NATT" udp 4500 ;;
      5) add_entry "WireGuard" udp 51820 ;;
      6) add_entry "VLESS" tcp 443 ;;
      7) add_entry "vpn-ui" tcp 8081 ;;
      8) n=$(ask "  name" "custom")
         pr=$(ask "  protocol (tcp/udp)" tcp)
         p=$(ask "  public port on THIS server" "")
         t=$(ask "  port on the FOREIGN server" "$p")
         add_entry "$n" "$pr" "$p" "$t" ;;
      0) break ;;
      *) warn "invalid choice" ;;
    esac
  done
  list_forwards
}

list_forwards() {
  [ -f "$CFG" ] || return
  echo
  echo "  ${W}Current forwards:${N}"
  jq -r '.forwards[]? | "    \(.net)\t\(.listen)\t->  \(.target)\t\(.name // "")"' "$CFG" | expand -t 12
  echo
}

del_forward() {
  [ -f "$CFG" ] || { warn "no config"; return; }
  list_forwards
  local l tmp; l=$(ask "listen address to remove (e.g. 0.0.0.0:1194)" "")
  [ -z "$l" ] && return
  tmp=$(jq --arg l "$l" '.forwards |= map(select(.listen != $l))' "$CFG")
  echo "$tmp" | jq . > "$CFG"
  ok "removed $l"
}

# ------------------------------------------------------------------ manage

set_field() {
  local tmp
  tmp=$(jq --arg k "$1" --arg v "$2" '.[$k]=$v' "$CFG") || { warn "edit failed"; return; }
  echo "$tmp" | jq . > "$CFG"
  ok "$1 = $2"
}

edit_settings() {
  [ -f "$CFG" ] || { warn "no configuration yet"; return; }
  local mode; mode=$(jq -r .mode "$CFG")
  while true; do
    echo
    echo "  ${W}${BD}Settings${N} ${D}($mode)${N}"
    echo "    transport : ${W}$(jq -r .transport "$CFG")${N}"
    echo "    token     : ${W}$(jq -r .token "$CFG")${N}"
    echo "    sni       : ${W}$(jq -r .sni "$CFG")${N}"
    echo "    path      : ${W}$(jq -r .path "$CFG")${N}"
    if [ "$mode" = server ]; then
      echo "    listen    : ${W}$(jq -r .listen "$CFG")${N}"
    else
      echo "    server    : ${W}$(jq -r .server "$CFG")${N}"
      echo "    pool      : ${W}$(jq -r .pool "$CFG")${N}"
    fi
    echo
    echo "   ${R}1${N}) ${W}transport${N}    ${D}tcp / tls / ws / wss${N}"
    echo "   ${R}2${N}) ${W}token${N}        ${D}shared secret - must match on both servers${N}"
    echo "   ${R}3${N}) ${W}SNI${N}          ${D}fake hostname for tls/ws/wss${N}"
    echo "   ${R}4${N}) ${W}path${N}         ${D}HTTP path for ws/wss${N}"
    if [ "$mode" = server ]; then
      echo "   ${R}5${N}) ${W}tunnel port${N}  ${D}what the foreign server dials${N}"
    else
      echo "   ${R}5${N}) ${W}Iran ip:port${N} ${D}where this client connects${N}"
      echo "   ${R}6${N}) ${W}pool${N}         ${D}warm connections kept open${N}"
    fi
    echo "   ${R}7${N}) ${W}Performance preset${N}  ${D}BBR + buffer tuning${N}"
    echo "   ${R}0${N}) ${W}back${N}"
    local c v tmp; read -r -p "  ${W}choice:${N} " c
    case "$c" in
      1) v=$(pick_transport); set_field transport "$v" ;;
      2) v=$(ask "new token" ""); [ -n "$v" ] && set_field token "$v" ;;
      3) v=$(ask "new SNI" "www.bing.com"); set_field sni "$v" ;;
      4) v=$(ask "new path" "/tunnel"); set_field path "$v" ;;
      5) if [ "$mode" = server ]; then
           v=$(ask "new tunnel port" 8443); set_field listen "0.0.0.0:$v"; open_port "$v" tcp
         else
           v=$(ask "Iran server ip:port" "$(jq -r .server "$CFG")"); set_field server "$v"
         fi ;;
      6) [ "$mode" = client ] || { warn "client only"; continue; }
         v=$(ask "warm connections" 8)
         tmp=$(jq --argjson p "$v" '.pool=$p' "$CFG") && echo "$tmp" | jq . > "$CFG" && ok "pool = $v" ;;
      7) performance ;;
      0) break ;;
      *) warn "invalid choice" ;;
    esac
  done
  echo
  warn "transport, token, SNI and path must match on BOTH servers"
  restart_service
}

show_status() {
  echo
  systemctl status bomalo --no-pager -l 2>/dev/null | head -12
  echo
  if [ -f "$CFG" ]; then
    echo "  mode      : ${W}$(jq -r .mode "$CFG")${N}"
    echo "  transport : ${W}$(jq -r .transport "$CFG")${N}"
    echo "  token     : ${W}$(jq -r .token "$CFG")${N}"
    [ "$(jq -r .mode "$CFG")" = "server" ] && list_forwards
  else
    warn "no configuration at $CFG"
  fi
}

write_cron() {
  {
    echo "# Bomalo Tunnel watchdog"
    echo "PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"
    echo "*/5 * * * * root systemctl is-active --quiet bomalo || systemctl restart bomalo"
    [ "$1" = 1 ] && echo "0 4 * * * root systemctl restart bomalo"
  } > "$CRON"
  chmod 0644 "$CRON"
  systemctl restart cron 2>/dev/null || systemctl restart crond 2>/dev/null || true
  ok "watchdog enabled"
}

watchdog() {
  command -v crontab >/dev/null 2>&1 || pkg_install cron >/dev/null 2>&1
  while true; do
    echo
    echo "  ${W}${BD}Watchdog${N}  ${D}current:${N} $( [ -f "$CRON" ] && echo "${G}enabled${N}" || echo "${W}disabled${N}" )"
    echo "   ${R}1${N}) ${W}check every 5 minutes, restart if the service is down${N}"
    echo "   ${R}2${N}) ${W}the same, plus a daily restart at 04:00${N}"
    echo "   ${R}3${N}) ${W}disable${N}"
    echo "   ${R}0${N}) ${W}back${N}"
    local c; read -r -p "  ${W}choice:${N} " c
    case "$c" in
      1) write_cron 0 ;;
      2) write_cron 1 ;;
      3) rm -f "$CRON"; ok "watchdog disabled" ;;
      0) break ;;
      *) warn "invalid choice" ;;
    esac
  done
}

apply_perf_preset() {
  local level="$1" rmem wmem
  case "$level" in
    1) rmem=4194304;  wmem=4194304  ;;   # Balance - light on RAM, small/shared VPS
    2) rmem=16777216; wmem=16777216 ;;   # Turbo - tuned default for Iran<->abroad links
    3) rmem=33554432; wmem=33554432 ;;   # Aggressive - max headroom, more RAM
    *) warn "invalid preset"; return ;;
  esac
  sed -i '/# Bomalo Tunnel performance preset/,/# end Bomalo Tunnel preset/d' /etc/sysctl.conf
  {
    echo "# Bomalo Tunnel performance preset"
    echo "net.core.default_qdisc=fq"
    echo "net.ipv4.tcp_congestion_control=bbr"
    echo "net.core.rmem_max=$rmem"
    echo "net.core.wmem_max=$wmem"
    echo "# end Bomalo Tunnel preset"
  } >> /etc/sysctl.conf
  sysctl -p >/dev/null 2>&1
  ok "applied - tcp_congestion_control is now $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
}

performance() {
  echo
  echo "  ${W}${BD}Performance preset${N}  ${D}applies BBR congestion control + socket buffer sizing${N}"
  echo "   ${R}1${N}) ${W}Balance${N}      ${D}light on RAM - small or shared VPS${N}"
  echo "   ${R}2${N}) ${W}Turbo${N}        ${D}recommended - tuned for Iran<->abroad links${N}"
  echo "   ${R}3${N}) ${W}Aggressive${N}   ${D}max throughput headroom - needs more RAM${N}"
  echo "   ${R}0${N}) ${W}back${N}"
  local c; read -r -p "  ${W}choice:${N} " c
  case "$c" in
    1|2|3) apply_perf_preset "$c" ;;
    0) return ;;
    *) warn "invalid choice" ;;
  esac
}

uninstall() {
  read -r -p "  ${W}Remove Bomalo Tunnel completely?${N} [y/N]: " a
  [[ "$a" =~ ^[Yy]$ ]] || return
  systemctl disable --now bomalo >/dev/null 2>&1
  rm -f "$UNIT" "$BIN" "$CRON" "$MENU" /usr/local/bin/bm
  rm -rf "$CFG_DIR" "$SRC_DIR"
  systemctl daemon-reload
  ok "removed"
}

manage() {
  while true; do
    banner
    echo "  ${W}${BD}Manage${N}"
    echo "  ${D}------------------------------${N}"
    echo "   ${R}1${N}) ${W}Edit settings${N}   ${D}(transport, token, SNI, port)${N}"
    echo "   ${R}2${N}) ${W}Status${N}"
    echo "   ${R}3${N}) ${W}Live logs${N}"
    echo "   ${R}4${N}) ${W}Restart service${N}"
    echo "   ${R}5${N}) ${W}Watchdog / cron${N}"
    echo "   ${R}6${N}) ${W}Uninstall${N}"
    echo "   ${R}0${N}) ${W}Back${N}"
    echo
    local c; read -r -p "  ${W}choice:${N} " c
    case "$c" in
      1) edit_settings; pause ;;
      2) show_status; pause ;;
      3) journalctl -u bomalo -f -n 50 ;;
      4) restart_service; pause ;;
      5) watchdog ;;
      6) uninstall; pause ;;
      0) break ;;
      *) warn "invalid choice"; sleep 1 ;;
    esac
  done
}

# ------------------------------------------------------------------ main menu

menu() {
  while true; do
    banner
    local ver st mode
    ver=$(bin_version 2>/dev/null) || ver="not installed"
    if systemctl is-active --quiet bomalo 2>/dev/null; then st="${G}running${N}"
    elif [ -f "$CFG" ]; then st="${W}stopped${N}"
    else st="${W}not configured${N}"; fi
    mode=""
    [ -f "$CFG" ] && mode="   ${D}mode:${N} ${W}$(jq -r .mode "$CFG")${N}"
    echo "  ${W}$ver${N}   ${D}service:${N} $st$mode"
    echo "  ${D}------------------------------${N}"
    echo "   ${R}1${N}) ${W}Install / update the binary${N}"
    echo "   ${R}2${N}) ${W}Set up as IRAN side${N}      ${D}(server)${N}"
    echo "   ${R}3${N}) ${W}Set up as FOREIGN side${N}   ${D}(client)${N}"
    echo "   ${R}4${N}) ${W}Add forwarded ports${N}      ${D}(Iran)${N}"
    echo "   ${R}5${N}) ${W}Remove a forwarded port${N}  ${D}(Iran)${N}"
    echo "   ${R}6${N}) ${W}Manage${N}"
    echo "   ${R}0${N}) ${W}Exit${N}"
    echo
    local c; read -r -p "  ${W}choice:${N} " c
    case "$c" in
      1) install_binary; pause ;;
      2) [ -x "$BIN" ] || install_binary; setup_server; pause ;;
      3) [ -x "$BIN" ] || install_binary; setup_client; pause ;;
      4) add_forward; restart_service; pause ;;
      5) del_forward; restart_service; pause ;;
      6) manage ;;
      0) clear 2>/dev/null; exit 0 ;;
      *) warn "invalid choice"; sleep 1 ;;
    esac
  done
}

require_root
ensure_deps
install_shortcut >/dev/null 2>&1
menu
