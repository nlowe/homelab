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

  forContainer(name, container_name=null)::
    k.core.v1.container.new(if container_name != null then container_name else name, $[name].ref()),
} +
{
  // https://github.com/caddyserver/gateway/pkgs/container/gateway
  caddy: $.new(registry='ghcr.io', name='caddyserver/gateway', version='caddy-2.10.2'),
  'caddy-gateway': $.new(registry='ghcr.io', name='caddyserver/gateway', version='v0.1.0'),

  // https://www.linuxserver.io/our-images
  'code-server': $.new(registry='lscr.io', name='linuxserver/code-server', version='4.105.1-ls303'),

  // https://github.com/cloudflare/cloudflared/releases/latest
  cloudflared: $.new(name='cloudflare/cloudflared', version='2025.11.1'),

  // https://github.com/esphome/esphome/releases/latest
  // https://github.com/esphome/esphome/pkgs/container/esphome
  esphome: $.new(registry='ghcr.io', name='esphome/esphome', version='2025.10.4'),
  // https://github.com/home-assistant/core/releases/latest
  // https://github.com/home-assistant/core/pkgs/container/home-assistant
  'home-assistant': $.new(registry='ghcr.io', name='home-assistant/home-assistant', version='2025.11.1'),
  // See images/sensy-one-zone-editor
  // https://github.com/sensy-one/home-assistant-addons
  'sensy-one-zone-editor': $.new(registry='docker.io', name='nlowe/sensy-one-zone-editor', version='main-05e259aa029ee8fe836f1cfaaf49c1ed8707cff1'),
  // https://github.com/zwave-js/zwave-js-ui/releases/latest
  'zwave-js-ui': $.new(name='zwavejs/zwave-js-ui', version='11.6.1'),
  // https://hub.docker.com/r/vernemq/vernemq/tags
  vernemq: $.new(name='vernemq/vernemq', version='2.1.1'),
  // https://github.com/Koenkk/zigbee2mqtt/releases/latest
  // https://github.com/koenkk/zigbee2mqtt/pkgs/container/zigbee2mqtt
  zigbee2mqtt: $.new(registry='ghcr.io', name='koenkk/zigbee2mqtt', version='2.6.3'),
  // https://github.com/mikefarah/yq/releases/latest
  // https://github.com/mikefarah/yq/pkgs/container/yq
  yq: $.new(registry='ghcr.io', name='mikefarah/yq', version='4.48.1'),

  // https://github.com/brancz/kube-rbac-proxy/releases/latest
  'kube-rbac-proxy': $.new(registry='quay.io', name='brancz/kube-rbac-proxy', version='v0.20.0'),

  // https://github.com/grafana/grafana/releases/latest
  grafana: $.new(name='grafana/grafana', version='12.2.1'),
  // https://github.com/kubernetes/kube-state-metrics/releases/latest
  'kube-state-metrics': $.new(registry='registry.k8s.io', name='kube-state-metrics/kube-state-metrics', version='v2.17.0'),
  // https://github.com/unpoller/unpoller/releases/latest
  // https://github.com/unpoller/unpoller/pkgs/container/unpoller
  'unifi-exporter': $.new(registry='ghcr.io', name='unpoller/unpoller', version='v2.15.4'),
} +
{
  // From charts/cert-manager
  // See https://github.com/cert-manager/cert-manager/releases/latest
  // See https://artifacthub.io/packages/helm/cert-manager/cert-manager?modal=values
  ['cert-manager-%s' % name]: $.new(registry='quay.io', name='jetstack/cert-manager-%s' % name, version='v1.19.1')
  for name in ['controller', 'webhook', 'cainjector', 'acmesolver', 'startupapicheck']
} +
{
  // From charts/cert-manager-csi-driver
  // See https://artifacthub.io/packages/helm/cert-manager/cert-manager-csi-driver?modal=values
  'cert-manager-csi-driver': $.new(registry='quay.io', name='jetstack/cert-manager-csi-driver', version='v0.11.1'),
  // See https://github.com/kubernetes-csi/node-driver-registrar/releases/latest
  'csi-node-driver-registrar': $.new(registry='registry.k8s.io', name='sig-storage/csi-node-driver-registrar', version='v2.15.0'),
  // See https://github.com/kubernetes-csi/livenessprobe/releases/latest
  'sig-storage-livenessprobe': $.new(registry='registry.k8s.io', name='sig-storage/livenessprobe', version='v2.17.0'),
} +
{
  // From charts/democratic-csi
  // See https://artifacthub.io/packages/helm/democratic-csi/democratic-csi?modal=values
  democratic_csi:: {
    // https://github.com/kubernetes-csi/external-attacher/releases/latest
    externalAttacher: $.new(registry='registry.k8s.io', name='sig-storage/csi-attacher', version='v4.10.0'),
    // https://github.com/kubernetes-csi/external-provisioner/releases/latest
    // 6.0+ requires k8s 1.34+
    externalProvisioner: $.new(registry='registry.k8s.io', name='sig-storage/csi-provisioner', version='v5.3.0'),
    // https://github.com/kubernetes-csi/external-resizer/releases/latest
    // 2.0+ requires k8s 1.34+
    externalResizer: $.new(registry='registry.k8s.io', name='sig-storage/csi-resizer', version='v1.14.0'),
    // https://github.com/kubernetes-csi/external-snapshotter/releases/latest
    externalSnapshotter: $.new(registry='registry.k8s.io', name='sig-storage/csi-snapshotter', version='v8.4.0'),
    // https://github.com/kubernetes-csi/external-health-monitor/releases/latest
    externalHealthMonitorController: $.new(registry='registry.k8s.io', name='sig-storage/csi-external-health-monitor-controller', version='v0.16.0'),
    // https://github.com/democratic-csi/democratic-csi/tags
    // https://github.com/democratic-csi/democratic-csi/issues/479
    // https://github.com/democratic-csi/democratic-csi/issues/479#issuecomment-3476531774: 1.9.5 will include this fix
    driver: $.new(registry='docker.io', name='democraticcsi/democratic-csi', version='next@sha256:6b758d6faf96f0e96d4b8ac0e240fc290c7bace23c20d78a3eb93781652cb1f1'),
    // https://hub.docker.com/_/busybox#supported-tags-and-respective-dockerfile-links
    busybox: $.new(registry='docker.io', name='busybox', version='1.37.0'),
    driverRegistrar: $['csi-node-driver-registrar'],
    // https://github.com/democratic-csi/csi-grpc-proxy/releases/latest
    csiProxy: $.new(registry='docker.io', name='democraticcsi/csi-grpc-proxy', version='v0.5.7'),
  },
} +
{
  // From charts/alloy
  // See https://artifacthub.io/packages/helm/grafana/alloy?modal=values
  // https://github.com/grafana/alloy/releases/latest
  alloy: $.new(registry='docker.io', name='grafana/alloy', version='v1.11.3'),
  // https://github.com/prometheus-operator/prometheus-operator/releases/latest
  // https://github.com/prometheus-operator/prometheus-operator/pkgs/container/prometheus-config-reloader
  'prometheus-config-reloader': $.new(registry='ghcr.io', name='prometheus-operator/prometheus-config-reloader', version='v0.86.2'),
} +
{
  // https://github.com/grafana/rollout-operator/releases/latest
  grafana_rollout_operator: $.new(name='grafana/rollout-operator', version='v0.32.0'),
  // https://github.com/memcached/memcached/tags
  memcached: $.new(name='memcached', version='1.6.39-alpine'),
  // See https://github.com/prometheus/memcached_exporter/releases/latest
  memcachedExporter: $.new(name='prom/memcached-exporter', version='v0.15.3'),

}
{
  // https://github.com/grafana/loki/releases/latest
  // See https://github.com/grafana/loki/blob/main/production/ksonnet/loki/images.libsonnet
  // See https://github.com/grafana/loki/blob/main/production/ksonnet/loki/rollout-operator.libsonnet
  loki:: {
    loki: $.new(name='grafana/loki', version='3.5.8'),
    memcached: $.memcached,
    memcachedExporter: $.memcachedExporter,
    rollout_operator: $.grafana_rollout_operator,
  },
} +
{
  // https://github.com/grafana/mimir/releases/latest
  // See https://github.com/grafana/mimir/blob/main/operations/mimir/images.libsonnet
  // TODO: Upgrade to 3.0: https://github.com/grafana/mimir/releases/tag/mimir-3.0.0
  mimir:: {
    mimir: $.new(name='grafana/mimir', version='2.17.2'),
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
  'local-path-provisioner': $.new(name='rancher/local-path-provisioner', version='v0.0.32'),
} +
{
  // https://artifacthub.io/packages/helm/external-secrets-operator/external-secrets?modal=values

  // https://github.com/external-secrets/external-secrets/releases/latest
  'external-secrets': $.new(registry='oci.external-secrets.io', name='external-secrets/external-secrets', version='v1.0.0'),
  // https://github.com/external-secrets/bitwarden-sdk-server/releases/latest
  'bitwarden-sdk-server': $.new(registry='ghcr.io', name='external-secrets/bitwarden-sdk-server', version='v0.5.0'),
} +
{
  // images/qolsysgw/Dockerfile
  // https://github.com/xaf/qolsysgw/releases/latest
  // https://github.com/AppDaemon/appdaemon/releases/latest
  qolsysgw: $.new(name='nlowe/qolsysgw', version='v1.6.2-appdaemon4.5.12'),
}
