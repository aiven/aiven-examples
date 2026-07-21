// Command live-orders is a long-running worker that continuously writes mock
// ecommerce orders into a PostgreSQL table at a configurable rate, until it is
// shut down. It is the "live" data source for the aiven-trino-iceberg-agent
// demo: orders land in Postgres, are captured by a Debezium CDC source
// connector into Kafka, flow through the Kafka Connect Iceberg sink into
// Iceberg-on-S3, and are then queryable through Trino.
//
// Besides INSERTing new orders (always status PENDING), it also UPDATEs
// existing orders through a realistic status lifecycle
// (PENDING → PAID → SHIPPED → DELIVERED, with occasional CANCELLED), so the
// CDC stream carries genuine update events, not just inserts.
//
// Configuration (environment variables):
//
//	POSTGRES_URI       - Aiven for PostgreSQL service URI from the Aiven Console
//	                     (Service > Connection information), e.g.
//	                     postgres://avnadmin:pass@host:port/defaultdb?sslmode=require
//	ORDERS_PER_MINUTE  - target INSERT rate (optional, default 100)
//	UPDATES_PER_MINUTE - target status-UPDATE rate (optional, default 60)
//	PORT               - health-server port (optional, default 8080); serves
//	                     /healthz (liveness) and /readyz (ready once connected)
package main

import (
	"context"
	"database/sql"
	"errors"
	"log"
	"math/rand"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"sync/atomic"
	"syscall"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
)

func mustGetenv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("Required environment variable %s is not set", key)
	}
	return v
}

// getenvDefault returns the value of key, or def if unset/empty.
func getenvDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

// getenvRate reads a positive-integer per-minute rate from the environment.
func getenvRate(key string, def int) int {
	v := os.Getenv(key)
	if v == "" {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil || n <= 0 {
		log.Fatalf("%s must be a positive integer, got %q", key, v)
	}
	return n
}

// Order represents an ecommerce order placed by a customer. Column names in
// Postgres are snake_case (order_id, customer_id, ...) — Debezium propagates
// them as-is into the Kafka record and the auto-created Iceberg table.
type Order struct {
	CustomerID int
	Product    string
	Quantity   int
	Amount     float64
	Status     string // PENDING, PAID, SHIPPED, DELIVERED, CANCELLED
}

var products = []string{"Laptop", "Headphones", "Keyboard", "Monitor", "Webcam", "Mouse", "Desk Chair", "USB-C Cable"}

// nextStatus maps a non-terminal status to its natural successor.
// DELIVERED and CANCELLED are terminal.
var nextStatus = map[string]string{
	"PENDING": "PAID",
	"PAID":    "SHIPPED",
	"SHIPPED": "DELIVERED",
}

// cancelProbability is the chance a PENDING or PAID order gets CANCELLED
// instead of advancing to its next status.
const cancelProbability = 0.1

// schemaDDL creates the orders table if it doesn't exist. amount is double
// precision (not numeric) so Debezium's JSON output stays a plain number, and
// order_id is an identity column so IDs survive producer restarts. The same
// DDL lives in sql/init.sql for manual setup.
const schemaDDL = `
CREATE TABLE IF NOT EXISTS public.orders (
    order_id    integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id integer          NOT NULL,
    product     text             NOT NULL,
    quantity    integer          NOT NULL,
    amount      double precision NOT NULL,
    status      text             NOT NULL,
    order_date  timestamptz      NOT NULL DEFAULT now(),
    updated_at  timestamptz      NOT NULL DEFAULT now()
)`

// intervalFor returns the delay between operations needed to hit a target rate.
func intervalFor(perMinute int) time.Duration {
	return time.Minute / time.Duration(perMinute)
}

// startHealthServer runs a minimal HTTP server so the platform (Aiven Apps) has a
// port to health-check — this is otherwise a headless worker with no inbound
// surface. /healthz is liveness (always 200 once the process is up); /readyz
// returns 200 only after the Postgres connection is established.
func startHealthServer(addr string, ready *atomic.Bool) {
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	mux.HandleFunc("/readyz", func(w http.ResponseWriter, _ *http.Request) {
		if ready.Load() {
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte("ready"))
			return
		}
		http.Error(w, "connecting to postgres", http.StatusServiceUnavailable)
	})
	// A bare GET / also succeeds, so the simplest HTTP health check passes.
	mux.HandleFunc("/", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("live-orders"))
	})
	srv := &http.Server{Addr: addr, Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	go func() {
		log.Printf("Health server listening on %s (/healthz, /readyz)", addr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Printf("Health server error: %v", err)
		}
	}()
}

// generateOrder builds a single mock order. New orders always start PENDING;
// later status changes happen via UPDATEs so they show up as CDC update events.
func generateOrder(rng *rand.Rand) Order {
	quantity := rng.Intn(5) + 1
	unitPrice := float64(5+rng.Intn(495)) + rng.Float64()

	return Order{
		CustomerID: rng.Intn(1000) + 1,
		Product:    products[rng.Intn(len(products))],
		Quantity:   quantity,
		Amount:     float64(quantity) * unitPrice,
		Status:     "PENDING",
	}
}

// insertOrder writes a new order row and returns its generated order_id.
// order_date/updated_at default to now() in the database.
func insertOrder(ctx context.Context, db *sql.DB, o Order) (int, error) {
	var id int
	err := db.QueryRowContext(ctx,
		`INSERT INTO public.orders (customer_id, product, quantity, amount, status)
		 VALUES ($1, $2, $3, $4, $5) RETURNING order_id`,
		o.CustomerID, o.Product, o.Quantity, o.Amount, o.Status).Scan(&id)
	return id, err
}

// pickTransition decides the new status for an order currently in cur.
// Returns "" for terminal statuses.
func pickTransition(rng *rand.Rand, cur string) string {
	next, ok := nextStatus[cur]
	if !ok {
		return ""
	}
	if (cur == "PENDING" || cur == "PAID") && rng.Float64() < cancelProbability {
		return "CANCELLED"
	}
	return next
}

// advanceRandomOrder picks a random non-terminal order among the 100 most
// recent and advances its status one step (or cancels it). Returns the updated
// order_id and the transition, or ok=false if no eligible order exists.
func advanceRandomOrder(ctx context.Context, db *sql.DB, rng *rand.Rand) (id int, from, to string, ok bool, err error) {
	// Sample inside the DB so we don't track order state in the app: grab one
	// random non-terminal order from the recent window, then update it.
	err = db.QueryRowContext(ctx,
		`SELECT order_id, status FROM (
		     SELECT order_id, status FROM public.orders
		     WHERE status IN ('PENDING', 'PAID', 'SHIPPED')
		     ORDER BY order_id DESC LIMIT 100
		 ) recent ORDER BY random() LIMIT 1`).Scan(&id, &from)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, "", "", false, nil
	}
	if err != nil {
		return 0, "", "", false, err
	}

	to = pickTransition(rng, from)
	if to == "" {
		return 0, "", "", false, nil // raced with another update; skip this tick
	}
	_, err = db.ExecContext(ctx,
		`UPDATE public.orders SET status = $1, updated_at = now() WHERE order_id = $2`,
		to, id)
	if err != nil {
		return 0, "", "", false, err
	}
	return id, from, to, true, nil
}

func main() {
	log.Println("Starting live-orders Postgres writer...")

	// Bring up the health port first, so the platform sees a listening socket
	// even while we connect to Postgres. PORT defaults to 8080 (Aiven Apps default).
	healthAddr := ":" + getenvDefault("PORT", "8080")
	var ready atomic.Bool
	startHealthServer(healthAddr, &ready)

	postgresURI := mustGetenv("POSTGRES_URI")
	ordersPerMinute := getenvRate("ORDERS_PER_MINUTE", 100)
	updatesPerMinute := getenvRate("UPDATES_PER_MINUTE", 60)

	insertInterval := intervalFor(ordersPerMinute)
	updateInterval := intervalFor(updatesPerMinute)
	log.Printf("Config: %d inserts/min (1 every %s), %d updates/min (1 every %s)",
		ordersPerMinute, insertInterval, updatesPerMinute, updateInterval)

	db, err := sql.Open("pgx", postgresURI)
	if err != nil {
		log.Fatalf("Failed to open Postgres connection: %v", err)
	}
	defer db.Close()
	// One insert + one update in flight at most; keep the pool tiny.
	db.SetMaxOpenConns(4)

	// Cancel the loop on SIGINT/SIGTERM so Aiven Apps can stop us cleanly.
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	if err := db.PingContext(ctx); err != nil {
		log.Fatalf("Failed to connect to Postgres: %v", err)
	}
	if _, err := db.ExecContext(ctx, schemaDDL); err != nil {
		log.Fatalf("Failed to ensure orders table exists: %v", err)
	}
	ready.Store(true) // connected + table ensured — /readyz now returns 200
	log.Println("Connected to Postgres; public.orders table ready.")

	rng := rand.New(rand.NewSource(time.Now().UnixNano()))
	insertTicker := time.NewTicker(insertInterval)
	defer insertTicker.Stop()
	updateTicker := time.NewTicker(updateInterval)
	defer updateTicker.Stop()

	var inserted, updated int
	log.Println("Streaming live orders. Press Ctrl-C (or send SIGTERM) to stop.")

	for {
		select {
		case <-ctx.Done():
			log.Printf("Shutdown signal received. Inserted %d orders, updated %d. Closing...", inserted, updated)
			return
		case <-insertTicker.C:
			order := generateOrder(rng)
			id, err := insertOrder(ctx, db, order)
			if err != nil {
				// Log and keep going — a transient hiccup shouldn't kill
				// a long-running worker.
				if ctx.Err() == nil {
					log.Printf("Failed to insert order: %v", err)
				}
				continue
			}
			inserted++
			if inserted%50 == 0 {
				log.Printf("Inserted %d orders (latest: order %d, %s x%d)", inserted, id, order.Product, order.Quantity)
			}
		case <-updateTicker.C:
			id, from, to, ok, err := advanceRandomOrder(ctx, db, rng)
			if err != nil {
				if ctx.Err() == nil {
					log.Printf("Failed to update an order: %v", err)
				}
				continue
			}
			if !ok {
				continue // nothing eligible yet
			}
			updated++
			if updated%50 == 0 {
				log.Printf("Updated %d orders (latest: order %d %s → %s)", updated, id, from, to)
			}
		}
	}
}
