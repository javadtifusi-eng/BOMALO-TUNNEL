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
- TCP and UDP port forwarding, including NAT-T for L2TP/IPsec and IKEv2
- Token-based authentication on every tunnel connection
- WireGuard bridge (`bm` → Manage → WireGuard bridge) for protocols like
  L2TP/IPsec whose peer identity needs a stable source address, which the
  app-level relay alone cannot give them
- `install.sh`: one-line interactive installer/manager (`bm`) covering
  install/update, server and client setup, adding/removing forwarded
  ports, live logs, a BBR + socket-buffer performance preset, and a
  watchdog cron job
- systemd service management
- English, Persian and Russian documentation

### Security
- Per-connection token authentication (constant-time comparison)
- Self-signed TLS certificate generated fresh on every server start

Standard library only — no third-party Go modules.
