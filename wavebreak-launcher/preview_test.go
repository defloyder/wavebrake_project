//go:build windows

package main

import (
	"os"
	"strings"
	"testing"
)

// WB_PREVIEW=<file>: writes the page with sample data, to look at in a
// browser (no WebView, no bindings).
func TestWritePreview(t *testing.T) {
	out := os.Getenv("WB_PREVIEW")
	if out == "" {
		t.Skip("set WB_PREVIEW")
	}
	mock := `<script>
window.wbState=async()=>({system:{name:"Windows 11",arch:"x64",build:26100},products:[
{id:"wavebreak",name:"WAVEBREAK",tagline:"Полная версия для 64-битной Windows 10 и 11",kind:"app",arch:["x64","arm64"],features:` + js(catalog[0].Features) + `,status:"update",installed:"1.0.14",latest:"1.0.15",compatible:true,recommended:true},
{id:"wavebreak-lite",name:"WAVEBREAK Lite",tagline:"Лёгкая версия: 32-битная Windows и слабые ПК",kind:"app",arch:["x86","x64","arm64"],features:` + js(catalog[1].Features) + `,status:"soon",compatible:true},
{id:"android",name:"Телефон и ТВ",tagline:"Android, Android TV, Google TV, Fire TV",kind:"link",features:` + js(catalog[2].Features) + `,status:"link",compatible:true}]});
window.wbSelf=async()=>({version:"1.1.0",available:"1.1.1"});
window.wbSelfUpdate=()=>{};
window.wbNet=async()=>[{name:"Сайт",ms:124},{name:"Аккаунт",ms:188},{name:"Аккаунт, запасной путь",ms:612},{name:"Загрузки",ms:-1}];
</script>`
	html := strings.Replace(withAssets(page), "<script>", mock+"<script>", 1)
	if err := os.WriteFile(out, []byte(html), 0o644); err != nil {
		t.Fatal(err)
	}
}

func js(list []string) string {
	return `["` + strings.Join(list, `","`) + `"]`
}
