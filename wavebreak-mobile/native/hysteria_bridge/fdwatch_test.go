package bridge

import (
	"strings"
	"testing"
)

func TestFdKind(t *testing.T) {
	for target, want := range map[string]string{
		"socket:[123456]":           "socket",
		"pipe:[42]":                 "pipe",
		"anon_inode:[eventpoll]":    "epoll",
		"anon_inode:[eventfd]":      "anon",
		"/dev/tun":                  "dev",
		"/dev/null":                 "dev",
		"/data/app/base.apk":        "file",
		"/data/user/0/x/engine.log": "file",
	} {
		if got := fdKind(target); got != want {
			t.Errorf("fdKind(%q) = %q, want %q", target, got, want)
		}
	}
}

func TestFormatKindsLargestFirst(t *testing.T) {
	got := formatKinds(map[string]int{"file": 78, "socket": 3900, "pipe": 6, "anon": 6})
	if got != "socket=3900 file=78 anon=6 pipe=6" {
		t.Fatalf("got %q", got)
	}
}

func TestFdBreakdownReadsOwnProcess(t *testing.T) {
	got := FdBreakdown()
	// /proc exists on Linux and Android; elsewhere it says it can't read.
	if !strings.HasPrefix(got, "fds=") && !strings.HasPrefix(got, "fds unreadable") {
		t.Fatalf("unexpected %q", got)
	}
	if strings.HasPrefix(got, "fds=") && !strings.Contains(got, "· flows tcp=") {
		t.Fatalf("no flow counts in %q", got)
	}
}
