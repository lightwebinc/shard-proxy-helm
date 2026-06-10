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

## Helm test

```bash
helm test proxy -n bsv-mcast
```

Probes `/healthz` and `/metrics` on the metrics Service.

## Release

The `release.yml` workflow is gated. It runs only via `workflow_dispatch` with `confirm: RELEASE` and a `production` GitHub Environment review. Tag-based auto-release is intentionally disabled.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
