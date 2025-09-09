# Ethereum Endpoint Reference Guide

This document provides information about the Ethereum endpoints configured in Bitcoin Sprint.

## Current Endpoints

### HTTP/RPC Endpoints

| Endpoint | Provider | Notes |
|---------|----------|-------|
| `https://eth.rpc.nethermind.io` | Nethermind | Official client team endpoint, closest to the source |
| `https://rpc.eth.gateway.fm` | Gateway.fm/EF | Ethereum Foundation supported endpoint |
| `https://rpc.flashbots.net` | Flashbots | MEV-protected endpoint, best for sending transactions |

### WebSocket Endpoints

| Endpoint | Provider | Notes |
|---------|----------|-------|
| `wss://ethereum.publicnode.com` | PublicNode | More reliable public WebSocket endpoint |
| `wss://eth.drpc.org` | DRPC | Distributed RPC provider |

## Endpoint Reliability and Performance

The endpoints have been selected based on:

1. **Proximity to source**: Nethermind directly runs Ethereum clients
2. **Official support**: Gateway.fm is supported by the Ethereum Foundation
3. **Special features**: Flashbots protects against MEV extraction
4. **Reliability**: These endpoints have more consistent uptime than general public endpoints

## Rate Limiting Considerations

Even with these improved endpoints, rate limiting is still a concern. The system includes:

- Polling interval: 5000ms (5 seconds)
- Rate limit factor: 0.25
- Connection timeout: 15 seconds

These settings help prevent overwhelming the endpoints while still maintaining connectivity.

## Fallback Strategy

Bitcoin Sprint uses a fallback strategy where if the primary endpoint fails:

1. The system attempts to use the next endpoint in the list
2. If all endpoints fail, it will retry with exponential backoff
3. Multiple connection attempts help ensure reliability

## Production Recommendation

While these endpoints are more reliable than general public endpoints, for production-grade applications with high throughput requirements, consider:

1. Running your own Ethereum node
2. Using a paid service like Alchemy, Infura, or QuickNode with API keys
3. Using decentralized RPC providers like Pokt Network with a dedicated endpoint
