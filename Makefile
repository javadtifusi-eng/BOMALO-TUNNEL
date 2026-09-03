.PHONY: all build test clean install

all: build

build:
	@echo "Building Tifusi Tunnel..."
	CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o bin/tifusi .

test:
	go test -v -race ./...

clean:
	rm -rf bin/ dist/

install: build
	install -Dm755 bin/tifusi /usr/local/bin/tifusi
