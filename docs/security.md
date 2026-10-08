# Security

## Cilium network policies

Every pod should have an explicit network policy allowing _only_ its required ingress/egress.

In the future, a cluster-wide default-deny policy will be implemented. Today its case-by-base.

## Cloudflared vs Tailscale

Very few services are exposed publicly. If they are, they are exposed with Cloudfare Tunnels (`cloudflared`).

The rest are exposed via different Tailscale services:

- `tailscale-int`: only admins (me)
- `talscale-home`: home users
- `tailscale-sre`: trusted dev users

Both Cloudflare and Tailscale traffic is routed via Envoy Gateway, and then to workloads.
