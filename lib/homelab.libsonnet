local k = import 'k.libsonnet';

local cm = import 'github.com/jsonnet-libs/cert-manager-libsonnet/1.15/main.libsonnet';
local cert = cm.nogroup.v1.certificate;
local issuer = cm.nogroup.v1.clusterIssuer;

local es = import 'github.com/nlowe/external-secrets-libsonnet/0.18/main.libsonnet';
local clusterSecretStore = es.nogroup.v1.clusterSecretStore;
local externalSecret = es.nogroup.v1.externalSecret;

local g = (import 'github.com/jsonnet-libs/gateway-api-libsonnet/1.1/main.libsonnet').gateway;

{
  _config+:: {
    caddy: {
      namespace: 'caddy-system',

      gateway: {
        name: 'caddy',

        local route = g.v1.httpRoute,
        route():
          route.spec.withParentRefs([
            route.spec.parentRefs.withName($._config.caddy.gateway.name) +
            route.spec.parentRefs.withNamespace($._config.caddy.namespace),
          ]),
      },
    },

    cilium+: {
      bgp+: {
        labels:: { advertise: 'bgp' },

        local svc = k.core.v1.service,
        loadBalancerMixin(ips)::
          svc.metadata.withAnnotationsMixin({
            'lbipam.cilium.io/ips': std.join(',', if std.isArray(ips) then ips else [ips]),
          }) +
          svc.metadata.withLabelsMixin($._config.cilium.bgp.labels) +
          svc.spec.withType('LoadBalancer') +
          svc.spec.withLoadBalancerClass('io.cilium/bgp-control-plane') +
          svc.spec.withExternalTrafficPolicy('Local') +
          svc.spec.withInternalTrafficPolicy('Local'),

        serviceMixins:: {
          caddy: $._config.cilium.bgp.loadBalancerMixin('10.200.200.10'),
          alloy_syslog: $._config.cilium.bgp.loadBalancerMixin('10.200.200.11'),
        },
      },
    },

    letsEncrypt: {
      issuer: {
        kind: issuer.new('').kind,
        name: 'lets-encrypt',

        ref():
          cert.spec.issuerRef.withKind($._config.letsEncrypt.issuer.kind) +
          cert.spec.issuerRef.withName($._config.letsEncrypt.issuer.name),
      },
    },

    externalSecret: {
      kind: clusterSecretStore.new('').kind,
      storeName: 'bitwarden',

      new(name, namespace, refreshPolicy='OnChange')::
        externalSecret.new(name) +
        externalSecret.metadata.withNamespace(namespace) +
        externalSecret.spec.withRefreshPolicy(refreshPolicy) +
        externalSecret.spec.secretStoreRef.withKind($._config.externalSecret.kind) +
        externalSecret.spec.secretStoreRef.withName($._config.externalSecret.storeName),
    },
  },
}
