local k = import 'k.libsonnet';
local g = (import 'github.com/jsonnet-libs/gateway-api-libsonnet/1.1/main.libsonnet').gateway;

local image = import 'images.libsonnet';

{
  grafana: {
    local this = self,

    labels:: { app: 'grafana' },

    local svc = k.core.v1.service,
    local port = k.core.v1.servicePort,
    service: {
      app:
        svc.new('grafana', this.labels, [
          port.withName('http') +
          port.withPort(3000) +
          port.withTargetPort(3000),
        ]) +
        svc.metadata.withNamespace($.namespace.metadata.name) +
        svc.metadata.withLabels(this.labels),

      headless:
        this.service.app +
        svc.metadata.withName('grafana-headless') +
        svc.spec.withClusterIP('None'),
    },

    local container = k.core.v1.container,
    local mount = k.core.v1.volumeMount,
    container::
      image.forContainer('grafana') +
      // TODO: Tune resources
      container.resources.withRequests({ memory: '4Gi' }) +
      container.resources.withLimits({ memory: '4Gi' }) +
      container.withPorts([{ containerPort: 3000 }]) +
      container.readinessProbe.withFailureThreshold(3) +
      container.readinessProbe.httpGet.withPath('/robots.txt') +
      container.readinessProbe.httpGet.withPort(3000) +
      container.readinessProbe.httpGet.withScheme('HTTP') +
      container.readinessProbe.withInitialDelaySeconds(10) +
      container.readinessProbe.withPeriodSeconds(30) +
      container.readinessProbe.withSuccessThreshold(1) +
      container.readinessProbe.withTimeoutSeconds(2) +
      container.livenessProbe.withFailureThreshold(3) +
      container.livenessProbe.withInitialDelaySeconds(30) +
      container.livenessProbe.withPeriodSeconds(10) +
      container.livenessProbe.withSuccessThreshold(1) +
      container.livenessProbe.tcpSocket.withPort(3000) +
      container.livenessProbe.withTimeoutSeconds(1) +
      container.withVolumeMounts([
        mount.withMountPath('/var/lib/grafana') +
        mount.withName('data'),
      ]),

    local pvc = k.core.v1.persistentVolumeClaim,
    pvcTemplate::
      pvc.new('data') +
      pvc.spec.withAccessModes(['ReadWriteOnce']) +
      pvc.spec.resources.withRequests({ storage: '10Gi' }),

    local sts = k.apps.v1.statefulSet,
    local volume = k.core.v1.volume,
    statefulSet:
      sts.new('grafana', 1, [self.container], [self.pvcTemplate], null) +
      sts.metadata.withNamespace($.namespace.metadata.name) +
      sts.metadata.withLabels(self.labels) +
      sts.spec.withServiceName(self.service.headless.metadata.name) +
      sts.spec.selector.withMatchLabels(self.labels) +
      sts.spec.template.metadata.withLabels(self.labels) +
      sts.spec.template.spec.securityContext.withFsGroup(472) +
      sts.spec.template.spec.securityContext.withSupplementalGroups([0]),

    local route = g.v1.httpRoute,
    local rule = route.spec.rules,
    route:
      route.new('grafana') +
      route.metadata.withNamespace($.namespace.metadata.name) +
      $._config.caddy.gateway.route() +
      route.spec.withHostnames(['grafana.home.nlowe.dev']) +
      route.spec.withRules([
        rule.withBackendRefs([
          rule.backendRefs.withName($.grafana.service.app.metadata.name) +
          rule.backendRefs.withNamespace($.grafana.service.app.metadata.namespace) +
          rule.backendRefs.withPort(3000),
        ]),
      ]),
  },
}
