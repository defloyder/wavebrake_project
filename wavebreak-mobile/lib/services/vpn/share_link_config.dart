// The share-link parser and Xray config generator now live in the shared
// wavebreak_links package (wavebreak-shared/wavebreak_links), used by both
// the mobile and desktop clients. This file keeps the old import path.
export 'package:wavebreak_links/wavebreak_links.dart'
    show
        V2RayURL,
        VlessURL,
        VmessURL,
        TrojanURL,
        ShadowSocksURL,
        SocksURL,
        Hysteria2URL,
        WireguardURL,
        parseShareLink,
        applySmartRoutingPolicy;
