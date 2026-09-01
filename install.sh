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

info() { echo "${B}==>${N} $*"; }
ok()   { echo "${G} ok ${N} $*"; }
warn() { echo "${Y} !! ${N} $*"; }
die()  { echo "${R}fail${N} $*"; exit 1; }

banner() {
cat <<'EOF'
  ____                        _         _____                       _
 | __ )  ___  _ __ ___   __ _| | ___   |_   _|   _ _ __  _ __   ___| |
 |  _ \ / _ \| '_ ` _ \ / _` | |/ _ \    | || | | | '_ \| '_ \ / _ \ |
 | |_) | (_) | | | | | | (_| | | (_) |   | || |_| | | | | | | |  __/ |
 |____/ \___/|_| |_| |_|\__,_|_|\___/    |_| \__,_|_| |_|_| |_|\___|_|
EOF
echo "                         reverse tunnel  ${D}installer${N}"
echo
}

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

ensure_go() {
  if command -v go >/dev/null 2>&1; then
    local have; have=$(go version | awk '{print $3}' | sed 's/go//')
    if [ "$(printf '%s\n%s\n' "$GO_MIN" "$have" | sort -V | head -1)" = "$GO_MIN" ]; then
      ok "go $have already installed"; return
    fi
    warn "go $have is older than $GO_MIN, installing a newer toolchain"
  fi
  local ver a url
  ver=$(curl -fsSL https://go.dev/VERSION?m=text 2>/dev/null | head -1)
  [ -z "$ver" ] && ver="go1.22.5"
  a=$(arch_tag); url="https://go.dev/dl/${ver}.linux-${a}.tar.gz"
  info "downloading $ver"
  curl -fsSL "$url" -o /tmp/go.tgz || die "could not download the Go toolchain"
  rm -rf /usr/local/go && tar -C /usr/local -xzf /tmp/go.tgz && rm -f /tmp/go.tgz
  export PATH=$PATH:/usr/local/go/bin
  grep -q '/usr/local/go/bin' /etc/profile 2>/dev/null || echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
  ok "go installed"
}

bin_version() { # prints the version, or nothing if $BIN is not our binary
  [ -x "$BIN" ] || return 1
  local v; v=$("$BIN" -version 2>/dev/null | head -1)
  case "$v" in bomalo\ *) echo "$v" ;; *) return 1 ;; esac
}

stop_legacy() {
  bin_version >/dev/null 2>&1 && return   # already our binary
  [ -x "$BIN" ] || return
  warn "an older bomalo (the iptables/bash version) is installed at $BIN"
  local units
  units=$(systemctl list-units --all --plain --no-legend 2>/dev/null \
          | awk '{print $1}' | grep -E '^(bomalo|tunnel)' | grep -v '^bomalo.service$')
  if [ -n "$units" ]; then
    echo "   ${D}stopping legacy services: $(echo "$units" | tr '\n' ' ')${N}"
    for u in $units; do systemctl disable --now "$u" >/dev/null 2>&1; done
  fi
  if iptables -t nat -S PREROUTING 2>/dev/null | grep -q 'DNAT'; then
    warn "old DNAT rules are still present in iptables:"
    iptables -t nat -S PREROUTING | grep DNAT | sed 's/^/     /'
    echo "   ${D}remove them one by one with: iptables -t nat -D PREROUTING <n>${N}"
    echo "   ${D}leave them in place and they will hijack the ports before the tunnel sees them${N}"
  fi
  cp -f "$BIN" "${BIN}.legacy.bak" 2>/dev/null && echo "   ${D}old script kept at ${BIN}.legacy.bak${N}"
}

install_binary() {
  stop_legacy
  local a; a=$(arch_tag)
  info "looking for a prebuilt binary"
  if curl -fsSL "${RELEASE}/bomalo-linux-${a}" -o /tmp/bomalo 2>/dev/null && [ -s /tmp/bomalo ]; then
    install -m 0755 /tmp/bomalo "$BIN"; rm -f /tmp/bomalo
    ok "installed $(bin_version)"
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

uninstall() {
  read -r -p "  Remove Bomalo Tunnel completely? [y/N]: " a
  [[ "$a" =~ ^[Yy]$ ]] || return
  systemctl disable --now bomalo >/dev/null 2>&1
  rm -f "$UNIT" "$BIN"; rm -rf "$CFG_DIR" "$SRC_DIR"
  systemctl daemon-reload
  ok "removed"
}

menu() {
  while true; do
    echo
    echo "  ${B}Bomalo Tunnel${N}  $(bin_version || echo 'not installed')"
    echo "  ------------------------------------------"
    echo "   1) Install / update the binary"
    echo "   2) Set up this server as IRAN side (server)"
    echo "   3) Set up this server as FOREIGN side (client)"
    echo "   4) Add forwarded ports        (Iran side)"
    echo "   5) Remove a forwarded port    (Iran side)"
    echo "   6) Status and settings"
    echo "   7) Live logs"
    echo "   8) Restart service"
    echo "   9) Uninstall"
    echo "   0) Exit"
    local c; read -r -p "  choice: " c
    case "$c" in
      1) install_binary ;;
      2) [ -x "$BIN" ] || install_binary; setup_server ;;
      3) [ -x "$BIN" ] || install_binary; setup_client ;;
      4) add_forward; restart_service ;;
      5) del_forward; restart_service ;;
      6) show_status ;;
      7) journalctl -u bomalo -f -n 50 ;;
      8) restart_service ;;
      9) uninstall ;;
      0) exit 0 ;;
      *) warn "invalid choice" ;;
    esac
  done
}

require_root
banner
ensure_deps
menu
