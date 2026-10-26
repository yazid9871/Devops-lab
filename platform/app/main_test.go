package main

import (
	"net/http/httptest"
	"testing"
)

func TestLivenessDoesNotRequireDatabase(t *testing.T) {
	s := &server{}
	w := httptest.NewRecorder()
	s.handleHealthz(w, httptest.NewRequest("GET", "/healthz", nil))
	if w.Code != 200 {
		t.Fatalf("liveness status = %d", w.Code)
	}
}

func TestReadinessBlocksTrafficBeforeStartup(t *testing.T) {
	s := &server{}
	w := httptest.NewRecorder()
	s.handleReadyz(w, httptest.NewRequest("GET", "/readyz", nil))
	if w.Code != 503 {
		t.Fatalf("unready status = %d", w.Code)
	}
}

func TestUnknownPathsDoNotCreateUnboundedMetricLabels(t *testing.T) {
	for _, path := range []string{"/unknown/a", "/unknown/b", "/random/123"} {
		if got := normalizePath(path); got != "unmatched" {
			t.Fatalf("normalizePath(%q) = %q", path, got)
		}
	}
}
