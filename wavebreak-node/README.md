# WAVEBREAK Node

Go node agent for WAVEBREAK.

The node agent enrolls through WAVEBREAK Core and sends periodic heartbeats. Deployment supplies either `WAVEBREAK_NODE_ENROLLMENT_TOKEN` for first boot or `WAVEBREAK_NODE_API_TOKEN` after enrollment; nodes do not receive direct commands from Laravel.

```bash
go test ./...
go build ./cmd/wavebreak-node
```
