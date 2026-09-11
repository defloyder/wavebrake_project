FROM golang:1.25-alpine AS build

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /out/wavebreak-api ./cmd/wavebreak-api \
    && CGO_ENABLED=0 GOOS=linux go build -o /out/wavebreak-worker ./cmd/wavebreak-worker \
    && CGO_ENABLED=0 GOOS=linux go build -o /out/wavebreak-cli ./cmd/wavebreak-cli \
    && CGO_ENABLED=0 GOOS=linux go build -o /out/wavebreak-migrate ./cmd/wavebreak-migrate

FROM alpine:3.22
RUN adduser -D -H wavebreak
WORKDIR /app
COPY --from=build /out/wavebreak-api /usr/local/bin/wavebreak-api
COPY --from=build /out/wavebreak-worker /usr/local/bin/wavebreak-worker
COPY --from=build /out/wavebreak-cli /usr/local/bin/wavebreak-cli
COPY --from=build /out/wavebreak-migrate /usr/local/bin/wavebreak-migrate
COPY migrations ./migrations
COPY api ./api
USER wavebreak
EXPOSE 8080
CMD ["wavebreak-api"]
