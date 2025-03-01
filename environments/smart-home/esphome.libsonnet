local k = import 'k.libsonnet';
local g = (import 'github.com/jsonnet-libs/gateway-api-libsonnet/1.1/main.libsonnet').gateway;

{
  esphome: {
    local this = self,

    labels:: { app: 'esphome' },

    local svc = k.core.v1.service,
    local port = k.core.v1.servicePort,
    service: {
      app:
        svc.new('esphome', this.labels, [
          port.withName('http') +
          port.withPort(80) +
          port.withTargetPort('http'),

          port.withName('websocket') +
          port.withPort(3000) +
          port.withTargetPort('websocket'),
        ]) +
        svc.metadata.withNamespace($.namespace.metadata.name) +
        svc.metadata.withLabels(this.labels),

      headless:
        this.service.app +
        svc.metadata.withName('esphome-headless') +
        svc.spec.withClusterIP('None'),
    },

    local container = k.core.v1.container,
    local mount = k.core.v1.volumeMount,
    container::
      container.new('esphome', 'ghcr.io/esphome/esphome:2024.12.4') +
      container.withCommand(['esphome']) +
      container.withArgs(['dashboard', '/data']) +
      container.withPorts([
        { containerPort: 6052, name: 'http', protocol: 'TCP' },
      ]) +
      // TODO: Tune resources
      container.withVolumeMounts([
        mount.withMountPath('/data') +
        mount.withName('data'),
      ]),

    local pvc = k.core.v1.persistentVolumeClaim,
    pvcTemplate::
      pvc.new('data') +
      pvc.spec.withAccessModes(['ReadWriteOnce']) +
      pvc.spec.resources.withRequests({ storage: '25Gi' }),

    local sts = k.apps.v1.statefulSet,
    local volume = k.core.v1.volume,
    statefulSet:
      sts.new('esphome', 1, [self.container], [self.pvcTemplate], null) +
      sts.metadata.withNamespace($.namespace.metadata.name) +
      sts.metadata.withLabels(self.labels) +
      sts.spec.withServiceName(self.service.headless.metadata.name) +
      sts.spec.selector.withMatchLabels(self.labels) +
      sts.spec.template.metadata.withLabels(self.labels) +
      sts.spec.template.spec.withHostNetwork(true) +
      sts.spec.template.spec.withDnsPolicy('ClusterFirstWithHostNet') +
      sts.spec.template.spec.dnsConfig.withOptions([{ name: 'ndots', value: '1' }]),

    local route = g.v1.httpRoute,
    local rule = route.spec.rules,
    route:
      route.new('esphome') +
      route.metadata.withNamespace($.namespace.metadata.name) +
      $._config.caddy.gateway.route() +
      route.spec.withHostnames(['esp.home.nlowe.dev']) +
      route.spec.withRules([
        rule.withBackendRefs([
          rule.backendRefs.withName($.esphome.service.app.metadata.name) +
          rule.backendRefs.withNamespace($.esphome.service.app.metadata.namespace) +
          rule.backendRefs.withPort(80),
        ]),
      ]),
  },
}
