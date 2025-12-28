local k = import 'k.libsonnet';
local g = (import 'github.com/jsonnet-libs/gateway-api-libsonnet/1.2/main.libsonnet').gateway;
local prom = import 'github.com/jsonnet-libs/prometheus-operator-libsonnet/0.83/main.libsonnet';

local image = import 'images.libsonnet';

{
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
        svc.metadata.withNamespace($.namespace.metadata.name) +
        svc.metadata.withLabels(this.labels),

      headless:
        this.service.app +
        svc.metadata.withName('zwave-js-ui-headless') +
        svc.spec.withClusterIP('None'),
    },

    local container = k.core.v1.container,
    local mount = k.core.v1.volumeMount,
    container::
      image.forContainer('zwave-js-ui', container_name='zwave') +
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
    statefulSet:
      sts.new('zwave-js-ui', 1, [self.container], [self.pvcTemplate], null) +
      sts.metadata.withNamespace($.namespace.metadata.name) +
      sts.metadata.withLabels(self.labels) +
      sts.spec.withServiceName(self.service.headless.metadata.name) +
      sts.spec.selector.withMatchLabels(self.labels) +
      sts.spec.template.metadata.withLabels(self.labels) +
      sts.spec.template.spec.withHostNetwork(true) +
      sts.spec.template.spec.withDnsPolicy('ClusterFirstWithHostNet'),

    local pm = prom.monitoring.v1.podMonitor,
    podMonitor:
      pm.new('zwave-js-ui') +
      pm.metadata.withNamespace($.namespace.metadata.name) +
      pm.spec.withPodMetricsEndpoints([
        pm.spec.podMetricsEndpoints.withPort('http'),
      ]) +
      pm.spec.selector.withMatchLabels($.zjs.statefulSet.spec.template.metadata.labels),

    local route = g.v1.httpRoute,
    local rule = route.spec.rules,
    route:
      route.new('zwave-js-ui') +
      route.metadata.withNamespace($.namespace.metadata.name) +
      $._config.cilium.gateway.route() +
      route.spec.withHostnames(['zwave-js-ui.home.nlowe.dev']) +
      route.spec.withRules([
        rule.withBackendRefs([
          rule.backendRefs.withName($.zjs.service.app.metadata.name) +
          rule.backendRefs.withNamespace($.zjs.service.app.metadata.namespace) +
          rule.backendRefs.withPort(80),
        ]),
      ]),
  },
}
