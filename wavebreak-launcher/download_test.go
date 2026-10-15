package main

import (
	"bytes"
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"
)

// The connection drops halfway: the download resumes from there (Range)
// and the file is whole.
func TestDownloadResumesAfterADrop(t *testing.T) {
	payload := bytes.Repeat([]byte("wavebreak"), 300_000) // 2.7 MB
	var calls atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if calls.Add(1) == 1 {
			w.Header().Set("Content-Length", "2700000")
			w.WriteHeader(http.StatusOK)
			w.Write(payload[:1_000_000])
			hj, _ := w.(http.Hijacker)
			conn, _, _ := hj.Hijack()
			conn.Close()
			return
		}
		http.ServeContent(w, r, "x.exe", time.Time{}, bytes.NewReader(payload))
	}))
	defer srv.Close()

	l := launcherFor(System{}, nil, nil)
	file := filepath.Join(t.TempDir(), "x.exe")
	if err := l.download(context.Background(), "x", srv.URL+"/x.exe", file); err != nil {
		t.Fatal(err)
	}
	got, _ := os.ReadFile(file)
	if !bytes.Equal(got, payload) {
		t.Fatalf("got %d bytes, want %d", len(got), len(payload))
	}
	if calls.Load() != 2 {
		t.Fatalf("%d requests, want 2 (one resume)", calls.Load())
	}
}
