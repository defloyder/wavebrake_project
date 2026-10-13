package main

import (
	"embed"
	"encoding/base64"
	"strings"
)

// The brand mark and the app's own fonts, built into the exe (owner,
// 13.10: the drawn logo was crooked and the wordmark in the system font).
// The page is loaded from a string, so they go in as data: URLs.
//
//go:embed assets/mark.png assets/michroma.ttf assets/noto-serif.ttf assets/inter-400.ttf assets/inter-600.ttf
var assetFS embed.FS

func dataURL(name, mime string) string {
	b, err := assetFS.ReadFile("assets/" + name)
	if err != nil {
		return ""
	}
	return "data:" + mime + ";base64," + base64.StdEncoding.EncodeToString(b)
}

// withAssets fills the page's {{…}} placeholders.
func withAssets(page string) string {
	return strings.NewReplacer(
		"{{MARK}}", dataURL("mark.png", "image/png"),
		"{{MICHROMA}}", dataURL("michroma.ttf", "font/ttf"),
		"{{SERIF}}", dataURL("noto-serif.ttf", "font/ttf"),
		"{{INTER400}}", dataURL("inter-400.ttf", "font/ttf"),
		"{{INTER600}}", dataURL("inter-600.ttf", "font/ttf"),
	).Replace(page)
}
