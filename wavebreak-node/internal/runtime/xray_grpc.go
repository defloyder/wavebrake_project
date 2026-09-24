package runtime

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"

	hcommand "github.com/xtls/xray-core/app/proxyman/command"
	"github.com/xtls/xray-core/common/protocol"
	"github.com/xtls/xray-core/common/serial"
	"github.com/xtls/xray-core/proxy/shadowsocks"
	"github.com/xtls/xray-core/proxy/trojan"
	"github.com/xtls/xray-core/proxy/vless"
)

// IncrementalApplier is an optional capability a RuntimeAdapter can
// implement: apply a desired-state change live, without the full
// Render+Apply(+restart) path. Agent.Sync tries this first whenever it has
// both the previously-applied and newly-desired state on hand; ok=false
// means "not confident this is safe to do live" (first sync ever, or a
// change bigger than a plain grant add/remove) and tells the caller to fall
// back to the existing, always-correct full-apply path instead.
type IncrementalApplier interface {
	ApplyIncremental(ctx context.Context, previous, next json.RawMessage) (ok bool, err error)
}

// grpcClient dials Xray's existing API listener — the "api" dokodemo-door
// inbound at 127.0.0.1:StatsAPIPort that already carries StatsService (see
// xray.go's Render) and now also HandlerService once the node is running
// with it enabled. A fresh short-lived connection per call is simpler than
// keeping one open across the agent's whole lifetime, and these calls are
// per-grant-change events, not hot-path traffic.
func (a XrayAdapter) grpcClient(ctx context.Context) (hcommand.HandlerServiceClient, func(), error) {
	if a.cfg.StatsAPIPort <= 0 {
		return nil, nil, fmt.Errorf("xray API port (WAVEBREAK_XRAY_STATS_API_PORT) is not configured")
	}
	target := fmt.Sprintf("127.0.0.1:%d", a.cfg.StatsAPIPort)
	conn, err := grpc.NewClient(target, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return nil, nil, fmt.Errorf("dial xray api: %w", err)
	}
	dialCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	conn.Connect()
	for {
		state := conn.GetState()
		if state.String() == "READY" {
			break
		}
		if !conn.WaitForStateChange(dialCtx, state) {
			_ = conn.Close()
			return nil, nil, fmt.Errorf("dial xray api at %s: timed out reaching %s", target, dialCtx.Err())
		}
	}
	return hcommand.NewHandlerServiceClient(conn), func() { _ = conn.Close() }, nil
}

// vlessInboundTags lists the tags of every VLESS-carrying inbound this node
// currently renders (see xray.go's Render) — every one of them needs the
// same client add/removed live, since they're all alternate transports to
// reach the same grant, not separate protocols.
func (a XrayAdapter) vlessInboundTags() []string {
	var tags []string
	if a.cfg.ListenPort > 0 {
		tags = append(tags, "vless-reality")
	}
	if a.cfg.CDNListenPort > 0 && strings.TrimSpace(a.cfg.CDNTLSCertPath) != "" && strings.TrimSpace(a.cfg.CDNTLSKeyPath) != "" {
		tags = append(tags, "vless-cdn-ws")
	}
	if a.cfg.CDNXHTTPListenPort > 0 && strings.TrimSpace(a.cfg.CDNTLSCertPath) != "" && strings.TrimSpace(a.cfg.CDNTLSKeyPath) != "" {
		tags = append(tags, "vless-cdn-xhttp")
	}
	if a.cfg.CDNGRPCListenPort > 0 && strings.TrimSpace(a.cfg.CDNTLSCertPath) != "" && strings.TrimSpace(a.cfg.CDNTLSKeyPath) != "" {
		tags = append(tags, "vless-cdn-grpc")
	}
	if a.cfg.DirectTLSListenPort > 0 && strings.TrimSpace(a.cfg.DirectTLSCertPath) != "" && strings.TrimSpace(a.cfg.DirectTLSKeyPath) != "" {
		tags = append(tags, "vless-direct-tls")
	}
	return tags
}

func (a XrayAdapter) trojanTag() string {
	if a.cfg.TrojanCDNListenPort > 0 && strings.TrimSpace(a.cfg.CDNTLSCertPath) != "" && strings.TrimSpace(a.cfg.CDNTLSKeyPath) != "" {
		return "trojan-cdn-ws"
	}
	return ""
}

func (a XrayAdapter) shadowsocksTag() string {
	if a.cfg.ShadowsocksPort > 0 {
		return "shadowsocks"
	}
	return ""
}

func shadowsocksCipherType(method string) shadowsocks.CipherType {
	switch strings.ToLower(strings.TrimSpace(method)) {
	case "aes-128-gcm":
		return shadowsocks.CipherType_AES_128_GCM
	case "chacha20-poly1305", "chacha20-ietf-poly1305":
		return shadowsocks.CipherType_CHACHA20_POLY1305
	case "xchacha20-poly1305", "xchacha20-ietf-poly1305":
		return shadowsocks.CipherType_XCHACHA20_POLY1305
	case "none", "plain":
		return shadowsocks.CipherType_NONE
	default:
		// aes-256-gcm is this project's configured default (see config.go)
		return shadowsocks.CipherType_AES_256_GCM
	}
}

func (a XrayAdapter) addVLESSUserToTag(ctx context.Context, client hcommand.HandlerServiceClient, tag, grantID, email string, withFlow bool) error {
	account := &vless.Account{Id: grantID}
	// Matches Render: only the raw-TCP REALITY inbound gets XTLS Vision
	// flow — the WS/XHTTP/gRPC/stream transports reject a flow-bearing
	// client outright.
	if withFlow && xrayFlowEnabled(a.cfg.Flow) {
		account.Flow = a.cfg.Flow
	}
	user := &protocol.User{Email: email, Level: 0, Account: serial.ToTypedMessage(account)}
	_, err := client.AlterInbound(ctx, &hcommand.AlterInboundRequest{
		Tag:       tag,
		Operation: serial.ToTypedMessage(&hcommand.AddUserOperation{User: user}),
	})
	return err
}

func (a XrayAdapter) addTrojanUser(ctx context.Context, client hcommand.HandlerServiceClient, tag, grantID, email string) error {
	user := &protocol.User{Email: email, Level: 0, Account: serial.ToTypedMessage(&trojan.Account{Password: grantID})}
	_, err := client.AlterInbound(ctx, &hcommand.AlterInboundRequest{
		Tag:       tag,
		Operation: serial.ToTypedMessage(&hcommand.AddUserOperation{User: user}),
	})
	return err
}

func (a XrayAdapter) addShadowsocksUser(ctx context.Context, client hcommand.HandlerServiceClient, tag, grantID, email string) error {
	account := &shadowsocks.Account{Password: grantID, CipherType: shadowsocksCipherType(a.cfg.ShadowsocksMethod)}
	user := &protocol.User{Email: email, Level: 0, Account: serial.ToTypedMessage(account)}
	_, err := client.AlterInbound(ctx, &hcommand.AlterInboundRequest{
		Tag:       tag,
		Operation: serial.ToTypedMessage(&hcommand.AddUserOperation{User: user}),
	})
	return err
}

func (a XrayAdapter) removeUserFromTag(ctx context.Context, client hcommand.HandlerServiceClient, tag, email string) error {
	_, err := client.AlterInbound(ctx, &hcommand.AlterInboundRequest{
		Tag:       tag,
		Operation: serial.ToTypedMessage(&hcommand.RemoveUserOperation{Email: email}),
	})
	return err
}

// grantEmail reproduces the exact label Render/Core both already use
// ("WVB-XXXXXXXX", first 8 hex chars of the grant id, uppercased) so a live
// add/remove targets the same client identity Render would have written.
func grantEmail(g xrayGrant) string {
	email := strings.TrimSpace(g.Label)
	if email != "" {
		return email
	}
	id := strings.ReplaceAll(g.ID, "-", "")
	if len(id) > 8 {
		id = id[:8]
	}
	return "WVB-" + strings.ToUpper(id)
}

// grantActivation is whether a grant is the kind Render actually turns into
// a live client at all — see Render's own filter (isVLESSProtocol && status
// == "active"). A grant that never made it into any transport's client list
// obviously needs no live add/remove either.
func grantActivation(g xrayGrant) bool {
	return isVLESSProtocol(g.Protocol) && g.Status == "active"
}

// ApplyIncremental implements IncrementalApplier. It diffs the grant list
// between the previously-applied and newly-desired state; if every
// difference is a plain activation flip (a grant newly went active, or an
// active grant left/expired/was revoked) it adds/removes exactly those
// clients live via Xray's HandlerService gRPC API and only regenerates +
// restarts the separate Hysteria2 sidecar (which has no live API of its
// own) — Xray itself is never restarted, so no other connected client is
// touched. Anything it isn't fully sure about (first sync, a grant's
// protocol changing while staying active, or HandlerService unreachable)
// returns ok=false so the caller falls back to the full, always-correct
// Render+Apply(+restart) path instead of risking a broken partial state.
func (a XrayAdapter) ApplyIncremental(ctx context.Context, previous, next json.RawMessage) (bool, error) {
	if len(previous) == 0 {
		return false, nil
	}
	var prevState, nextState xrayDesiredState
	if err := json.Unmarshal(previous, &prevState); err != nil {
		return false, nil
	}
	if err := json.Unmarshal(next, &nextState); err != nil {
		return false, nil
	}

	prevByID := make(map[string]xrayGrant, len(prevState.Grants))
	for _, g := range prevState.Grants {
		prevByID[g.ID] = g
	}
	nextByID := make(map[string]xrayGrant, len(nextState.Grants))
	for _, g := range nextState.Grants {
		nextByID[g.ID] = g
	}

	type flip struct {
		grant     xrayGrant
		activated bool // true = newly active (add), false = no longer active (remove)
	}
	var flips []flip
	for id, g := range nextByID {
		prev, existed := prevByID[id]
		wasActive := existed && grantActivation(prev)
		nowActive := grantActivation(g)
		if existed && wasActive && nowActive && prev.Protocol != g.Protocol {
			// Stayed "active" but changed protocol underneath — outside
			// what this minimal diff understands; let the full path handle it.
			return false, nil
		}
		if !wasActive && nowActive {
			flips = append(flips, flip{grant: g, activated: true})
		} else if wasActive && !nowActive {
			flips = append(flips, flip{grant: g, activated: false})
		}
	}
	for id, g := range prevByID {
		if _, stillPresent := nextByID[id]; !stillPresent && grantActivation(g) {
			flips = append(flips, flip{grant: g, activated: false})
		}
	}
	if len(flips) == 0 {
		return true, nil // nothing that changes any live client; no-op is a valid "handled".
	}

	client, closeConn, err := a.grpcClient(ctx)
	if err != nil {
		return false, nil // treat "can't reach HandlerService" as "fall back", not a hard error
	}
	defer closeConn()

	vlessTags := a.vlessInboundTags()
	trojanTag := a.trojanTag()
	ssTag := a.shadowsocksTag()

	for _, f := range flips {
		email := grantEmail(f.grant)
		if f.activated {
			for _, tag := range vlessTags {
				if err := a.addVLESSUserToTag(ctx, client, tag, f.grant.ID, email, tag == "vless-reality"); err != nil {
					return false, fmt.Errorf("live add user on %s: %w", tag, err)
				}
			}
			if trojanTag != "" {
				if err := a.addTrojanUser(ctx, client, trojanTag, f.grant.ID, email); err != nil {
					return false, fmt.Errorf("live add trojan user: %w", err)
				}
			}
			if ssTag != "" {
				if err := a.addShadowsocksUser(ctx, client, ssTag, f.grant.ID, email); err != nil {
					return false, fmt.Errorf("live add shadowsocks user: %w", err)
				}
			}
		} else {
			for _, tag := range vlessTags {
				if err := a.removeUserFromTag(ctx, client, tag, email); err != nil {
					return false, fmt.Errorf("live remove user on %s: %w", tag, err)
				}
			}
			if trojanTag != "" {
				if err := a.removeUserFromTag(ctx, client, trojanTag, email); err != nil {
					return false, fmt.Errorf("live remove trojan user: %w", err)
				}
			}
			if ssTag != "" {
				if err := a.removeUserFromTag(ctx, client, ssTag, email); err != nil {
					return false, fmt.Errorf("live remove shadowsocks user: %w", err)
				}
			}
		}
	}

	// Xray is now live-consistent with `next`. Re-render so both the
	// on-disk config file (crash/restart recovery) and the Hysteria2
	// sidecar's user list (which has no live API) stay in sync too.
	// Restarting Hysteria2 only drops Hysteria2-connected clients — never
	// the Xray ones this whole path exists to protect.
	rendered, err := a.Render(ctx, next)
	if err != nil {
		return false, fmt.Errorf("re-render after live apply: %w", err)
	}
	if err := a.writeXrayConfigFile(rendered); err != nil {
		return false, fmt.Errorf("persist xray config after live apply: %w", err)
	}
	if err := a.applyHysteria(ctx); err != nil {
		return false, fmt.Errorf("apply hysteria2 sidecar after live apply: %w", err)
	}
	return true, nil
}
