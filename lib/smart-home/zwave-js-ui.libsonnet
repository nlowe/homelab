local k = import 'k.libsonnet';
local g = (import 'github.com/jsonnet-libs/gateway-api-libsonnet/1.1/main.libsonnet').gateway;

{
  _config+:: {
    smartHome+: {
      zjs: {

      },
    },
  },

  smartHome+: {
    zjs: {
      local this = self,

      labels:: { app: 'zwave-js-ui' },

      local svc = k.core.v1.service,
      local port = k.core.v1.servicePort,
      service: {
        app:
          svc.new('zwave-js-ui', this.labels, [
            port.withName('http') +
            port.withPort(80) +
            port.withTargetPort('http'),

            port.withName('websocket') +
            port.withPort(3000) +
            port.withTargetPort('websocket'),
          ]) +
          svc.metadata.withNamespace($.smartHome.namespace.metadata.name) +
          svc.metadata.withLabels(this.labels),

        headless:
          this.service.app +
          svc.metadata.withName('zwave-js-ui-headless') +
          svc.spec.withClusterIP('None'),
      },

      local container = k.core.v1.container,
      local mount = k.core.v1.volumeMount,
      container::
        container.new('zwave', 'zwavejs/zwave-js-ui:9.30.1') +
        container.withPorts([
          { containerPort: 8091, name: 'http', protocol: 'TCP' },
          { containerPort: 3000, name: 'websocket', protocol: 'TCP' },
        ]) +
        // TODO: Tune resources
        container.withResourcesLimits('1', '512Mi') +
        container.withResourcesRequests('1', '400Mi') +
        container.livenessProbe.withFailureThreshold(10) +
        container.livenessProbe.httpGet.withHttpHeaders([{ name: 'Accept', value: 'text/plain' }]) +
        container.livenessProbe.httpGet.withPath('/health') +
        container.livenessProbe.httpGet.withPort('http') +
        container.livenessProbe.withInitialDelaySeconds(30) +
        container.livenessProbe.withPeriodSeconds(10) +
        container.livenessProbe.withSuccessThreshold(1) +
        container.livenessProbe.withTimeoutSeconds(1) +
        container.withVolumeMounts([
          mount.withMountPath('/usr/src/app/store') +
          mount.withName('data'),

          // TODO: Codify settings.json
        ]),

      local pvc = k.core.v1.persistentVolumeClaim,
      pvcTemplate::
        pvc.new('data') +
        pvc.spec.withAccessModes(['ReadWriteOnce']) +
        pvc.spec.resources.withRequests({ storage: '1Gi' }),

      local sts = k.apps.v1.statefulSet,
      local volume = k.core.v1.volume,
      statefulSet:
        sts.new('zwave-js-ui', 1, [self.container], [self.pvcTemplate], null) +
        sts.metadata.withNamespace($.smartHome.namespace.metadata.name) +
        sts.metadata.withLabels(self.labels) +
        sts.spec.withServiceName(self.service.headless.metadata.name) +
        sts.spec.selector.withMatchLabels(self.labels) +
        sts.spec.template.metadata.withLabels(self.labels),

      local route = g.v1.httpRoute,
      local rule = route.spec.rules,
      route:
        route.new('zwave-js-ui') +
        route.metadata.withNamespace($.smartHome.namespace.metadata.name) +
        route.spec.withParentRefs([
          route.spec.parentRefs.withName($.caddy.gateway.def.metadata.name) +
          route.spec.parentRefs.withNamespace($.caddy.gateway.def.metadata.namespace),
        ]) +
        route.spec.withHostnames(['zwave-js-ui.home.nlowe.dev']) +
        route.spec.withRules([
          rule.withBackendRefs([
            rule.backendRefs.withName($.smartHome.zjs.service.app.metadata.name) +
            rule.backendRefs.withNamespace($.smartHome.zjs.service.app.metadata.namespace) +
            rule.backendRefs.withPort(80),
          ]),
        ]),
    },
  },
}
