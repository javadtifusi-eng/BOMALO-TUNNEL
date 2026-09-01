.PHONY: all build build-cli build-daemon test clean install docker

VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
LDFLAGS := -X main.Version=$(VERSION) -s -w

all: build

build: build-cli build-daemon

build-cli:
	@echo "Building Bomalo CLI..."
	CGO_ENABLED=0 go build -ldflags "$(LDFLAGS)" -o bin/bomalo ./cmd/bomalo

build-daemon:
	@echo "Building Bomalo Daemon..."
	CGO_ENABLED=0 go build -ldflags "$(LDFLAGS)" -o bin/bomalod ./cmd/bomalod

build-ebpf:
	@echo "Building eBPF programs..."
	go generate ./internal/ebpf/...

test:
	go test -v -race ./...

clean:
	rm -rf bin/ dist/

install: build
	install -Dm755 bin/bomalo /usr/local/bin/bomalo
	install -Dm755 bin/bomalod /usr/local/bin/bomalod

docker:
	docker build -t bomalo-tunnel:$(VERSION) -f deploy/docker/Dockerfile .

proto:
	protoc --go_out=. --go-grpc_out=. pkg/pb/bomalo.proto

run-dev:
	go run ./cmd/bomalod --config configs/dev.yaml
