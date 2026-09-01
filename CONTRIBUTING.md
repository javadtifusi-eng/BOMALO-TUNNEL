# Contributing to Bomalo Tunnel

Thank you for your interest in contributing!

## Development Setup

```bash
git clone https://github.com/yourusername/bomalo-tunnel.git
cd bomalo-tunnel
go mod tidy
make build
```

## Code Style

- Follow standard Go conventions (`gofmt`, `golint`)
- Write tests for new features
- Keep functions focused and small
- Add comments for exported functions

## Pull Request Process

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'feat: add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Commit Message Format

```
feat: add new transport
fix: resolve memory leak in QUIC
docs: update README with new examples
refactor: simplify tunnel engine
test: add unit tests for nettest
```

## Reporting Issues

Please include:
- OS and version
- Go version (`go version`)
- Steps to reproduce
- Expected vs actual behavior
- Logs (if applicable)
