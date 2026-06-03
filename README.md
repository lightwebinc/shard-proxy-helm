# shard-proxy Helm chart

Helm chart for [shard-proxy](https://github.com/lightwebinc/shard-proxy) — the IPv6 multicast frame proxy in the BSV multicast transaction distribution pipeline.

This repository packages templates, default values, JSON Schema validation, and CI workflows for the proxy. The application source lives in [`shard-proxy`](https://github.com/lightwebinc/shard-proxy).

## Install

> The chart references `ghcr.io/lightwebinc/shard-proxy:<appVersion>`. Until the corresponding image is published from the application repo, `helm install` will succeed in rendering but pods will `ImagePullBackOff`.

```bash
# OCI registry
helm install proxy oci://ghcr.io/lightwebinc/charts/shard-proxy \
  --version 0.1.0 -n bsv-mcast --create-namespace \
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

See the [composition spec](https://github.com/lightwebinc/bsv-multicast/blob/main/containerization/composition-spec.md) for wiring proxy + listener + retry-endpoint via Helmfile / ArgoCD / Terraform / plain Helm.

## Values reference

See [`values.yaml`](values.yaml) for the full annotated reference. Every flag accepted by the proxy binary is exposed under `.config`; cluster-shape knobs (replicas, autoscaling, PDB, NetworkPolicy, ServiceMonitor) live at the top level.

The chart includes [`values.schema.json`](values.schema.json) — `helm install` rejects out-of-range `shardBits`, invalid `mcScope`, or invalid `networking.mode` before reaching the cluster.

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
[`bsv-multicast/docs/ModularCacheBackend/`](https://github.com/lightwebinc/bsv-multicast/blob/main/docs/ModularCacheBackend/modular-cache-backend.md).

### SSM (Source-Specific Multicast)

`config.sourceMode` (`asm` default, `ssm` opt-in) renders to the
`SOURCE_MODE` env var. When `ssm`, set `config.bindSource` to the
per-pod IPv6 from your Multus/Whereabouts allocation — each replica
MUST hold a distinct address (anycast/ECMP-shared sources break
PIM-SSM RPF). `bindSource` renders to `BIND_SOURCE`. See the
[SSM Support Plan](https://github.com/lightwebinc/bsv-multicast/blob/main/docs/SourceSpecificMulticast/ssm-support-plan.md)
for fabric prerequisites.

### BRC-137 auto-shard-config (opt-in)

`config.autoShardConfig` exposes the BRC-137 manifest consumer. Off by
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

See the [Automatic Shard Configuration Plan](https://github.com/lightwebinc/bsv-multicast/blob/main/docs/AutoShardConfig/auto-shard-config-plan.md).

## Helm test

```bash
helm test proxy -n bsv-mcast
```

Probes `/healthz` and `/metrics` on the metrics Service.

## Release

The `release.yml` workflow is gated. It runs only via `workflow_dispatch` with `confirm: RELEASE` and a `production` GitHub Environment review. Tag-based auto-release is intentionally disabled.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
