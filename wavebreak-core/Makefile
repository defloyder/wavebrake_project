.PHONY: tidy test race build lint migrate-up migrate-down

tidy:
	go mod tidy

test:
	go test ./...

race:
	go test -race ./...

build:
	go build ./cmd/wavebreak-api ./cmd/wavebreak-worker ./cmd/wavebreak-cli ./cmd/wavebreak-migrate

lint:
	golangci-lint run ./...

migrate-up:
	goose -dir migrations postgres "$$WAVEBREAK_DATABASE_URL" up

migrate-down:
	goose -dir migrations postgres "$$WAVEBREAK_DATABASE_URL" down
