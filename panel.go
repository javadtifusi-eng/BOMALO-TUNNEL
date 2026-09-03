// Web panel: an optional HTTPS admin UI served by the same process, for
// editing the config, managing forwards, and restarting/watching the
// service from a browser instead of the "bm" CLI. Off unless
// config.json sets "panel": {"enabled": true, ...} (see install.sh).
//
// Auth is HTTP Basic over TLS - the frontend keeps the credentials in
// sessionStorage and attaches them to every fetch() itself rather than
// relying on the browser's native prompt, so the login screen can look
// like the rest of the app. Every write goes through validate() (the
// same one the tunnel binary itself uses) before it's saved, and a
// successful save always restarts the service so the change takes
// effect immediately - same behavior as the "bm" menu.
package main

import (
	"crypto/subtle"
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"

	"golang.org/x/crypto/bcrypt"
)

//go:embed panel_ui.html
var panelUIFiles embed.FS

// panelMu serializes reads-then-writes of the config file across
// concurrent panel requests; the tunnel binary itself never writes it.
var panelMu sync.Mutex

func hashPanelPassword(pw string) (string, error) {
	if len(pw) < 8 {
		return "", errors.New("password must be at least 8 characters")
	}
	b, err := bcrypt.GenerateFromPassword([]byte(pw), bcrypt.DefaultCost)
	return string(b), err
}

func runPanel(cfg *Config, cfgPath string) {
	tc, err := tlsServerConfig(cfg.SNI)
	if err != nil {
		log.Printf("panel: %v", err)
		return
	}

	mux := http.NewServeMux()
	// "/" is intentionally NOT behind panelAuth: it's just the static app
	// shell (no secrets in it), and the login screen it renders is this
	// app's own JS UI. If it required Basic Auth too, the browser's native
	// credential popup would intercept the very first page load before
	// that custom login screen ever got a chance to render.
	mux.HandleFunc("/", panelIndex)
	mux.HandleFunc("/api/config", panelAuth(cfg, func(w http.ResponseWriter, r *http.Request) { handleConfig(w, r, cfgPath) }))
	mux.HandleFunc("/api/forwards", panelAuth(cfg, func(w http.ResponseWriter, r *http.Request) { handleForwards(w, r, cfgPath) }))
	mux.HandleFunc("/api/restart", panelAuth(cfg, handleRestart))
	mux.HandleFunc("/api/status", panelAuth(cfg, handleStatus))
	mux.HandleFunc("/api/logs", panelAuth(cfg, handleLogs))

	srv := &http.Server{Addr: cfg.Panel.Listen, Handler: mux, TLSConfig: tc}
	log.Printf("web panel listening on %s (https)", cfg.Panel.Listen)
	log.Printf("panel: %v", srv.ListenAndServeTLS("", ""))
}

func panelIndex(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	b, err := panelUIFiles.ReadFile("panel_ui.html")
	if err != nil {
		http.Error(w, "panel UI missing", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write(b)
}

// panelAuth checks HTTP Basic credentials against cfg.Panel on every
// /api/ request; the frontend's JS attaches them itself on every fetch()
// after login. Deliberately does NOT set WWW-Authenticate: that header on
// a 401 is exactly what makes a browser pop up its own native credential
// dialog over a fetch()/XHR call too (not just full navigations), which
// would hijack a failed login attempt away from this app's own login
// screen - the JSON body here is for this app's JS to read, not for the
// browser to react to.
func panelAuth(cfg *Config, next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		user, pass, ok := r.BasicAuth()
		validUser := ok && subtle.ConstantTimeCompare([]byte(user), []byte(cfg.Panel.Username)) == 1
		validPass := ok && bcrypt.CompareHashAndPassword([]byte(cfg.Panel.PasswordHash), []byte(pass)) == nil
		if !validUser || !validPass {
			http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
			return
		}
		next(w, r)
	}
}

func writeJSON(w http.ResponseWriter, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, code int, err error) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
}

func restartTunnelService() error {
	return exec.Command("systemctl", "restart", "tifusi").Run()
}

// ---- /api/config ----------------------------------------------------

// configPatch carries only the fields a PUT actually wants to change;
// unset (nil) fields leave the on-disk value untouched.
type configPatch struct {
	Transport *string `json:"transport"`
	SNI       *string `json:"sni"`
	Path      *string `json:"path"`
	Token     *string `json:"token"`
	Pool      *int    `json:"pool"`
	MuxCon    *int    `json:"mux_con"`
	Listen    *string `json:"listen"` // server: "0.0.0.0:<port>"
	Server    *string `json:"server"` // client: "ip:port"
}

func handleConfig(w http.ResponseWriter, r *http.Request, cfgPath string) {
	switch r.Method {
	case http.MethodGet:
		cfg, err := loadConfig(cfgPath)
		if err != nil {
			writeErr(w, http.StatusInternalServerError, err)
			return
		}
		cfg.Panel = nil // never echo panel credentials back over the API
		writeJSON(w, cfg)

	case http.MethodPut:
		panelMu.Lock()
		defer panelMu.Unlock()

		var patch configPatch
		if err := json.NewDecoder(r.Body).Decode(&patch); err != nil {
			writeErr(w, http.StatusBadRequest, err)
			return
		}
		cfg, err := loadConfig(cfgPath)
		if err != nil {
			writeErr(w, http.StatusInternalServerError, err)
			return
		}
		if patch.Transport != nil {
			cfg.Transport = *patch.Transport
		}
		if patch.SNI != nil {
			cfg.SNI = *patch.SNI
		}
		if patch.Path != nil {
			cfg.Path = *patch.Path
		}
		if patch.Token != nil {
			cfg.Token = *patch.Token
		}
		if patch.Pool != nil {
			cfg.Pool = *patch.Pool
		}
		if patch.MuxCon != nil {
			cfg.MuxCon = *patch.MuxCon
		}
		if patch.Listen != nil {
			cfg.Listen = *patch.Listen
		}
		if patch.Server != nil {
			cfg.Server = *patch.Server
		}
		if err := cfg.validate(); err != nil {
			writeErr(w, http.StatusBadRequest, err)
			return
		}
		if err := writeConfigFile(cfgPath, cfg); err != nil {
			writeErr(w, http.StatusInternalServerError, err)
			return
		}
		if err := restartTunnelService(); err != nil {
			// config was saved; say so, but surface the restart failure too
			writeErr(w, http.StatusAccepted, fmt.Errorf("saved, but restart failed: %w", err))
			return
		}
		resp := *cfg
		resp.Panel = nil
		writeJSON(w, resp)

	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

// ---- /api/forwards ----------------------------------------------------

type forwardReq struct {
	Name       string `json:"name"`
	Net        string `json:"net"` // tcp | udp
	ListenPort string `json:"listen_port"`
	TargetPort string `json:"target_port"`
}

func handleForwards(w http.ResponseWriter, r *http.Request, cfgPath string) {
	panelMu.Lock()
	defer panelMu.Unlock()

	cfg, err := loadConfig(cfgPath)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, err)
		return
	}
	if cfg.Mode != "server" {
		writeErr(w, http.StatusBadRequest, errors.New("forwards belong on the Iran (server) side"))
		return
	}

	switch r.Method {
	case http.MethodGet:
		writeJSON(w, cfg.Forwards)

	case http.MethodPost:
		var req forwardReq
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeErr(w, http.StatusBadRequest, err)
			return
		}
		if req.Net != "udp" {
			req.Net = "tcp"
		}
		if req.TargetPort == "" {
			req.TargetPort = req.ListenPort
		}
		fw, err := buildForward(cfg, req)
		if err != nil {
			writeErr(w, http.StatusBadRequest, err)
			return
		}
		// replace any existing entry with the same listen+net, like add_entry in install.sh
		filtered := cfg.Forwards[:0]
		for _, existing := range cfg.Forwards {
			if existing.Listen != fw.Listen || existing.Net != fw.Net {
				filtered = append(filtered, existing)
			}
		}
		cfg.Forwards = append(filtered, fw)
		if err := writeConfigFile(cfgPath, cfg); err != nil {
			writeErr(w, http.StatusInternalServerError, err)
			return
		}
		restartTunnelService()
		writeJSON(w, cfg.Forwards)

	case http.MethodDelete:
		listen := r.URL.Query().Get("listen")
		net_ := r.URL.Query().Get("net")
		if listen == "" {
			writeErr(w, http.StatusBadRequest, errors.New("missing \"listen\" query parameter"))
			return
		}
		kept := cfg.Forwards[:0]
		for _, existing := range cfg.Forwards {
			if existing.Listen == listen && (net_ == "" || existing.Net == net_) {
				continue
			}
			kept = append(kept, existing)
		}
		cfg.Forwards = kept
		if err := writeConfigFile(cfgPath, cfg); err != nil {
			writeErr(w, http.StatusInternalServerError, err)
			return
		}
		restartTunnelService()
		writeJSON(w, cfg.Forwards)

	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

// buildForward validates a forward request the same way install.sh's
// add_entry does: no port 22, and never the tunnel's own listen port.
func buildForward(cfg *Config, req forwardReq) (Forward, error) {
	if req.ListenPort == "" {
		return Forward{}, errors.New("listen_port is required")
	}
	if _, err := strconv.Atoi(req.ListenPort); err != nil {
		return Forward{}, fmt.Errorf("listen_port must be numeric: %w", err)
	}
	if req.ListenPort == "22" {
		return Forward{}, errors.New("refusing to forward port 22 - it would break SSH")
	}
	listen := "0.0.0.0:" + req.ListenPort
	if listen == cfg.Listen {
		return Forward{}, errors.New("refusing to forward the tunnel's own port")
	}
	name := strings.TrimSpace(req.Name)
	if name == "" {
		name = "custom"
	}
	return Forward{
		Name:   name,
		Listen: listen,
		Net:    req.Net,
		Target: "127.0.0.1:" + req.TargetPort,
	}, nil
}

// ---- /api/restart, /api/status, /api/logs -----------------------------

func handleRestart(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.WriteHeader(http.StatusMethodNotAllowed)
		return
	}
	if err := restartTunnelService(); err != nil {
		writeErr(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, map[string]bool{"ok": true})
}

func handleStatus(w http.ResponseWriter, r *http.Request) {
	out, err := exec.Command("systemctl", "is-active", "tifusi").Output()
	state := strings.TrimSpace(string(out))
	if state == "" {
		state = "unknown"
	}
	writeJSON(w, map[string]interface{}{
		"state":   state,
		"running": err == nil && state == "active",
	})
}

func handleLogs(w http.ResponseWriter, r *http.Request) {
	n := r.URL.Query().Get("n")
	if n == "" {
		n = "200"
	}
	if _, err := strconv.Atoi(n); err != nil {
		n = "200"
	}
	out, err := exec.Command("journalctl", "-u", "tifusi", "-n", n, "--no-pager").CombinedOutput()
	if err != nil && len(out) == 0 {
		writeErr(w, http.StatusInternalServerError, err)
		return
	}
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	w.Write(out)
}

// writeConfigFile marshals and saves cfg, matching the permissions
// save_cfg() in install.sh uses for the same file.
func writeConfigFile(path string, cfg *Config) error {
	b, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, b, 0o600)
}
