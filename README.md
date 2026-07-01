# shard-proxy Helm chart

> Part of the [**BSV Layered Multicast**](https://github.com/lightwebinc/bsv-multicast) open-source project — see the main repository for the full architecture, design docs, and BRC specifications.

Helm chart for [shard-proxy](https://github.com/lightwebinc/shard-proxy) — the IPv6 multicast frame proxy in the BSV multicast transaction distribution pipeline.

This repository packages templates, default values, JSON Schema validation, and CI workflows for the proxy. The application source lives in [`shard-proxy`](https://github.com/lightwebinc/shard-proxy).

## Install

> The chart references `ghcr.io/lightwebinc/shard-proxy:<appVersion>` — `appVersion` always tracks a published image tag (see the contract note in [`Chart.yaml`](Chart.yaml)).

```bash
# OCI registry
helm install proxy oci://ghcr.io/lightwebinc/charts/shard-proxy \
  --version 0.3.2 -n bsv-mcast --create-namespace \
  --set networking.multus.fabricIPv6=fd20::21/64

# Or from a local clone
helm install proxy . -n bsv-mcast --create-namespace \
  --set networking.mode=host
```

## Networking modes

| Mode | Description |
|---|---|
| `multus` (default) | Primary CNI for control/metrics; macvlan secondary `net1` on dedicated fabric NIC. Requires a `NetworkAttachmentDefinition` named `mcast-fabric` in namespace `bsv-mcast`. |
| `host` | `hostNetwork: true`; `MULTICAST_IF` resolves to the host NIC named by `config.multicastIf`. Single-NIC fallback. |
| `unicast` | Reserved for a future proxy `EGRESS_MODE=unicast-list` release. The chart renders pods but emits a `helm.sh/chart-warnings` annotation. |

See [multicast-kube-infra](https://github.com/lightwebinc/multicast-kube-infra) for wiring proxy + listener + retry-endpoint via Helmfile / ArgoCD / Terraform / plain Helm.

### BGP-anycast ingress (host mode)

For HA ingress, run the proxy as a `hostNetwork` pod on the tainted data-plane pool and front the replicas with **external BGP/ECMP anycast** — every node binds the same anycast VIP, senders reach the nearest, and traffic re-homes on failure. Worked example: [`examples/anycast-ingress.yaml`](examples/anycast-ingress.yaml).

```sh
helm install sp . -f examples/anycast-ingress.yaml
```

Division of labour (the chart stays out of the hot path):

| Concern | Owner |
|---|---|
| Anycast VIP on `lo`, FRR/BIRD announce, health-gated withdraw | **host** (`ingress-infra` networking+bgp roles; `fleet` `ingress:` block) |
| Bind the VIP, serve `/healthz` + `/readyz` on `:9100` | **this chart** (`networking.mode: host`, `config.listenAddr: "[::]"`) |

The proxy binds `[::]`, which covers the host-owned VIP — the chart never runs BGP or manages the VIP, so k8s carries no ingress packets through the pod network. For **graceful drain**, point the host speaker at `/readyz` (`fleet ingress.health_path: /readyz`): on SIGTERM the proxy drains for `config.drainTimeout` while readiness is false, so the VIP withdraws and senders re-home **before** the pod stops. BGP-anycast ingress; see [`examples/anycast-ingress.yaml`](examples/anycast-ingress.yaml).

### Orchestrated edge (W2)

On a fleet-orchestrated collapsed edge the proxy runs as a `hostNetwork` pod on a k0s worker, sharing the host with a co-resident listener and the kernel ip6gre + `mc-router` fabric (configured by the `integrated-infra` roles). Worked example: [`examples/orchestrated-edge.yaml`](examples/orchestrated-edge.yaml).

```sh
helm install shard-proxy-us . -f examples/orchestrated-edge.yaml \
  --set nodeSelector."topology\.kubernetes\.io/region"=us
```

Collapsed-node config keys:

| Key | Env var | Default | Notes |
|-----|---------|---------|-------|
| `stampSource` | `STAMP_SOURCE` | `true` (binary) | Stamp the BRC-129 own-traffic-exclusion HashKey from the **observed per-consumer source IP**. `true` here because the `hostNetwork` pod sees real source addresses. Set `false` ONLY behind a source-rewriting LB. `null` inherits the binary default. |
| `egressMulticastLoop` | `EGRESS_MULTICAST_LOOP` | `null` (off) | **REQUIRED `true` on a collapsed node**: the kernel MFC only forwards the proxy's locally-emitted multicast to the co-resident listener (and the fabric tunnels) when `IPV6_MULTICAST_LOOP` is on. |
| `egressHoplimit` | `EGRESS_HOPLIMIT` | `1` | Raise the multicast hop limit — the default `1` dies on the first mesh/tunnel hop, so inter-region delivery needs a higher value (e.g. `16`). |

Two host facts the preset also sets:

- **`NET_RAW` capability** — raw multicast emit on a collapsed node needs `NET_RAW` in addition to `NET_ADMIN`; the preset adds both under `securityContext.capabilities`.
- **Metrics on `:9110`, not `:9100`** — the Prometheus node-exporter DaemonSet owns hostPort `9100` on every k8s node, so a `hostNetwork` proxy binding `9100` collides. The preset moves `config.metricsAddr`, `service.metricsPort`, and `metrics.port` to `9110` in lockstep.

## Values reference

See [`values.yaml`](values.yaml) for the full annotated reference. Every flag accepted by the proxy binary is exposed under `.config`; cluster-shape knobs (replicas, autoscaling, PDB, NetworkPolicy, ServiceMonitor) live at the top level.

The chart includes [`values.schema.json`](values.schema.json) — `helm install` rejects out-of-range `shardBits`, invalid `mcScope`, invalid `networking.mode`, an invalid `logFormat` (`text`|`json`), `logLevel` (`debug`|`info`|`warn`|`error`), or out-of-range `traceSampling` (`0`–`1`) before reaching the cluster.

### Pod defaults (v0.3.2+)

The chart ships hardened pod-level defaults: `resources` requests/limits (CPU-bound datapath — tune against your own throughput benchmark), a nonroot `podSecurityContext` (uid 65532, seccomp `RuntimeDefault`, matching the distroless image), and `terminationGracePeriodSeconds: 30` — keep it `>= config.drainTimeout` or Kubernetes will SIGKILL the proxy mid-drain. Single-replica HA caveats are documented inline at `replicaCount` in [`values.yaml`](values.yaml).

### Logging & tracing

`config.logFormat` (`text` default | `json`) → `LOG_FORMAT`, `config.logLevel`
(`info`) → `LOG_LEVEL`, and `config.traceSampling` (`0`) → `TRACE_SAMPLING`.
Set `logFormat: json` for one-JSON-object-per-line stdout suitable for the
node-local collector; the log level is also runtime-togglable via `POST /loglevel`
on the metrics port and SIGHUP. `traceSampling > 0` (with `config.otlpEndpoint`)
enables control-plane traces. See the
[Unified Logging Plan](https://github.com/lightwebinc/shard-common/blob/main/docs/logging.md).

### Miner-tier ingress gate

The user ingress ports (`config.udpListenPort` 8725 / `config.tcpListenPort`)
are transaction-only: BRC-131 block, BRC-133 coinbase, and BRC-132 subtree
data frames are dropped there (counted as `bsp_privileged_frame_rejected_total`).
Those privileged frames may only enter through a separate miner ingress —
`config.minerListenPort` (UDP) / `config.minerTcpListenPort` (TCP). Leaving both
at `0` means the proxy ingests transactions only.

Expose the miner ports to miner-tier peers alone: set
`networkPolicy.minerIngressFrom` (fail-closed — an empty list with a miner port
set admits no peers). On a Multus/host-network multicast fabric the binding
source restriction is enforced at the fabric firewall / provider ACL, not the
pod-network `NetworkPolicy`. `config.txAcceptPrivileged: true` reverts the user
port to legacy accept-all for collapsed/single-port nodes. See
[DESIGN.md § Ingress Authorization](https://github.com/lightwebinc/bsv-multicast/blob/main/DESIGN.md#ingress-authorization-miner-tier-gate).

### Ingress TxID dedup backend

`config.txidDedup` controls the two-tier ingress dedup gate. Tier-1 is the
always-on in-process LRU; tier-2 is the modular `shard-common/cache` backend
selected by `config.txidDedup.backend` (`redis` | `aerospike` | `memory` |
`none`; empty infers `redis` when `redisAddr` is set, else `none`).

| Backend | Keys | Notes |
|---------|------|-------|
| `redis` | `txidDedup.redisAddr` | Redis/Valkey/Dragonfly |
| `aerospike` | `txidDedup.aerospikeHosts` (+ `aerospikeNamespace`, `aerospikeSet`) | namespace must be provisioned; TTL floor 1s |

`txidDedup.prefix` MUST match the local listener's `ingressSet.prefix`. When
setting comma-separated `aerospikeHosts` via `--set`, escape the commas
(`--set-string 'config.txidDedup.aerospikeHosts=a:3000\,b:3000'`) or use a
values file. See
[`shard-common/docs/cache-backend.md`](https://github.com/lightwebinc/shard-common/blob/main/docs/cache-backend.md).

### SSM (Source-Specific Multicast)

`config.sourceMode` (`asm` default, `ssm` opt-in) renders to the
`SOURCE_MODE` env var. When `ssm`, set `config.bindSource` to the
per-pod IPv6 from your Multus/Whereabouts allocation — each replica
MUST hold a distinct address (anycast/ECMP-shared sources break
PIM-SSM RPF). `bindSource` renders to `BIND_SOURCE`. See the
[SSM Support Plan](https://github.com/lightwebinc/bsv-multicast/blob/main/DESIGN.md#source-specific-multicast-ssm)
for fabric prerequisites.

### BRC-139 auto-shard-config (opt-in)

`config.autoShardConfig` exposes the BRC-139 manifest consumer. Off by
default (`enabled: false`); manual `config.shardBits`/`sourceMode` always
win. When `enabled: true` the proxy opens a dedicated beacon-receive
socket and adopts `ShardBits`/`SourceMode` from authoritative pilot
manifests once `pilotQuorum` distinct announcers agree for the
hysteresis window.

| Key | Env var | Default | Notes |
|-----|---------|---------|-------|
| `enabled` | `MANIFEST_CONSUMER_ENABLED` | `false` | master switch |
| `bootstrap` | `MANIFEST_BOOTSTRAP` | `optional` | `required` fails closed: no data-plane egress until quorum |
| `pilotQuorum` | `PILOT_QUORUM` | `2` | min distinct authoritative announcers |
| `pilotHysteresis` | `PILOT_HYSTERESIS` | `0s` | `0s` ⇒ 2 × AnnounceInterval |
| `beaconScope` | `MANIFEST_BEACON_SCOPE` | `""` | empty inherits `mcScope` |
| `beaconPort` | `MANIFEST_BEACON_PORT` | `9001` | matches shard-manifest `-port` |
| `liveResharding` | `LIVE_RESHARDING` | `false` | `true` = dual-emit bridging; `false` = restart-on-adopt |
| `bridgingWindow` | `BRIDGING_WINDOW` | `0s` | `0s` ⇒ honour pilot `TransitionEpoch` |

See the [Automatic Shard Configuration Plan](https://github.com/lightwebinc/bsv-multicast/blob/main/DESIGN.md#automatic-shard-configuration).

### BRC-142 origin coalescing (opt-in)

`config.coalesce` (default `false`) renders `COALESCE`; when enabled the proxy
packs many small transactions from one ingest batch into bundle datagrams
(`FrameVer 0x08`) to cut fabric pps. Tune with `config.coalesceMaxBytes`
(`COALESCE_MAX_BYTES`, `0` ⇒ 1500), `config.coalesceMaxMembers`
(`COALESCE_MAX_MEMBERS`, `0` = MTU-bound), and `config.coalesceCarryTxid`
(`COALESCE_CARRY_TXID`). Coalesce at the origin, never at a spine. See the
[BRC-142 coalescing frame](https://github.com/lightwebinc/bsv-multicast/blob/main/docs/brc-142-coalescing-frame.md).

## Helm test

```bash
helm test proxy -n bsv-mcast
```

Probes `/healthz` and `/metrics` on the metrics Service.

## Release

The `release.yml` workflow is gated. It runs only via `workflow_dispatch` with `confirm: RELEASE` and a `production` GitHub Environment review. Tag-based auto-release is intentionally disabled.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
