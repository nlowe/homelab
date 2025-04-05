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
  caddy: $.new(registry='ghcr.io', name='caddyserver/gateway', version='caddy-2.8.4'),
  'caddy-gateway': $.new(registry='ghcr.io', name='caddyserver/gateway', version='v0.1.0'),
  'code-server': $.new(name='linuxserver/code-server', version='4.98.0'),
  cloudflared: $.new(name='cloudflare/cloudflared', version='2025.1.0'),
  esphome: $.new(registry='ghcr.io', name='esphome/esphome', version='2025.2.2'),
  grafana: $.new(name='grafana/grafana', version='11.5.0'),
  'home-assistant': $.new(registry='ghcr.io', name='home-assistant/home-assistant', version='2025.3.1'),
  'kube-rbac-proxy': $.new(registry='quay.io', name='brancz/kube-rbac-proxy', version='v0.17.1@sha256:89d0be6da831f45fb53e7e40d216555997ccf6e27d66f62e50eb9a69ff9c9801'),
  'kube-state-metrics': $.new(registry='registry.k8s.io', name='kube-state-metrics/kube-state-metrics', version='v2.15.0'),
  'unifi-exporter': $.new(registry='ghcr.io', name='unpoller/unpoller', version='v2.14.1'),
  'zwave-js-ui': $.new(name='zwavejs/zwave-js-ui', version='9.32.0'),
} +
{
  // From charts/cert-manager
  // See https://artifacthub.io/packages/helm/cert-manager/cert-manager?modal=values
  ['cert-manager-%s' % name]: $.new(registry='quay.io', name='jetstack/cert-manager-%s' % name, version='v1.16.3')
  for name in ['controller', 'webhook', 'cainjector', 'acmesolver', 'startupapicheck']
} +
{
  // From charts/cert-manager-csi-driver
  // See https://artifacthub.io/packages/helm/cert-manager/cert-manager-csi-driver?modal=values
  'cert-manager-csi-driver': $.new(registry='quay.io', name='jetstack/cert-manager-csi-driver', version='v0.10.2'),
  'csi-node-driver-registrar': $.new(registry='registry.k8s.io', name='sig-storage/csi-node-driver-registrar', version='v2.12.0'),
  'sig-storage-livenessprobe': $.new(registry='registry.k8s.io', name='sig-storage/livenessprobe', version='v2.12.0'),
} +
{
  // From charts/democratic-csi
  // See https://artifacthub.io/packages/helm/democratic-csi/democratic-csi?modal=values
  democratic_csi:: {
    externalAttacher: $.new(registry='registry.k8s.io', name='sig-storage/csi-attacher', version='v4.4.0'),
    externalProvisioner: $.new(registry='registry.k8s.io', name='sig-storage/csi-provisioner', version='v3.6.0'),
    externalResizer: $.new(registry='registry.k8s.io', name='sig-storage/csi-resizer', version='v1.9.0'),
    externalSnapshotter: $.new(registry='registry.k8s.io', name='sig-storage/csi-snapshotter', version='v6.3.0'),
    externalHealthMonitorController: $.new(registry='registry.k8s.io', name='sig-storage/csi-external-health-monitor-controller', version='v0.14.0'),
    driver: $.new(registry='docker.io', name='democraticcsi/democratic-csi', version='latest'),  // TODO: Pick a version
    busybox: $.new(registry='docker.io', name='busybox', version='1.32.0'),
    driverRegistrar: $.new(registry='registry.k8s.io', name='sig-storage/csi-node-driver-registrar', version='v2.9.0'),
    csiProxy: $.new(registry='docker.io', name='democraticcsi/csi-grpc-proxy', version='v0.5.6'),
  },
} +
{
  // From charts/alloy
  // See https://artifacthub.io/packages/helm/grafana/alloy?modal=values
  alloy: $.new(registry='docker.io', name='grafana/alloy', version='v1.6.1'),
  'prometheus-config-reloader': $.new(registry='quay.io', name='prometheus-operator/prometheus-config-reloader', version='v0.81.0'),
} +
{
  // See https://github.com/grafana/loki/blob/main/production/ksonnet/loki/images.libsonnet
  // See https://github.com/grafana/loki/blob/main/production/ksonnet/loki/rollout-operator.libsonnet
  loki:: {
    loki: $.new(name='grafana/loki', version='3.4.2'),
    memcached: $.new(name='memcached', version='1.5.17-alpine'),
    memcachedExporter: $.new(name='prom/memcached-exporter', version='v0.11.3'),
    rollout_operator: $.new(name='grafana/rollout-operator', version='v0.1.1'),
  },
} +
{
  // See https://github.com/grafana/mimir/blob/main/operations/mimir/images.libsonnet
  mimir:: {
    mimir: $.new(name='grafana/mimir', version='2.15.0'),
    memcached: $.new(name='memcached', version='1.6.28-alpine'),
    memcachedExporter: $.new(name='prom/memcached-exporter', version='v0.15.0'),
    query_tee: $.new(name='grafana/query-tee', version=self.mimir.version),
    continuous_test: $.new(name='grafana/mimir-continuous-test', version=self.mimir.version),
    rollout_operator: $.new(name='grafana/rollout-operator', version='v0.20.0'),
  },
} +
{
  // See https://github.com/rancher/local-path-provisioner/blob/master/deploy/local-path-storage.yaml
  'local-path-provisioner': $.new(name='rancher/local-path-provisioner', version='v0.0.31'),
}
