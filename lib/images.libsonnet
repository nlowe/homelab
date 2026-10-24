local k = import 'k.libsonnet';

{
  // Centralize images for easy updating
  new(name, version=null, digest=null, registry=null)::
    assert (version != null && digest == null) || (version == null && digest != null) : 'version and digest cannot both be specified';
    {
      registry: registry,
      name: name,
      version: version,
      digest: digest,

      repo()::
        if self.registry != null && self.registry != '' then
          '%(registry)s/%(name)s' % self
        else
          self.name,

      ref()::
        self.repo() +
        (
          if self.version != null && self.version != '' then
            ':%s' % self.version
          else if self.digest != null && self.digest != '' then
            '@%s' % self.digest
        ),
    },

  forContainer(name, container_name=null, group=null)::
    k.core.v1.container.new(if container_name != null then container_name else name, if group != null then std.get(group, name).ref() else $[name].ref()),
} +
{
  // rke2: https://update.rke2.io/v1-release/channels/stable
  // Upgrade with the following as root:
  //   curl -sfL https://get.rke2.io | INSTALL_RKE2_CHANNEL=stable sh -

  // https://github.com/cloudflare/cloudflared/releases/latest
  cloudflared: $.new(name='cloudflare/cloudflared', version='2026.10.3'),

  // https://github.com/esphome/esphome/releases/latest
  // https://github.com/esphome/esphome/pkgs/container/esphome
  esphome: $.new(registry='ghcr.io', name='esphome/esphome', version='2026.10.0'),

  // https://github.com/home-assistant/core/releases/latest
  // https://github.com/home-assistant/core/pkgs/container/home-assistant
  'home-assistant': $.new(registry='ghcr.io', name='home-assistant/home-assistant', version='2026.10.3'),
  // https://github.com/music-assistant/server/releases/latest
  // https://github.com/music-assistant/server/pkgs/container/server
  'music-assistant': $.new(registry='ghcr.io', name='music-assistant/server', version='2.10.8'),
  // https://github.com/OHF-Voice/wyoming-piper/releases/latest
  // https://hub.docker.com/r/rhasspy/wyoming-piper/tags
  piper: $.new(name='rhasspy/wyoming-piper', version='2.5.2'),
  // https://github.com/OHF-Voice/wyoming-faster-whisper/releases/latest
  // https://hub.docker.com/r/rhasspy/wyoming-whisper/tags
  whisper: $.new(name='rhasspy/wyoming-whisper', version='3.8.1'),

  // https://github.com/sensy-one/home-assistant-addons
  // https://github.com/sensy-one/home-assistant-addons/pkgs/container/zone-editor
  'sensy-one-zone-editor': $.new(registry='ghcr.io', name='sensy-one/zone-editor', version='v1.4.9'),
  // https://github.com/zwave-js/zwave-js-ui/releases/latest
  'zwave-js-ui': $.new(name='zwavejs/zwave-js-ui', version='11.25.1'),
  // https://hub.docker.com/r/vernemq/vernemq/tags
  // https://github.com/vernemq/vernemq/releases/latest
  vernemq: $.new(name='vernemq/vernemq', version='2.2.1-alpine'),
  // https://github.com/Koenkk/zigbee2mqtt/releases/latest
  // https://github.com/koenkk/zigbee2mqtt/pkgs/container/zigbee2mqtt
  zigbee2mqtt: $.new(registry='ghcr.io', name='koenkk/zigbee2mqtt', version='2.14.2'),
  // https://github.com/mikefarah/yq/releases/latest
  // https://github.com/mikefarah/yq/pkgs/container/yq
  yq: $.new(registry='ghcr.io', name='mikefarah/yq', version='4.54.1'),

  // https://github.com/brancz/kube-rbac-proxy/releases/latest
  'kube-rbac-proxy': $.new(registry='quay.io', name='brancz/kube-rbac-proxy', version='v0.23.0'),

  // https://github.com/grafana/grafana/releases/latest
  grafana: $.new(name='grafana/grafana', version='13.2.4'),
  // https://github.com/kubernetes/kube-state-metrics/releases/latest
  'kube-state-metrics': $.new(registry='registry.k8s.io', name='kube-state-metrics/kube-state-metrics', version='v2.20.0'),
  // https://github.com/unpoller/unpoller/releases/latest
  // https://github.com/unpoller/unpoller/pkgs/container/unpoller
  'unifi-exporter': $.new(registry='ghcr.io', name='unpoller/unpoller', version='v5.7.0'),

  // https://hub.docker.com/_/busybox#supported-tags-and-respective-dockerfile-links
  // https://busybox.net/
  busybox: $.new(registry='docker.io', name='busybox', version='1.38.0'),
} +
{
  // From charts/cert-manager
  // See https://github.com/cert-manager/cert-manager/releases/latest
  // See https://artifacthub.io/packages/helm/cert-manager/cert-manager?modal=values
  ['cert-manager-%s' % name]: $.new(registry='quay.io', name='jetstack/cert-manager-%s' % name, version='v1.21.3')
  for name in ['controller', 'webhook', 'cainjector', 'acmesolver', 'startupapicheck']
} +
{
  // From charts/cert-manager-csi-driver
  // https://github.com/cert-manager/csi-driver/releases/latest
  // See https://artifacthub.io/packages/helm/cert-manager/cert-manager-csi-driver?modal=values
  'cert-manager-csi-driver': $.new(registry='quay.io', name='jetstack/cert-manager-csi-driver', version='v0.16.1'),
  // See https://quay.io/repository/jetstack/csi-node-driver-registrar?tab=tags
  'csi-node-driver-registrar': $.new(registry='quay.io', name='jetstack/csi-node-driver-registrar', version='v2.18.0'),
  // See https://quay.io/repository/jetstack/livenessprobe?tab=tags&tag=latest
  'sig-storage-livenessprobe': $.new(registry='quay.io', name='jetstack/livenessprobe', version='v2.20.0'),
} +
{
  // From charts/democratic-csi
  // See https://artifacthub.io/packages/helm/democratic-csi/democratic-csi?modal=values
  democratic_csi:: {
    // https://github.com/kubernetes-csi/external-attacher/releases/latest
    externalAttacher: $.new(registry='registry.k8s.io', name='sig-storage/csi-attacher', version='v4.13.0'),
    // https://github.com/kubernetes-csi/external-provisioner/releases/latest
    externalProvisioner: $.new(registry='registry.k8s.io', name='sig-storage/csi-provisioner', version='v6.4.0'),
    // https://github.com/kubernetes-csi/external-resizer/releases/latest
    externalResizer: $.new(registry='registry.k8s.io', name='sig-storage/csi-resizer', version='v2.3.0'),
    // https://github.com/kubernetes-csi/external-snapshotter/releases/latest
    externalSnapshotter: $.new(registry='registry.k8s.io', name='sig-storage/csi-snapshotter', version='v8.7.0'),
    // https://github.com/kubernetes-csi/external-health-monitor/releases/latest
    externalHealthMonitorController: $.new(registry='registry.k8s.io', name='sig-storage/csi-external-health-monitor-controller', version='v0.19.0'),
    // https://github.com/democratic-csi/democratic-csi/tags
    // https://github.com/democratic-csi/democratic-csi/pkgs/container/democratic-csi
    driver: $.new(registry='ghcr.io', name='democratic-csi/democratic-csi', version='v1.9.5'),
    busybox: $.busybox,
    // See https://github.com/kubernetes-csi/node-driver-registrar/releases/latest
    driverRegistrar: $.new(registry='registry.k8s.io', name='sig-storage/csi-node-driver-registrar', version='v2.18.0'),
    // https://github.com/democratic-csi/csi-grpc-proxy/releases/latest
    csiProxy: $.new(registry='docker.io', name='democraticcsi/csi-grpc-proxy', version='v0.5.7'),
  },
} +
{
  // From charts/alloy
  // See https://artifacthub.io/packages/helm/grafana/alloy?modal=values
  // https://github.com/grafana/alloy/releases/latest
  alloy: $.new(registry='docker.io', name='grafana/alloy', version='v1.21.2'),
  // https://github.com/prometheus-operator/prometheus-operator/releases/latest
  // https://github.com/prometheus-operator/prometheus-operator/pkgs/container/prometheus-config-reloader
  'prometheus-config-reloader': $.new(registry='ghcr.io', name='prometheus-operator/prometheus-config-reloader', version='v0.94.2'),
} +
{
  // https://github.com/grafana/rollout-operator/releases/latest
  grafana_rollout_operator: $.new(name='grafana/rollout-operator', version='v0.41.1'),
  // https://github.com/memcached/memcached/tags
  memcached: $.new(name='memcached', version='1.6.45-alpine'),
  // See https://github.com/prometheus/memcached_exporter/releases/latest
  memcachedExporter: $.new(name='prom/memcached-exporter', version='v0.18.0'),
}
{
  // https://github.com/grafana/loki/releases/latest
  // See https://github.com/grafana/loki/blob/main/production/ksonnet/loki/images.libsonnet
  // See https://github.com/grafana/loki/blob/main/production/ksonnet/loki/rollout-operator.libsonnet
  loki:: {
    loki: $.new(name='grafana/loki', version='3.7.9'),
    memcached: $.memcached,
    memcachedExporter: $.memcachedExporter,
    rollout_operator: $.grafana_rollout_operator,
  },
} +
{
  // https://github.com/grafana/mimir/releases/latest
  // See https://github.com/grafana/mimir/blob/main/operations/mimir/images.libsonnet
  mimir:: {
    mimir: $.new(name='grafana/mimir', version='3.2.3'),
    query_tee: $.new(name='grafana/query-tee', version=self.mimir.version),
    continuous_test: $.new(name='grafana/mimir-continuous-test', version=self.mimir.version),
    memcached: $.memcached,
    memcachedExporter: $.memcachedExporter,
    rollout_operator: $.grafana_rollout_operator,
  },
} +
{
  // https://github.com/rancher/local-path-provisioner/releases/latest
  // See https://github.com/rancher/local-path-provisioner/blob/master/deploy/local-path-storage.yaml
  'local-path-provisioner': $.new(name='rancher/local-path-provisioner', version='v0.0.37'),
} +
{
  // https://artifacthub.io/packages/helm/external-secrets-operator/external-secrets?modal=values

  // https://github.com/external-secrets/external-secrets/releases/latest
  'external-secrets': $.new(registry='oci.external-secrets.io', name='external-secrets/external-secrets', version='v2.14.0'),
  // https://github.com/external-secrets/bitwarden-sdk-server/releases/latest
  'bitwarden-sdk-server': $.new(registry='ghcr.io', name='external-secrets/bitwarden-sdk-server', version='v0.8.1'),
} +
{
  // images/qolsysgw/Dockerfile
  // https://github.com/xaf/qolsysgw/releases/latest
  // https://github.com/AppDaemon/appdaemon/releases/latest
  qolsysgw: $.new(name='nlowe/qolsysgw', version='v1.7.1-appdaemon4.5.13'),
} +
{
  // https://github.com/cloudnative-pg/cloudnative-pg/releases/latest
  // https://github.com/cloudnative-pg/charts/releases
  'cloudnative-pg': $.new(registry='ghcr.io', name='cloudnative-pg/cloudnative-pg', version='1.30.1'),

  // https://github.com/cloudnative-pg/pgbouncer-containers/pkgs/container/pgbouncer
  pgbouncer: $.new(registry='ghcr.io', name='cloudnative-pg/pgbouncer', version='1.26.1'),

  // https://github.com/cloudnative-pg/artifacts/blob/main/image-catalogs/catalog-standard-trixie.yaml
  // https://github.com/cloudnative-pg/postgres-containers
  // https://github.com/cloudnative-pg/postgres-containers/pkgs/container/postgresql
  pg: $.new(registry='ghcr.io', name='cloudnative-pg/postgresql', version='18.6-standard-trixie'),

  // https://github.com/tensorchord/cloudnative-vectorchord/blob/main/versions.yaml
  // https://github.com/tensorchord/cloudnative-vectorchord/pkgs/container/cloudnative-vectorchord
  'pg-vectorchord': $.new(registry='ghcr.io', name='tensorchord/cloudnative-vectorchord', version='18.6-1.1.1'),
} +
{
  immich:: {
    // https://github.com/immich-app/immich/releases/latest
    // https://github.com/immich-app/immich-charts/releases/latest
    version:: 'v3.3.5',

    server: $.new(registry='ghcr.io', name='immich-app/immich-server', version=self.version),
    'machine-learning': $.new(registry='ghcr.io', name='immich-app/immich-machine-learning', version=self.version),

    // https://github.com/valkey-io/valkey/releases/latest
    // https://github.com/valkey-io/valkey-container/pkgs/container/valkey
    valkey: $.new(registry='ghcr.io', name='valkey-io/valkey', version='9.1.2-alpine'),
    // https://github.com/oliver006/redis_exporter/releases/latest
    'redis-exporter': $.new(registry='ghcr.io', name='oliver006/redis_exporter', version='v1.96.0'),
  },
} +
{
  conatus:: {
    // https://github.com/nojusmorkunas/conatus/releases/latest
    // v1.3.0 released, but the app image isn't available: https://github.com/nojusmorkunas/conatus/issues/52
    version:: '1.2.2',

    conatus: $.new(registry='ghcr.io', name='nojusmorkunas/conatus', version=self.version),
    'conatus-ops': $.new(registry='ghcr.io', name='nojusmorkunas/conatus', version='%s-ops' % self.version),
  },
} +
{
  // https://github.com/dancwilliams/protonmail-bridge-docker/releases/latest
  'protonmail-bridge': $.new(registry='ghcr.io', name='dancwilliams/protonmail-bridge-docker', version='v3.27.1-4'),
} +
{
  // https://github.com/alam00000/bentopdf/releases/latest
  bentopdf: $.new(registry='ghcr.io', name='alam00000/bentopdf-simple', version='v2.8.10'),
} +
{
  // https://github.com/gregtwallace/certwarden/releases/latest
  certwarden: $.new(registry='ghcr.io', name='gregtwallace/certwarden', version='v0.30.1'),
}
