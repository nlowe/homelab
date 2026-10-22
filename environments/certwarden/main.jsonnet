local k = import 'k.libsonnet';
local g = (import 'github.com/jsonnet-libs/gateway-api-libsonnet/1.4/main.libsonnet').gateway;

local image = import 'images.libsonnet';

(import 'homelab.libsonnet') +
{
  namespace: k.core.v1.namespace.new('certwarden'),

  labels:: { app: 'certwarden' },
  ports:: {
    http: 4050,
    'acme-http01': 4060,
  },

  local svc = k.core.v1.service,
  local port = k.core.v1.servicePort,
  service: {
    app:
      svc.new('certwarden', $.labels, [
        port.withName('http') +
        port.withPort($.ports.http) +
        port.withTargetPort('http'),

        port.withName('acme-http01') +
        port.withPort($.ports['acme-http01']) +
        port.withTargetPort('acme-http01'),
      ]) +
      svc.metadata.withNamespace($.namespace.metadata.name) +
      svc.metadata.withLabels($.labels),

    headless:
      $.service.app +
      svc.metadata.withName('certwarden-headless') +
      svc.spec.withClusterIP('None'),
  },

  local container = k.core.v1.container,
  local mount = k.core.v1.volumeMount,
  container::
    image.forContainer('certwarden') +
    container.withPorts([
      { containerPort: $.ports.http, name: 'http', protocol: 'TCP' },
      { containerPort: $.ports['acme-http01'], name: 'acme-http01', protocol: 'TCP' },
    ]) +
    container.livenessProbe.httpGet.withPath('/certwarden/api/health') +
    container.livenessProbe.httpGet.withPort('http') +
    container.livenessProbe.withFailureThreshold(3) +
    container.livenessProbe.withPeriodSeconds(30) +
    container.livenessProbe.withTimeoutSeconds(10) +
    container.withVolumeMounts([
      mount.new('data', '/app/data'),
    ]),

  local pvc = k.core.v1.persistentVolumeClaim,
  pvcTemplate::
    pvc.new('data') +
    pvc.spec.withAccessModes(['ReadWriteOnce']) +
    // TODO: how much data does this need?
    pvc.spec.resources.withRequests({ storage: '10Gi' }),

  local sts = k.apps.v1.statefulSet,
  statefulSet:
    sts.new('certwarden', 1, [$.container], [$.pvcTemplate], null) +
    sts.metadata.withNamespace($.namespace.metadata.name) +
    sts.metadata.withLabels($.labels) +
    sts.spec.withServiceName($.service.headless.metadata.name) +
    sts.spec.selector.withMatchLabels($.labels) +
    sts.spec.template.metadata.withLabels($.labels),

  local route = g.v1.httpRoute,
  local rule = route.spec.rules,
  route:
    route.new('certwarden') +
    route.metadata.withNamespace($.namespace.metadata.name) +
    $._config.cilium.gateway.route() +
    route.spec.withHostnames(['certwarden.home.nlowe.dev']) +
    route.spec.withRules([
      rule.withBackendRefs([
        rule.backendRefs.withName($.service.app.metadata.name) +
        rule.backendRefs.withNamespace($.service.app.metadata.namespace) +
        rule.backendRefs.withPort($.ports.http),
      ]),
    ]),
}
