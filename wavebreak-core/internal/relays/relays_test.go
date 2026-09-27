package relays

import (
	"context"
	"errors"
	"testing"
)

func TestParse(t *testing.T) {
	got, err := Parse(" Moscow=135.106.227.90 , Moscow-2=5.188.1.2:8443,")
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || got[0] != (Relay{Name: "Moscow", Host: "135.106.227.90", Port: 443}) || got[1] != (Relay{Name: "Moscow-2", Host: "5.188.1.2", Port: 8443}) {
		t.Fatalf("parse: %+v", got)
	}
	if empty, err := Parse(""); err != nil || len(empty) != 0 {
		t.Fatalf("empty: %v %v", empty, err)
	}
	for _, bad := range []string{"no-equals", "=1.2.3.4", "X=1.2.3.4:0", "X=1.2.3.4:abc"} {
		if _, err := Parse(bad); err == nil {
			t.Fatalf("%q must fail", bad)
		}
	}
}

func TestHealthTracking(t *testing.T) {
	up := map[string]bool{"1.1.1.1:443": true, "2.2.2.2:443": true}
	dial := func(_ context.Context, address string) error {
		if up[address] {
			return nil
		}
		return errors.New("refused")
	}
	reg := NewRegistry([]Relay{{Name: "A", Host: "1.1.1.1", Port: 443}, {Name: "B", Host: "2.2.2.2", Port: 443}}, dial, 0)

	if len(reg.Healthy()) != 2 {
		t.Fatal("relays count as up before the first check")
	}
	up["2.2.2.2:443"] = false
	reg.CheckOnce(context.Background())
	if len(reg.Healthy()) != 2 {
		t.Fatal("one failed probe must not drop a relay")
	}
	reg.CheckOnce(context.Background())
	if h := reg.Healthy(); len(h) != 1 || h[0].Name != "A" {
		t.Fatalf("B must be dropped after two failures: %+v", h)
	}
	up["2.2.2.2:443"] = true
	reg.CheckOnce(context.Background())
	if len(reg.Healthy()) != 2 {
		t.Fatal("one success brings a relay back")
	}
	var nilReg *Registry
	if nilReg.Healthy() != nil {
		t.Fatal("nil registry has no relays")
	}
}
