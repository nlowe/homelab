local k = import 'k.libsonnet';
local g = (import 'github.com/jsonnet-libs/gateway-api-libsonnet/1.4/main.libsonnet').gateway;

local image = import 'images.libsonnet';

(import 'homelab.libsonnet') +
{
  namespace: k.core.v1.namespace.new('bentopdf'),

  labels:: { app: 'bentopdf' },

  local svc = k.core.v1.service,
  local port = k.core.v1.servicePort,
  service:
    svc.new('bentopdf', $.labels, [
      port.withName('http') +
      port.withPort(8080) +
      port.withTargetPort('http'),
    ]) +
    svc.metadata.withNamespace($.namespace.metadata.name) +
    svc.metadata.withLabels($.labels),

  local container = k.core.v1.container,
  container::
    image.forContainer('bentopdf') +
    container.withPorts([
      { containerPort: 8080, name: 'http', protocol: 'TCP' },
    ]) +
    container.livenessProbe.httpGet.withPath('/') +
    container.livenessProbe.httpGet.withPort(8080) +
    container.livenessProbe.withFailureThreshold(3) +
    container.livenessProbe.withTimeoutSeconds(10) +
    container.livenessProbe.withPeriodSeconds(30),

  local deploy = k.apps.v1.deployment,
  deployment:
    deploy.new('bentopdf', 1, [$.container], $.labels) +
    deploy.metadata.withNamespace($.namespace.metadata.name) +
    deploy.metadata.withLabels($.labels),

  local route = g.v1.httpRoute,
  local rule = route.spec.rules,
  local filter = route.spec.rules.filters,
  local header = filter.responseHeaderModifier.add,
  route:
    route.new('bentopdf') +
    route.metadata.withNamespace($.namespace.metadata.name) +
    $._config.cilium.gateway.route() +
    route.spec.withHostnames(['pdf.home.nlowe.dev']) +
    route.spec.withRules([
      rule.withFilters([
        filter.withType('ResponseHeaderModifier') +
        filter.responseHeaderModifier.withAdd([
          header.withName('Cross-Origin-Opener-Policy') +
          header.withValue('same-origin'),

          header.withName('Cross-Origin-Embedder-Policy') +
          header.withValue('require-corp'),
        ]),
      ]) +
      rule.withBackendRefs([
        rule.backendRefs.withName($.service.metadata.name) +
        rule.backendRefs.withNamespace($.service.metadata.namespace) +
        rule.backendRefs.withPort(8080),
      ]),
    ]),
}
