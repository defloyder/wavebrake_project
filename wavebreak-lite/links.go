package main

import (
	"encoding/base64"
	"errors"
	"fmt"
	"net/url"
	"strconv"
	"strings"
)

// ShareLink is the part of a share link sing-box needs. Only what Core
// hands out (VLESS REALITY / TLS, Trojan, Shadowsocks, Hysteria2) is read.
type ShareLink struct {
	Raw         string
	Protocol    string // vless | trojan | shadowsocks | hysteria2
	Host        string
	Port        int
	Credential  string
	Method      string // shadowsocks
	Network     string // tcp | ws | grpc | httpupgrade
	Security    string // none | tls | reality
	SNI         string
	Fingerprint string
	PublicKey   string
	ShortID     string
	Flow        string
	Path        string
	HostHeader  string
	ServiceName string
	Insecure    bool
	Obfs        string
	ObfsPass    string
	PortHopping string
	Label       string
}

var errUnsupported = errors.New("unsupported link")

// ParseShareLink reads one share link.
func ParseShareLink(raw string) (*ShareLink, error) {
	raw = strings.TrimSpace(raw)
	u, err := url.Parse(raw)
	if err != nil {
		return nil, err
	}
	l := &ShareLink{Raw: raw, Network: "tcp", Security: "none", Label: u.Fragment}
	q := u.Query()
	switch strings.ToLower(u.Scheme) {
	case "vless":
		l.Protocol = "vless"
	case "trojan":
		l.Protocol = "trojan"
		l.Security = "tls"
	case "hysteria2", "hy2":
		l.Protocol = "hysteria2"
		l.Security = "tls"
	case "ss":
		return parseShadowsocks(u, l)
	default:
		return nil, errUnsupported
	}
	// Cloak-wrapped and certificate-pinned Hysteria2 need the bridge the
	// Lite build doesn't have; Core doesn't send them to it anyway.
	if q.Get("cloak") == "1" || q.Get("pinSHA256") != "" {
		return nil, errUnsupported
	}
	l.Host = u.Hostname()
	port, err := strconv.Atoi(u.Port())
	if err != nil || port <= 0 {
		return nil, fmt.Errorf("bad port in %s link", l.Protocol)
	}
	l.Port = port
	if u.User != nil {
		l.Credential = u.User.Username()
		if p, ok := u.User.Password(); ok && l.Protocol == "hysteria2" {
			l.Credential += ":" + p
		}
	}
	if v := q.Get("type"); v != "" {
		l.Network = strings.ToLower(v)
	}
	if v := q.Get("security"); v != "" {
		l.Security = strings.ToLower(v)
	}
	l.SNI = q.Get("sni")
	if l.SNI == "" {
		l.SNI = q.Get("peer")
	}
	l.Fingerprint = q.Get("fp")
	l.PublicKey = q.Get("pbk")
	l.ShortID = q.Get("sid")
	l.Flow = q.Get("flow")
	l.Path = q.Get("path")
	l.HostHeader = q.Get("host")
	l.ServiceName = q.Get("serviceName")
	l.Insecure = q.Get("insecure") == "1" || q.Get("allowInsecure") == "1"
	l.Obfs = q.Get("obfs")
	l.ObfsPass = q.Get("obfs-password")
	l.PortHopping = q.Get("mport")
	if l.Credential == "" || l.Host == "" {
		return nil, fmt.Errorf("incomplete %s link", l.Protocol)
	}
	return l, nil
}

func parseShadowsocks(u *url.URL, l *ShareLink) (*ShareLink, error) {
	l.Protocol = "shadowsocks"
	if u.User != nil && u.Port() != "" {
		info := u.User.Username()
		if p, ok := u.User.Password(); ok {
			l.Method, l.Credential = info, p
		} else if dec, err := decodeB64(info); err == nil {
			l.Method, l.Credential, _ = strings.Cut(dec, ":")
		}
		l.Host = u.Hostname()
		l.Port, _ = strconv.Atoi(u.Port())
	} else {
		dec, err := decodeB64(u.Host)
		if err != nil {
			return nil, err
		}
		userinfo, hostport, ok := strings.Cut(dec, "@")
		if !ok {
			return nil, errUnsupported
		}
		l.Method, l.Credential, _ = strings.Cut(userinfo, ":")
		host, port, ok := strings.Cut(hostport, ":")
		if !ok {
			return nil, errUnsupported
		}
		l.Host = host
		l.Port, _ = strconv.Atoi(port)
	}
	if l.Method == "" || l.Credential == "" || l.Port <= 0 {
		return nil, errUnsupported
	}
	return l, nil
}

func decodeB64(s string) (string, error) {
	for _, enc := range []*base64.Encoding{base64.RawURLEncoding, base64.URLEncoding, base64.RawStdEncoding, base64.StdEncoding} {
		if b, err := enc.DecodeString(s); err == nil {
			return string(b), nil
		}
	}
	return "", errors.New("not base64")
}

// ProtocolName is the short protocol label shown next to a server.
func (l *ShareLink) ProtocolName() string {
	switch {
	case l.Protocol == "hysteria2":
		return "Hysteria2"
	case l.Security == "reality":
		return "REALITY"
	case l.Protocol == "vless" && l.Network == "ws":
		return "CDN"
	case l.Protocol == "vless":
		return "Direct"
	case l.Protocol == "trojan":
		return "Trojan"
	default:
		return "Shadowsocks"
	}
}

// Place splits the label into a country code (from a leading flag emoji)
// and the place without the "(protocol)" note:
// "🇹🇷 Turkey, Istanbul (Direct-TLS)" → ("TR", "Turkey, Istanbul").
// Windows browsers don't draw flag emoji, so the code is shown instead.
func (l *ShareLink) Place() (country, place string) {
	runes := []rune(l.Label)
	text := l.Label
	if len(runes) >= 2 && isRegional(runes[0]) && isRegional(runes[1]) {
		country = string([]rune{'A' + (runes[0] - 0x1F1E6), 'A' + (runes[1] - 0x1F1E6)})
		text = string(runes[2:])
	}
	text = strings.TrimSpace(text)
	if i := strings.Index(text, " ("); i > 0 {
		text = text[:i]
	}
	if text == "" {
		text = l.Host
	}
	return country, text
}

func isRegional(r rune) bool { return r >= 0x1F1E6 && r <= 0x1F1FF }

// Outbound is the sing-box outbound for the link, tagged "proxy" — the
// shapes the Windows app builds (wavebreak_links/lib/src/singbox.dart).
func (l *ShareLink) Outbound() map[string]any {
	out := map[string]any{"tag": "proxy", "server": l.Host, "server_port": l.Port}
	switch l.Protocol {
	case "vless":
		out["type"] = "vless"
		out["uuid"] = l.Credential
		if l.Flow != "" && l.Network == "tcp" && l.Security == "reality" {
			out["flow"] = l.Flow
		}
		if l.Security == "tls" || l.Security == "reality" {
			out["tls"] = l.tls()
		}
		if t := l.transport(); t != nil {
			out["transport"] = t
		}
	case "trojan":
		out["type"] = "trojan"
		out["password"] = l.Credential
		out["tls"] = l.tls()
		if t := l.transport(); t != nil {
			out["transport"] = t
		}
	case "shadowsocks":
		out["type"] = "shadowsocks"
		out["method"] = l.Method
		out["password"] = l.Credential
	case "hysteria2":
		out["type"] = "hysteria2"
		out["password"] = l.Credential
		out["tls"] = l.tls()
		if l.Obfs != "" {
			obfs := map[string]any{"type": l.Obfs}
			if l.ObfsPass != "" {
				obfs["password"] = l.ObfsPass
			}
			out["obfs"] = obfs
		}
		if l.PortHopping != "" {
			var ports []string
			for _, r := range strings.Split(l.PortHopping, ",") {
				ports = append(ports, strings.ReplaceAll(strings.TrimSpace(r), "-", ":"))
			}
			out["server_ports"] = ports
			out["hop_interval"] = "15s"
		}
	}
	return out
}

func (l *ShareLink) tls() map[string]any {
	t := map[string]any{"enabled": true}
	if l.SNI != "" {
		t["server_name"] = l.SNI
	}
	if l.Insecure {
		t["insecure"] = true
	}
	if l.Fingerprint != "" {
		t["utls"] = map[string]any{"enabled": true, "fingerprint": l.Fingerprint}
	}
	if l.Security == "reality" && l.PublicKey != "" {
		r := map[string]any{"enabled": true, "public_key": l.PublicKey}
		if l.ShortID != "" {
			r["short_id"] = l.ShortID
		}
		t["reality"] = r
	}
	// Split the TLS ClientHello across TCP segments, as the Windows app
	// does (not for Hysteria2: QUIC has no TCP handshake to split).
	if l.Protocol != "hysteria2" && (l.Security == "tls" || l.Security == "reality") {
		t["fragment"] = true
	}
	return t
}

func (l *ShareLink) transport() map[string]any {
	switch l.Network {
	case "ws":
		t := map[string]any{"type": "ws", "path": orDefault(l.Path, "/")}
		if l.HostHeader != "" {
			t["headers"] = map[string]any{"Host": l.HostHeader}
		}
		return t
	case "grpc":
		return map[string]any{"type": "grpc", "service_name": l.ServiceName}
	case "httpupgrade":
		t := map[string]any{"type": "httpupgrade", "path": orDefault(l.Path, "/")}
		if l.HostHeader != "" {
			t["host"] = l.HostHeader
		}
		return t
	}
	return nil
}

func orDefault(s, d string) string {
	if s == "" {
		return d
	}
	return s
}

// SingBoxConfig is the full config: the Windows app's (TUN capturing all
// traffic, DNS over HTTPS, everything through the proxy) without its
// Clash API.
func SingBoxConfig(l *ShareLink) map[string]any {
	return map[string]any{
		"log": map[string]any{"level": "warn", "timestamp": true},
		"dns": map[string]any{
			"servers":  []any{map[string]any{"type": "https", "tag": "remote", "server": "1.1.1.1"}},
			"final":    "remote",
			"strategy": "prefer_ipv4",
		},
		"inbounds": []any{map[string]any{
			"type":           "tun",
			"interface_name": "wavebreak",
			"address":        []string{"172.19.0.1/30"},
			"mtu":            1400,
			"auto_route":     true,
			"strict_route":   true,
			"stack":          "system",
		}},
		"outbounds": []any{l.Outbound(), map[string]any{"type": "direct", "tag": "direct"}},
		"route":     map[string]any{"auto_detect_interface": true, "final": "proxy"},
	}
}
