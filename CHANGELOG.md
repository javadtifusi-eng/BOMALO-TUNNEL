# Changelog

All notable changes to Tifusi Tunnel will be documented in this file.

## [1.0.0]

### Added
- Reverse tunnel engine: the foreign server dials out, so it never needs an
  open inbound port and is never contacted directly by users
- Transports: `tcp`, `tls` (self-signed certificate, fake SNI), `ws` and
  `wss` (real RFC 6455 WebSocket framing, so the Iran side can sit behind
  an nginx WebSocket proxy or a CDN)
- Multiplexed transports `tcpmux`, `wsmux`, `wssmux`: a fixed pool of
  physical connections (`mux_con`) carries many logical sessions, cutting
  socket/handshake overhead under load
- `udp` transport backed by [kcp-go](https://github.com/xtaci/kcp-go): real
  reliable UDP for lossy links, no disguise
- TCP and UDP port forwarding, including NAT-T for L2TP/IPsec and IKEv2
- Token-based authentication on every tunnel connection
- WireGuard bridge (`bm` → Manage → WireGuard bridge) for protocols like
  L2TP/IPsec whose peer identity needs a stable source address, which the
  app-level relay alone cannot give them
- ArvanCloud CDN setup guide (`bm` → server setup, ws-family transports)
  for fronting the tunnel port through a domestically-whitelisted CDN
- Web panel: an optional bilingual (English/Persian) HTTPS admin UI served
  by the same binary, for editing settings, managing forwarded ports and
  watching logs from a browser (`bm` → Manage → Web panel)
- `install.sh`: one-line interactive installer/manager (`bm`) covering
  install/update, server and client setup (transport picker grouped by
  family), adding/removing forwarded ports, a tunnel connection test,
  live logs, a BBR + socket-buffer performance preset, and a watchdog
  cron job
- systemd service management
- English, Persian and Russian documentation

### Security
- Per-connection token authentication (constant-time comparison)
- Self-signed TLS certificate generated fresh on every server start
- Web panel: HTTP Basic Auth over TLS, bcrypt-hashed password

Depends on [kcp-go](https://github.com/xtaci/kcp-go) (for the `udp`
transport) and `golang.org/x/crypto/bcrypt` (for the web panel);
otherwise standard library only.
