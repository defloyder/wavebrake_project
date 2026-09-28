package httpapi

import (
	"context"
	"encoding/json"
	"time"

	"wavebreak-core/internal/config"
	"wavebreak-core/internal/store"
)

// A second location (e.g. Moscow) serves the same accounts as the primary
// node: its agent gets the primary's grants (store.refreshNodeDesiredStateTx),
// and the user gets a second set of links built from the mirror's own
// public_config. See migration 00006.

// mirrorFreshness: a mirror whose agent hasn't checked in for this long
// isn't offered (its links would just fail).
const mirrorFreshness = 5 * time.Minute

// mirrorVLESS: the mirror's connection settings. Only what public_config
// sets — nothing is inherited from the primary's host-specific settings
// (CDN, relays, XHTTP SNI ...), which would produce links to the primary
// under the mirror's name. Client-style defaults are kept.
func mirrorVLESS(primary config.VLESSConfig, publicConfig json.RawMessage) (config.VLESSConfig, bool) {
	v := config.VLESSConfig{Fingerprint: primary.Fingerprint, Flow: primary.Flow}
	if len(publicConfig) == 0 {
		return v, false
	}
	if err := json.Unmarshal(publicConfig, &v); err != nil {
		return v, false
	}
	return v, v.PublicHost != "" && v.RealityPublicKey != "" && v.RealityShortID != ""
}

func mirrorUsable(n store.Node, now time.Time) bool {
	return n.Status == "online" && n.LastHeartbeatAt != nil && now.Sub(*n.LastHeartbeatAt) < mirrorFreshness
}

// mirrorConfigs: the same grant at every usable mirror of its node.
func (s *Server) mirrorConfigs(ctx context.Context, primary store.AccessGrantConfig) []store.AccessGrantConfig {
	mirrors, err := s.app.Store.MirrorNodesOf(ctx, primary.Node.ID)
	if err != nil {
		s.warn(ctx, "load mirror nodes", "error", err)
		return nil
	}
	now := time.Now()
	var out []store.AccessGrantConfig
	for _, m := range mirrors {
		if !mirrorUsable(m.Node, now) {
			continue
		}
		vless, ok := mirrorVLESS(s.app.Config.VLESS, m.PublicConfig)
		if !ok {
			continue
		}
		cfg := store.AccessGrantConfig{Grant: primary.Grant, Node: m.Node}
		s.applyVLESSRuntimeConfigFor(&cfg, vless, false)
		out = append(out, cfg)
	}
	return out
}
