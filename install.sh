#!/usr/bin/env bash
# Bomalo Tunnel installer
#   bash <(curl -fsSL https://raw.githubusercontent.com/javadtifusi-eng/pashm/main/install.sh)
set -uo pipefail

REPO_USER="javadtifusi-eng"
REPO_NAME="BOMALO-TUNNEL"
BRANCH="main"
RAW="https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${BRANCH}"
RELEASE="https://github.com/${REPO_USER}/${REPO_NAME}/releases/latest/download"

BIN=/usr/local/bin/bomalo
CFG_DIR=/etc/bomalo
CFG=$CFG_DIR/config.json
UNIT=/etc/systemd/system/bomalo.service
SRC_DIR=/opt/bomalo-src
GO_MIN=1.21

R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[36m'; D=$'\e[2m'; N=$'\e[0m'
M=$'\e[35m'; W=$'\e[97m'; BD=$'\e[1m'; GLD=$'\e[38;5;179m'; RED=$'\e[38;5;167m'

info() { echo "${B}==>${N} $*"; }
ok()   { echo "${G} ok ${N} $*"; }
warn() { echo "${Y} !! ${N} $*"; }
die()  { echo "${R}fail${N} $*"; exit 1; }

banner() {
  clear 2>/dev/null || true
  printf '%s' "$GLD"
cat <<'EOF'
  ____                        _         _____                       _
 | __ )  ___  _ __ ___   __ _| | ___   |_   _|   _ _ __  _ __   ___| |
 |  _ \ / _ \| '_ ` _ \ / _` | |/ _ \    | || | | | '_ \| '_ \ / _ \ |
 | |_) | (_) | | | | | | (_| | | (_) |   | || |_| | | | | | | |  __/ |
 |____/ \___/|_| |_| |_|\__,_|_|\___/    |_| \__,_|_| |_|_| |_|\___|_|
EOF
  printf '%s' "$N"
  echo "        ${RED}reverse tunnel${N}  ${D}client-initiated · zero inbound ports${N}"
  echo
}

pause() { echo; read -r -p "  ${D}press Enter to continue${N} " _; }

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
  [ ${#need[@]} -gt 0 ] && { info "installing dependencies: ${need[*]}"; pkg_install "${need[@]}"; }
  command -v jq >/dev/null 2>&1 || die "jq is required and could not be installed"
}

arch_tag() {
  case "$(uname -m)" in
    x86_64|amd64) echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    armv7l) echo armv6l ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
}

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

  # Google's download hosts are blocked from many Iranian networks; the
  # distribution mirrors usually are not.
  warn "the Go download servers are unreachable from this network"
  info "falling back to the distribution package"
  pkg_install golang-go >/dev/null 2>&1 || pkg_install golang >/dev/null 2>&1 || true
  export PATH=$PATH:/usr/local/go/bin
  if have_go; then ok "using $(go version | awk '{print $3}')"; return; fi

  echo
  die "no usable Go toolchain (need >= $GO_MIN).
     Build the binary somewhere with working access instead:
       git clone https://github.com/${REPO_USER}/${REPO_NAME} && cd ${REPO_NAME} && bash build.sh
     then upload dist/* to a GitHub release tagged \"latest\" and run option 1 again."
}

install_binary() {
  stop_legacy
  local a; a=$(arch_tag)
  info "looking for a prebuilt binary"
  if curl -fsSL "${RELEASE}/bomalo-linux-${a}" -o /tmp/bomalo 2>/dev/null && [ -s /tmp/bomalo ]; then
    install -m 0755 /tmp/bomalo "$BIN"; rm -f /tmp/bomalo
    ok "installed $(bin_version)"
    install_shortcut
    return
  fi
  warn "no release binary found, building from source"
  ensure_go
  export PATH=$PATH:/usr/local/go/bin
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
  install_shortcut
}

install_shortcut() {
  if [ -f ./install.sh ]; then
    install -m 0755 ./install.sh /usr/local/bin/bomalo-menu 2>/dev/null
  else
    curl -fsSL "$RAW/install.sh" -o /usr/local/bin/bomalo-menu 2>/dev/null && \
      chmod 0755 /usr/local/bin/bomalo-menu
  fi
  [ -x /usr/local/bin/bomalo-menu ] || return
  ln -sf /usr/local/bin/bomalo-menu /usr/local/bin/bm
  ok "type ${W}bm${N} or ${W}bomalo-menu${N} to open this menu again"
}

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

save_cfg() { # save_cfg <json>
  mkdir -p "$CFG_DIR"
  echo "$1" | jq . > "$CFG" || die "could not write config"
  chmod 600 "$CFG"
}

restart_service() {
  write_unit
  systemctl enable bomalo >/dev/null 2>&1
  systemctl restart bomalo
  sleep 1
  systemctl is-active --quiet bomalo && ok "service is running" || warn "service failed, check option 6 (logs)"
}

open_port() { # open_port <port> <tcp|udp>
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow "$1/$2" >/dev/null 2>&1 && echo "   ${D}ufw: opened $1/$2${N}"
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port="$1/$2" >/dev/null 2>&1
    firewall-cmd --reload >/dev/null 2>&1 && echo "   ${D}firewalld: opened $1/$2${N}"
  fi
}

ask() { # ask <prompt> <default> -> echoes answer
  local p="$1" d="${2:-}" a
  if [ -n "$d" ]; then read -r -p "$p [$d]: " a; echo "${a:-$d}"
  else read -r -p "$p: " a; echo "$a"; fi
}

pick_transport() {
  echo >&2
  echo "  Transport:" >&2
  echo "    1) tls   - TLS with a self-signed certificate (recommended)" >&2
  echo "    2) wss   - HTTP/WebSocket upgrade inside TLS (best against DPI)" >&2
  echo "    3) ws    - plain HTTP/WebSocket upgrade" >&2
  echo "    4) tcp   - raw TCP, fastest, no disguise" >&2
  local c; read -r -p "  choice [1]: " c
  case "${c:-1}" in 2) echo wss ;; 3) echo ws ;; 4) echo tcp ;; *) echo tls ;; esac
}

# ------------------------------------------------------------------ server

setup_server() {
  echo
  info "Configuring this machine as the IRAN server (public entry point)"
  local port token transport sni path cfg
  port=$(ask "  Tunnel port (the foreign server dials this)" 8443)
  token=$(ask "  Shared token (leave empty to generate)" "")
  [ -z "$token" ] && token=$($BIN -gen-token)
  transport=$(pick_transport)
  sni=$(ask "  SNI / fake hostname" "www.bing.com")
  path=$(ask "  HTTP path (ws/wss only)" "/tunnel")

  cfg=$(jq -n --arg l "0.0.0.0:$port" --arg t "$transport" --arg tok "$token" \
              --arg s "$sni" --arg p "$path" \
        '{mode:"server", listen:$l, transport:$t, token:$tok, sni:$s, path:$p, forwards:[]}')
  save_cfg "$cfg"
  open_port "$port" tcp
  echo
  ok "server configured"
  echo
  echo "  ${Y}Copy these values to the foreign server:${N}"
  echo "    server    : $(curl -fsSL --max-time 4 https://api.ipify.org 2>/dev/null || echo YOUR_IRAN_IP):$port"
  echo "    token     : $token"
  echo "    transport : $transport"
  echo "    sni       : $sni"
  echo "    path      : $path"
  echo
  read -r -p "  Add forwarded ports now? [Y/n]: " a
  [[ "${a:-y}" =~ ^[Yy]?$ ]] && add_forward
  restart_service
}

add_forward() {
  [ -f "$CFG" ] || { warn "no config yet, run option 2 first"; return; }
  [ "$(jq -r .mode "$CFG")" = "server" ] || { warn "forwards are configured on the Iran server only"; return; }
  while true; do
    echo
    echo "  Which service do you want to publish on this Iran server?"
    echo "    1) OpenVPN            UDP 1194"
    echo "    2) OpenVPN            TCP 1194"
    echo "    3) L2TP/IPsec         UDP 500, 4500, 1701"
    echo "    4) IKEv2              UDP 500, 4500"
    echo "    5) WireGuard          UDP 51820"
    echo "    6) VLESS / Xray       TCP 443"
    echo "    7) vpn-ui panel       TCP 8081"
    echo "    8) Custom port"
    echo "    0) Done"
    local c; read -r -p "  choice: " c
    case "$c" in
      1) add_entry "OpenVPN" udp 1194 ;;
      2) add_entry "OpenVPN" tcp 1194 ;;
      3) add_entry "L2TP-IKE" udp 500; add_entry "L2TP-NATT" udp 4500; add_entry "L2TP" udp 1701
         echo "   ${D}note: IPsec ESP is carried inside UDP 4500 (NAT-T), which is what this relay forwards${N}" ;;
      4) add_entry "IKEv2" udp 500; add_entry "IKEv2-NATT" udp 4500 ;;
      5) add_entry "WireGuard" udp 51820 ;;
      6) add_entry "VLESS" tcp 443 ;;
      7) add_entry "vpn-ui" tcp 8081 ;;
      8) local n p pr t
         n=$(ask "   name" "custom")
         pr=$(ask "   protocol (tcp/udp)" tcp)
         p=$(ask "   public port on this server" "")
         t=$(ask "   port on the foreign server" "$p")
         add_entry "$n" "$pr" "$p" "$t" ;;
      0) break ;;
      *) warn "invalid choice" ;;
    esac
  done
  list_forwards
}

add_entry() { # add_entry <name> <tcp|udp> <public port> [remote port]
  local name="$1" proto="$2" port="$3" rport="${4:-$3}"
  [ -z "$port" ] && { warn "port is required"; return; }
  local tmp
  tmp=$(jq --arg n "$name" --arg p "$proto" \
           --arg l "0.0.0.0:$port" --arg t "127.0.0.1:$rport" \
        '.forwards |= (map(select(.listen != $l or .net != $p)) + [{name:$n, listen:$l, net:$p, target:$t}])' "$CFG")
  echo "$tmp" | jq . > "$CFG"
  open_port "$port" "$proto"
  ok "$proto $port -> 127.0.0.1:$rport ($name)"
}

list_forwards() {
  [ -f "$CFG" ] || { warn "no config"; return; }
  echo
  echo "  Current forwards:"
  jq -r '.forwards[]? | "    \(.net)\t\(.listen)\t->  \(.target)\t\(.name // "")"' "$CFG" | expand -t 12
  echo
}

del_forward() {
  list_forwards
  local l; l=$(ask "  listen address to remove (e.g. 0.0.0.0:1194)" "")
  [ -z "$l" ] && return
  local tmp; tmp=$(jq --arg l "$l" '.forwards |= map(select(.listen != $l))' "$CFG")
  echo "$tmp" | jq . > "$CFG"
  ok "removed $l"
}

# ------------------------------------------------------------------ client

setup_client() {
  echo
  info "Configuring this machine as the FOREIGN server (exit node, runs the VPN panel)"
  local ip port token transport sni path pool cfg
  ip=$(ask "  Iran server IP" "")
  [ -z "$ip" ] && { warn "IP is required"; return; }
  port=$(ask "  Tunnel port" 8443)
  token=$(ask "  Shared token (from the Iran server)" "")
  [ -z "$token" ] && { warn "token is required"; return; }
  transport=$(pick_transport)
  sni=$(ask "  SNI / fake hostname (must match the Iran server)" "www.bing.com")
  path=$(ask "  HTTP path (ws/wss only)" "/tunnel")
  pool=$(ask "  Warm connections to keep open" 8)

  cfg=$(jq -n --arg s "$ip:$port" --arg t "$transport" --arg tok "$token" \
              --arg sn "$sni" --arg p "$path" --argjson pool "$pool" \
        '{mode:"client", server:$s, transport:$t, token:$tok, sni:$sn, path:$p, pool:$pool}')
  save_cfg "$cfg"
  ok "client configured"
  echo "  ${D}Ports are chosen on the Iran side; this machine only dials out.${N}"
  restart_service
}

# ------------------------------------------------------------------ misc

show_status() {
  echo
  systemctl status bomalo --no-pager -l 2>/dev/null | head -15
  echo
  if [ -f "$CFG" ]; then
    echo "  mode      : $(jq -r .mode "$CFG")"
    echo "  transport : $(jq -r .transport "$CFG")"
    echo "  token     : $(jq -r .token "$CFG")"
    [ "$(jq -r .mode "$CFG")" = "server" ] && list_forwards
  else
    warn "no configuration at $CFG"
  fi
}


edit_settings() {
  [ -f "$CFG" ] || { warn "no configuration yet"; return; }
  local mode; mode=$(jq -r .mode "$CFG")
  while true; do
    echo
    echo "  ${BD}Current settings${N} ${D}($mode)${N}"
    echo "    transport : $(jq -r .transport "$CFG")"
    echo "    token     : $(jq -r .token "$CFG")"
    echo "    sni       : $(jq -r .sni "$CFG")"
    echo "    path      : $(jq -r .path "$CFG")"
    if [ "$mode" = server ]; then
      echo "    listen    : $(jq -r .listen "$CFG")"
    else
      echo "    server    : $(jq -r .server "$CFG")"
      echo "    pool      : $(jq -r .pool "$CFG")"
    fi
    echo
    echo "   ${B}1${N}) transport      ${B}2${N}) token         ${B}3${N}) SNI"
    echo "   ${B}4${N}) HTTP path     ${B}5${N}) address/port   ${B}6${N}) pool ${D}(client)${N}"
    echo "   ${B}0${N}) back"
    local c v; read -r -p "  choice: " c
    case "$c" in
      1) v=$(pick_transport); set_field transport "$v" ;;
      2) v=$(ask "  new token" ""); [ -n "$v" ] && set_field token "$v" ;;
      3) v=$(ask "  new SNI" "www.bing.com"); set_field sni "$v" ;;
      4) v=$(ask "  new path" "/tunnel"); set_field path "$v" ;;
      5) if [ "$mode" = server ]; then
           v=$(ask "  new tunnel port" 8443); set_field listen "0.0.0.0:$v"; open_port "$v" tcp
         else
           v=$(ask "  Iran server ip:port" "$(jq -r .server "$CFG")"); set_field server "$v"
         fi ;;
      6) [ "$mode" = client ] || { warn "client only"; continue; }
         v=$(ask "  warm connections" 8)
         local tmp; tmp=$(jq --argjson p "$v" '.pool=$p' "$CFG") && echo "$tmp" | jq . > "$CFG"
         ok "pool = $v" ;;
      0) break ;;
      *) warn "invalid choice" ;;
    esac
  done
  echo
  warn "transport, token, SNI and path must match on BOTH servers"
  restart_service
}

set_field() { # set_field <key> <value>
  local tmp
  tmp=$(jq --arg k "$1" --arg v "$2" '.[$k]=$v' "$CFG") || { warn "edit failed"; return; }
  echo "$tmp" | jq . > "$CFG"
  ok "$1 = $2"
}

CRON=/etc/cron.d/bomalo

watchdog() {
  command -v crontab >/dev/null 2>&1 || pkg_install cron >/dev/null 2>&1
  while true; do
    echo
    echo "  ${BD}Watchdog${N}  ${D}current:${N} $( [ -f "$CRON" ] && echo "${G}enabled${N}" || echo "${D}disabled${N}" )"
    echo "   ${B}1${N}) check every 5 minutes, restart if the service is down"
    echo "   ${B}2${N}) the same, plus a daily restart at 04:00"
    echo "   ${B}3${N}) disable"
    echo "   ${B}0${N}) back"
    local c; read -r -p "  choice: " c
    case "$c" in
      1) write_cron 0 ;;
      2) write_cron 1 ;;
      3) rm -f "$CRON"; ok "watchdog disabled" ;;
      0) break ;;
      *) warn "invalid choice" ;;
    esac
  done
}

write_cron() { # write_cron <daily 0|1>
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

uninstall() {
  read -r -p "  Remove Bomalo Tunnel completely? [y/N]: " a
  [[ "$a" =~ ^[Yy]$ ]] || return
  systemctl disable --now bomalo >/dev/null 2>&1
  rm -f "$UNIT" "$BIN" "$CRON" /usr/local/bin/bomalo-menu /usr/local/bin/bm
  rm -rf "$CFG_DIR" "$SRC_DIR"
  systemctl daemon-reload
  ok "removed"
}

menu() {
  while true; do
    banner
    local st ver
    ver=$(bin_version || echo "not installed")
    if systemctl is-active --quiet bomalo 2>/dev/null; then st="${G}running${N}"
    elif [ -f "$CFG" ]; then st="${R}stopped${N}"
    else st="${D}not configured${N}"; fi
    echo "  ${W}$ver${N}   ${D}service:${N} $st$( [ -f "$CFG" ] && echo "   ${D}mode:${N} $(jq -r .mode "$CFG")" )"
    echo "  ${D}--------------------------------------------------${N}"
    echo "   ${G}1${N})  Install / update the binary"
    echo "   ${B}2${N})  Set up this server as ${W}IRAN${N} side      ${D}(server)${N}"
    echo "   ${B}3${N})  Set up this server as ${W}FOREIGN${N} side   ${D}(client)${N}"
    echo "   ${M}4${N})  Add forwarded ports              ${D}(Iran side)${N}"
    echo "   ${M}5${N})  Remove a forwarded port          ${D}(Iran side)${N}"
    echo "   ${Y}6${N})  Edit settings                    ${D}(transport, token, SNI ...)${N}"
    echo "   ${B}7${N})  Status and settings"
    echo "   ${B}8${N})  Live logs"
    echo "   ${B}9${N})  Restart service"
    echo "   ${GLD}w${N})  Watchdog / cron"
    echo "   ${RED}u${N})  Uninstall"
    echo "   ${D}0${N})  Exit"
    echo
    local c; read -r -p "  ${W}choice:${N} " c
    case "$c" in
      1) install_binary; pause ;;
      2) [ -x "$BIN" ] || install_binary; setup_server; pause ;;
      3) [ -x "$BIN" ] || install_binary; setup_client; pause ;;
      4) add_forward; restart_service; pause ;;
      5) del_forward; restart_service; pause ;;
      6) edit_settings; pause ;;
      7) show_status; pause ;;
      8) journalctl -u bomalo -f -n 50 ;;
      9) restart_service; pause ;;
      w|W) watchdog ;;
      u|U) uninstall; pause ;;
      0) clear 2>/dev/null; exit 0 ;;
      *) warn "invalid choice"; sleep 1 ;;
    esac
  done
}

require_root
ensure_deps
menu
