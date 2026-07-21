package main

import (
	"math/rand"
	"testing"
	"time"
)

func TestIntervalFor(t *testing.T) {
	cases := map[int]time.Duration{
		60:  time.Second,
		100: 600 * time.Millisecond,
		1:   time.Minute,
		120: 500 * time.Millisecond,
	}
	for rate, want := range cases {
		if got := intervalFor(rate); got != want {
			t.Errorf("intervalFor(%d) = %s, want %s", rate, got, want)
		}
	}
}

func TestGetenvDefault(t *testing.T) {
	const key = "LIVE_ORDERS_TEST_VAR"
	if got := getenvDefault(key, "fallback"); got != "fallback" {
		t.Errorf("unset: got %q, want %q", got, "fallback")
	}
	t.Setenv(key, "value")
	if got := getenvDefault(key, "fallback"); got != "value" {
		t.Errorf("set: got %q, want %q", got, "value")
	}
}

func TestGenerateOrder(t *testing.T) {
	rng := rand.New(rand.NewSource(42))

	for i := 0; i < 200; i++ {
		o := generateOrder(rng)

		if o.Status != "PENDING" {
			t.Errorf("Status = %q, want PENDING (new orders always start pending)", o.Status)
		}
		if o.Quantity < 1 || o.Quantity > 5 {
			t.Errorf("Quantity = %d, want 1..5", o.Quantity)
		}
		if o.CustomerID < 1 || o.CustomerID > 1000 {
			t.Errorf("CustomerID = %d, want 1..1000", o.CustomerID)
		}
		if o.Amount <= 0 {
			t.Errorf("Amount = %f, want > 0", o.Amount)
		}
		if o.Product == "" {
			t.Error("Product is empty")
		}
	}
}

func TestPickTransition(t *testing.T) {
	rng := rand.New(rand.NewSource(7))

	// Terminal statuses never transition.
	for _, terminal := range []string{"DELIVERED", "CANCELLED"} {
		if got := pickTransition(rng, terminal); got != "" {
			t.Errorf("pickTransition(%q) = %q, want \"\"", terminal, got)
		}
	}

	// Non-terminal statuses always land on the natural successor or CANCELLED
	// (SHIPPED can only advance to DELIVERED — no cancellation after shipping).
	allowed := map[string]map[string]bool{
		"PENDING": {"PAID": true, "CANCELLED": true},
		"PAID":    {"SHIPPED": true, "CANCELLED": true},
		"SHIPPED": {"DELIVERED": true},
	}
	seen := map[string]map[string]bool{}
	for from := range allowed {
		seen[from] = map[string]bool{}
		for i := 0; i < 500; i++ {
			to := pickTransition(rng, from)
			if !allowed[from][to] {
				t.Fatalf("pickTransition(%q) = %q, not an allowed transition", from, to)
			}
			seen[from][to] = true
		}
	}
	// With 500 samples and a 10% cancel rate, both outcomes should occur.
	if !seen["PENDING"]["CANCELLED"] || !seen["PENDING"]["PAID"] {
		t.Errorf("PENDING transitions seen = %v, want both PAID and CANCELLED", seen["PENDING"])
	}
}
