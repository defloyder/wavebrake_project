FROM golang:1.25-alpine AS build

WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -p=1 -o /out/wavebreak-node ./cmd/wavebreak-node

FROM alpine:3.22
RUN adduser -D -H wavebreak
COPY --from=build /out/wavebreak-node /usr/local/bin/wavebreak-node
USER wavebreak
CMD ["wavebreak-node"]
