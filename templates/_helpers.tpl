{{/*
Expand the name of the chart.
*/}}
{{- define "shard-proxy.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "shard-proxy.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Chart label string.
*/}}
{{- define "shard-proxy.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels.
*/}}
{{- define "shard-proxy.labels" -}}
helm.sh/chart: {{ include "shard-proxy.chart" . }}
{{ include "shard-proxy.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: bsv-multicast
{{- end -}}

{{/*
Selector labels.
*/}}
{{- define "shard-proxy.selectorLabels" -}}
app.kubernetes.io/name: {{ include "shard-proxy.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
ServiceAccount name.
*/}}
{{- define "shard-proxy.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "shard-proxy.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Multus annotation. Emits only when networking.mode=multus.
*/}}
{{- define "shard-proxy.multusAnnotation" -}}
{{- if eq .Values.networking.mode "multus" -}}
k8s.v1.cni.cncf.io/networks: |
  [{
    "name": {{ .Values.networking.multus.networkName | quote }},
    "namespace": {{ .Values.networking.multus.namespace | quote }},
    {{- if .Values.networking.multus.fabricIPv6 }}
    "ips": [ {{ .Values.networking.multus.fabricIPv6 | quote }} ],
    {{- end }}
    "interface": {{ .Values.networking.multus.interface | quote }}
  }]
{{- end -}}
{{- end -}}

{{/*
Resolve the MULTICAST_IF env value based on networking.mode.
*/}}
{{- define "shard-proxy.multicastIf" -}}
{{- if eq .Values.networking.mode "multus" -}}
{{- .Values.networking.multus.interface -}}
{{- else -}}
{{- .Values.config.multicastIf -}}
{{- end -}}
{{- end -}}

{{/*
Container env vars rendered from .Values.config plus extraEnv passthrough.
*/}}
{{- define "shard-proxy.env" -}}
- name: LISTEN_ADDR
  value: {{ .Values.config.listenAddr | quote }}
- name: UDP_LISTEN_PORT
  value: {{ .Values.config.udpListenPort | quote }}
- name: TCP_LISTEN_PORT
  value: {{ .Values.config.tcpListenPort | quote }}
- name: MINER_LISTEN_PORT
  value: {{ .Values.config.minerListenPort | default 0 | quote }}
- name: MINER_TCP_LISTEN_PORT
  value: {{ .Values.config.minerTcpListenPort | default 0 | quote }}
- name: TX_ACCEPT_PRIVILEGED
  value: {{ .Values.config.txAcceptPrivileged | default false | quote }}
- name: MULTICAST_IF
  value: {{ include "shard-proxy.multicastIf" . | quote }}
- name: EGRESS_PORT
  value: {{ .Values.config.egressPort | quote }}
- name: SHARD_BITS
  value: {{ .Values.config.shardBits | quote }}
- name: MC_SCOPE
  value: {{ .Values.config.mcScope | quote }}
- name: MC_GROUP_ID
  value: {{ .Values.config.mcGroupId | quote }}
- name: SOURCE_MODE
  value: {{ .Values.config.sourceMode | default "asm" | quote }}
{{- if .Values.config.bindSource }}
- name: BIND_SOURCE
  value: {{ .Values.config.bindSource | quote }}
{{- end }}
- name: NUM_WORKERS
  value: {{ .Values.config.numWorkers | quote }}
- name: FRAG_MTU
  value: {{ .Values.config.fragMtu | quote }}
- name: DRAIN_TIMEOUT
  value: {{ .Values.config.drainTimeout | quote }}
- name: DEBUG
  value: {{ .Values.config.debug | quote }}
- name: LOG_FORMAT
  value: {{ .Values.config.logFormat | quote }}
- name: LOG_LEVEL
  value: {{ .Values.config.logLevel | quote }}
{{- if .Values.config.traceSampling }}
- name: TRACE_SAMPLING
  value: {{ .Values.config.traceSampling | quote }}
{{- end }}
- name: METRICS_ADDR
  value: {{ .Values.config.metricsAddr | quote }}
{{- if kindIs "bool" .Values.config.stampSource }}
- name: STAMP_SOURCE
  value: {{ .Values.config.stampSource | quote }}
{{- end }}
{{- if .Values.config.instanceId }}
- name: INSTANCE_ID
  value: {{ .Values.config.instanceId | quote }}
{{- end }}
{{- if .Values.config.otlpEndpoint }}
- name: OTLP_ENDPOINT
  value: {{ .Values.config.otlpEndpoint | quote }}
- name: OTLP_INTERVAL
  value: {{ .Values.config.otlpInterval | quote }}
{{- end }}
{{- if .Values.config.txidDedup }}
- name: TXID_DEDUP_LOCAL_CAP
  value: {{ .Values.config.txidDedup.localCap | quote }}
- name: TXID_DEDUP_PREFIX
  value: {{ .Values.config.txidDedup.prefix | quote }}
- name: TXID_DEDUP_TTL
  value: {{ .Values.config.txidDedup.ttl | quote }}
{{- if .Values.config.txidDedup.backend }}
- name: TXID_DEDUP_BACKEND
  value: {{ .Values.config.txidDedup.backend | quote }}
{{- end }}
{{- if .Values.config.txidDedup.redisAddr }}
- name: TXID_DEDUP_REDIS_ADDR
  value: {{ .Values.config.txidDedup.redisAddr | quote }}
{{- end }}
{{- if .Values.config.txidDedup.aerospikeHosts }}
- name: TXID_DEDUP_AEROSPIKE_HOSTS
  value: {{ .Values.config.txidDedup.aerospikeHosts | quote }}
- name: TXID_DEDUP_AEROSPIKE_NAMESPACE
  value: {{ .Values.config.txidDedup.aerospikeNamespace | quote }}
- name: TXID_DEDUP_AEROSPIKE_SET
  value: {{ .Values.config.txidDedup.aerospikeSet | quote }}
{{- end }}
{{- end }}
{{- if .Values.config.autoShardConfig }}
- name: MANIFEST_CONSUMER_ENABLED
  value: {{ .Values.config.autoShardConfig.enabled | quote }}
- name: MANIFEST_BOOTSTRAP
  value: {{ .Values.config.autoShardConfig.bootstrap | quote }}
- name: PILOT_QUORUM
  value: {{ .Values.config.autoShardConfig.pilotQuorum | quote }}
- name: PILOT_HYSTERESIS
  value: {{ .Values.config.autoShardConfig.pilotHysteresis | quote }}
- name: MANIFEST_BEACON_SCOPE
  value: {{ .Values.config.autoShardConfig.beaconScope | quote }}
- name: MANIFEST_BEACON_PORT
  value: {{ .Values.config.autoShardConfig.beaconPort | quote }}
- name: LIVE_RESHARDING
  value: {{ .Values.config.autoShardConfig.liveResharding | quote }}
- name: BRIDGING_WINDOW
  value: {{ .Values.config.autoShardConfig.bridgingWindow | quote }}
{{- end }}
{{- with .Values.extraEnv }}
{{ toYaml . }}
{{- end }}
{{- end -}}
