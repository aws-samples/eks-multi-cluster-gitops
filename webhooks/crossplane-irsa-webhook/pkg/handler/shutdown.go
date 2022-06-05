package handler

import (
	"context"
	"net/http"
	"time"

	"k8s.io/klog"
)

func ShutdownFromContext(ctx context.Context, server *http.Server, timeout time.Duration) {
	go func() {
		<-ctx.Done()

		shutdownCtx, cancel := context.WithTimeout(context.Background(), timeout)
		defer cancel()

		if err := server.Shutdown(shutdownCtx); err != nil {
			klog.Errorf("Error shutting server down: %v", err)
			if err := server.Close(); err != nil {
				klog.Fatalf("Error closing server: %v", err)
			}
		}
	}()
}
