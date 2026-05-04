// {{ .Name }} — Go worker scaffolded by rda.
// No HTTP server, no Service, no Ingress. Processes work from a
// queue/topic/schedule and exits on signal.
package main

import (
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	fmt.Printf("%s worker starting\n", "{{ .Name }}")

	// Discover bindings from env vars
	for _, prefix := range []string{"DB", "CACHE", "EVENTS", "QUEUE"} {
		if host := os.Getenv(prefix + "_HOST"); host != "" {
			fmt.Printf("  binding %s: host=%s port=%s\n",
				prefix, host, os.Getenv(prefix+"_PORT"))
		}
	}

	// Heartbeat loop — replace with real queue consumer logic
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	tick := time.NewTicker(10 * time.Second)
	defer tick.Stop()

	for {
		select {
		case <-tick.C:
			fmt.Printf("[%s] heartbeat\n", time.Now().Format(time.RFC3339))
		case s := <-sig:
			fmt.Printf("received %s, shutting down\n", s)
			return
		}
	}
}
