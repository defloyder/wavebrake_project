.PHONY: tidy test race build lint

tidy:
	go mod tidy

test:
	go test ./...

race:
	go test -race ./...

build:
	go build ./cmd/wavebreak-node

lint:
	golangci-lint run ./...
