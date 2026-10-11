package main

import (
	"context"
	"flag"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"time"
)

func main() {
	noBrowser := flag.Bool("no-browser", false, "Only print the game address")
	flag.Parse()
	executable, err := os.Executable()
	if err != nil {
		fail(err)
	}
	root := filepath.Dir(executable)
	if info, err := os.Stat(filepath.Join(root, "index.html")); err != nil || !info.Mode().IsRegular() {
		fail(fmt.Errorf("Распакуйте весь Web-архив: index.html должен находиться рядом с программой запуска"))
	}
	address := "127.0.0.1:18765"
	listener, err := net.Listen("tcp4", address)
	if err != nil {
		fail(fmt.Errorf("Адрес занят. Закройте предыдущее окно запуска игры и попробуйте снова: %w", err))
	}
	allowed := map[string]bool{"index.html": true}
	entries, err := os.ReadDir(root)
	if err != nil {
		fail(err)
	}
	for _, entry := range entries {
		name := entry.Name()
		if entry.Type().IsRegular() && strings.HasPrefix(name, "index.") {
			switch filepath.Ext(name) {
			case ".js", ".wasm", ".pck", ".png":
				allowed[name] = true
			}
		}
	}
	handler := http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		if request.Host != address {
			http.Error(response, "Forbidden", http.StatusForbidden)
			return
		}
		if request.Method != http.MethodGet && request.Method != http.MethodHead {
			response.Header().Set("Allow", "GET, HEAD")
			http.Error(response, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}
		name := strings.TrimPrefix(request.URL.Path, "/")
		if name == "" {
			name = "index.html"
		}
		if !allowed[name] {
			http.NotFound(response, request)
			return
		}
		response.Header().Set("Cache-Control", "no-store")
		response.Header().Set("X-Content-Type-Options", "nosniff")
		if filepath.Ext(name) == ".wasm" {
			response.Header().Set("Content-Type", "application/wasm")
		}
		http.ServeFile(response, request, filepath.Join(root, name))
	})
	server := &http.Server{Handler: handler, ReadHeaderTimeout: 5 * time.Second, IdleTimeout: 60 * time.Second}
	url := "http://" + address + "/"
	fmt.Println("Маленькие миры:", url)
	fmt.Println("Оставьте это окно открытым, пока играете. Для выхода нажмите Ctrl+C.")
	if !*noBrowser {
		var command *exec.Cmd
		if runtime.GOOS == "windows" {
			command = exec.Command("rundll32", "url.dll,FileProtocolHandler", url)
		} else {
			command = exec.Command("xdg-open", url)
		}
		if err := command.Start(); err != nil {
			fmt.Println("Откройте адрес выше в браузере.")
		} else {
			go command.Wait()
		}
	}
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-stop
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		server.Shutdown(ctx)
	}()
	if err := server.Serve(listener); err != nil && err != http.ErrServerClosed {
		fail(err)
	}
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, err)
	fmt.Fprintln(os.Stderr, "Нажмите Enter, чтобы закрыть окно.")
	fmt.Scanln()
	os.Exit(1)
}
