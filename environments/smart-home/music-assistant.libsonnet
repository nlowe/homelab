local k = import 'k.libsonnet';
local g = (import 'github.com/jsonnet-libs/gateway-api-libsonnet/1.4/main.libsonnet').gateway;

local image = import 'images.libsonnet';

{
  musicAssistant: {
    local this = self,

    labels:: { app: 'music-assistant' },
    ports:: {
      http: 8095,
      'stream-server': 8097,
    },

    service: {
      local svc = k.core.v1.service,
      local port = k.core.v1.servicePort,

      app:
        svc.new('music-assistant', this.labels, [
          port.withName('http') +
          port.withPort(this.ports.http) +
          port.withTargetPort('http'),
        ]) +
        svc.metadata.withNamespace($.namespace.metadata.name),

      headless:
        this.service.app +
        svc.metadata.withName('certwarden-headless') +
        svc.spec.withClusterIP('None'),

      streamServer:
        svc.new('music-assistant-stream-server', this.labels, [
          port.withName('stream-server') +
          port.withPort(this.ports['stream-server']) +
          port.withTargetPort('stream-server'),
        ]) +
        $._config.cilium.bgp.serviceMixins.music_assistant_stream_server,
    },

    local container = k.core.v1.container,
    local env = k.core.v1.envVar,
    local mount = k.core.v1.volumeMount,
    container::
      image.forContainer('music-assistant') +
      container.withPorts([
        { containerPort: this.ports.http, name: 'http', protocol: 'TCP' },
        { containerPort: this.ports['stream-server'], name: 'stream-server', protocol: 'TCP' },
      ]) +
      container.withEnv([
        env.new('LOG_LEVEL', 'info'),
      ]) +
      container.withVolumeMounts([
        mount.withMountPath('/data') +
        mount.withName('data'),
      ]),

    local pvc = k.core.v1.persistentVolumeClaim,
    pvcTemplate::
      pvc.new('data') +
      pvc.spec.withAccessModes(['ReadWriteOnce']) +
      // TODO: how much data does this need?
      pvc.spec.resources.withRequests({ storage: '10Gi' }),

    local sts = k.apps.v1.statefulSet,
    statefulSet:
      sts.new('music-assistant', 1, [this.container], [this.pvcTemplate], null) +
      sts.metadata.withNamespace($.namespace.metadata.name) +
      sts.spec.withServiceName(this.service.headless.metadata.name) +
      sts.spec.selector.withMatchLabels(this.labels) +
      sts.spec.template.metadata.withLabels(this.labels) +
      sts.spec.template.spec.withHostNetwork(true) +
      sts.spec.template.spec.withDnsPolicy('ClusterFirstWithHostNet'),

    local route = g.v1.httpRoute,
    local rule = route.spec.rules,
    route:
      route.new('music-assistant') +
      route.metadata.withNamespace($.namespace.metadata.name) +
      $._config.cilium.gateway.route() +
      route.spec.withHostnames(['music-assistant.home.nlowe.dev']) +
      route.spec.withRules([
        rule.withBackendRefs([
          rule.backendRefs.withName(this.service.app.metadata.name) +
          rule.backendRefs.withNamespace(this.service.app.metadata.namespace) +
          rule.backendRefs.withPort(this.ports.http),
        ]),
      ]),
  },
}
