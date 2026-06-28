package main

import (
	"encoding/json"
	"math/rand"
	"testing"
	"time"

	"github.com/IBM/sarama"
	"github.com/IBM/sarama/mocks"
)

func TestIntervalFor(t *testing.T) {
	cases := map[int]time.Duration{
		60:   time.Second,
		100:  600 * time.Millisecond,
		1:    time.Minute,
		120:  500 * time.Millisecond,
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
	validStatus := map[string]bool{"PENDING": true, "PAID": true, "SHIPPED": true, "DELIVERED": true, "CANCELLED": true}

	for i := 1; i <= 200; i++ {
		o := generateOrder(rng, i)

		if o.OrderID != i {
			t.Fatalf("OrderID = %d, want %d", o.OrderID, i)
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
		if !validStatus[o.Status] {
			t.Errorf("Status = %q, not a valid status", o.Status)
		}
		if o.Product == "" {
			t.Error("Product is empty")
		}
		ts, err := time.Parse(time.RFC3339, o.OrderDate)
		if err != nil {
			t.Errorf("OrderDate %q not RFC3339: %v", o.OrderDate, err)
		} else if d := time.Since(ts); d < -time.Minute || d > time.Minute {
			t.Errorf("OrderDate %q is not ~now (delta %s)", o.OrderDate, d)
		}
	}
}

func TestNewOrderMessage(t *testing.T) {
	order := Order{OrderID: 7, CustomerID: 42, Product: "Laptop", Quantity: 2, Amount: 199.5, Status: "PAID", OrderDate: "2026-06-28T00:00:00Z"}

	msg, err := newOrderMessage("order", order)
	if err != nil {
		t.Fatalf("newOrderMessage error: %v", err)
	}
	if msg.Topic != "order" {
		t.Errorf("Topic = %q, want %q", msg.Topic, "order")
	}

	valBytes, err := msg.Value.Encode()
	if err != nil {
		t.Fatalf("encode value: %v", err)
	}
	var got Order
	if err := json.Unmarshal(valBytes, &got); err != nil {
		t.Fatalf("value is not valid Order JSON: %v", err)
	}
	if got != order {
		t.Errorf("round-tripped order = %+v, want %+v", got, order)
	}

	keyBytes, err := msg.Key.Encode()
	if err != nil {
		t.Fatalf("encode key: %v", err)
	}
	var key OrderKey
	if err := json.Unmarshal(keyBytes, &key); err != nil {
		t.Fatalf("key is not valid OrderKey JSON: %v", err)
	}
	if key.KeyId != 70 || key.KeyCode != "O7" {
		t.Errorf("key = %+v, want {KeyId:70 KeyCode:O7}", key)
	}
}

// TestProduceWithMockBroker verifies the produce path against a mock SyncProducer
// (no real Kafka) — the message reaches the producer with a JSON-decodable Order.
func TestProduceWithMockBroker(t *testing.T) {
	config := sarama.NewConfig()
	config.Producer.Return.Successes = true

	producer := mocks.NewSyncProducer(t, config)
	defer func() {
		if err := producer.Close(); err != nil {
			t.Errorf("close: %v", err)
		}
	}()

	producer.ExpectSendMessageWithCheckerFunctionAndSucceed(func(val []byte) error {
		var o Order
		return json.Unmarshal(val, &o) // non-nil error fails the expectation
	})

	order := generateOrder(rand.New(rand.NewSource(1)), 1)
	msg, err := newOrderMessage("order", order)
	if err != nil {
		t.Fatalf("newOrderMessage error: %v", err)
	}

	if _, _, err := producer.SendMessage(msg); err != nil {
		t.Fatalf("SendMessage error: %v", err)
	}
}
