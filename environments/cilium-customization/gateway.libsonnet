local cm = import 'github.com/jsonnet-libs/cert-manager-libsonnet/1.15/main.libsonnet';
local g = (import 'github.com/jsonnet-libs/gateway-api-libsonnet/1.2/main.libsonnet').gateway;

{
  gateway+: {
    labels:: { app: 'cilium-gateway' },

    crds: [
      std.parseYaml((importstr 'github.com/kubernetes-sigs/gateway-api/config/crd/standard/gateway.networking.k8s.io_gatewayclasses.yaml')),
      std.parseYaml((importstr 'github.com/kubernetes-sigs/gateway-api/config/crd/standard/gateway.networking.k8s.io_gateways.yaml')),
      std.parseYaml((importstr 'github.com/kubernetes-sigs/gateway-api/config/crd/standard/gateway.networking.k8s.io_httproutes.yaml')),
      std.parseYaml((importstr 'github.com/kubernetes-sigs/gateway-api/config/crd/standard/gateway.networking.k8s.io_referencegrants.yaml')),
      std.parseYaml((importstr 'github.com/kubernetes-sigs/gateway-api/config/crd/standard/gateway.networking.k8s.io_grpcroutes.yaml')),
      std.parseYaml((importstr 'github.com/kubernetes-sigs/gateway-api/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml')),
    ],

    local cert = cm.nogroup.v1.certificate,
    cert:
      cert.new('homelab-tls') +
      cert.metadata.withNamespace($._config.cilium.namespace) +
      cert.spec.withSecretName('homelab-tls') +
      cert.spec.withDnsNames([
        'home.nlowe.dev',
        '*.home.nlowe.dev',
      ]) +
      $._config.letsEncrypt.issuer.ref(),

    local gateway = g.v1.gateway,
    local listener = gateway.spec.listeners,
    def:
      gateway.new($._config.cilium.gateway.name) +
      gateway.metadata.withNamespace($._config.cilium.namespace) +
      gateway.metadata.withLabels($.gateway.labels) +
      gateway.spec.withGatewayClassName($._config.cilium.gateway.class) +
      gateway.spec.infrastructure.withLabels($._config.cilium.bgp.labels) +
      gateway.spec.withAddresses([
        gateway.spec.addresses.withType('IPAddress') +
        gateway.spec.addresses.withValue('10.200.200.10'),
      ]) +
      gateway.spec.withListeners([
        listener.withName('http') +
        listener.withProtocol('HTTP') +
        listener.withPort(80) +
        listener.allowedRoutes.namespaces.withFrom('All'),

        listener.withName('https') +
        listener.withProtocol('HTTPS') +
        listener.withPort(443) +
        listener.allowedRoutes.namespaces.withFrom('All') +
        listener.withHostname('*.home.nlowe.dev') +
        listener.tls.withCertificateRefs([
          listener.tls.certificateRefs.withKind('Secret') +
          listener.tls.certificateRefs.withName($.gateway.cert.spec.secretName),
        ]),
      ]),

    local route = g.v1.httpRoute,
    local routeRule = route.spec.rules,
    httpToHttpsRedirect:
      route.new('cilium-https-redirect') +
      route.metadata.withNamespace($._config.cilium.namespace) +
      route.spec.withParentRefs([
        {
          name: $.gateway.def.metadata.name,
          namespace: $.gateway.def.metadata.namespace,
          sectionName: 'http',
        },
      ]) +
      route.spec.withHostnames([]) +
      route.spec.withRules([
        routeRule.withFilters([
          routeRule.filters.withType('RequestRedirect') +
          routeRule.filters.requestRedirect.withScheme('https') +
          routeRule.filters.requestRedirect.withPort(443),
        ]),
      ]),
  },
}
