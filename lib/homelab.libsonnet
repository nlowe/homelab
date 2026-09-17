local k = import 'k.libsonnet';

local cm = import 'github.com/jsonnet-libs/cert-manager-libsonnet/1.19/main.libsonnet';
local cert = cm.nogroup.v1.certificate;
local issuer = cm.nogroup.v1.clusterIssuer;

local es = import 'github.com/jsonnet-libs/external-secrets-libsonnet/1.1/main.libsonnet';
local clusterSecretStore = es.nogroup.v1.clusterSecretStore;
local externalSecret = es.nogroup.v1.externalSecret;

local g = (import 'github.com/jsonnet-libs/gateway-api-libsonnet/1.4/main.libsonnet').gateway;

{
  _config+:: {
    cilium+: {
      namespace: 'kube-system',

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
          cilium_gateway: $._config.cilium.bgp.loadBalancerMixin('10.200.200.10'),
          alloy_syslog: $._config.cilium.bgp.loadBalancerMixin('10.200.200.11'),
          vernemq_mqtts: $._config.cilium.bgp.loadBalancerMixin('10.200.200.12'),
        },
      },

      gateway: {
        name: 'cilium',
        class: 'cilium',

        local route = g.v1.httpRoute,
        route():
          route.spec.withParentRefs([
            route.spec.parentRefs.withName($._config.cilium.gateway.name) +
            route.spec.parentRefs.withNamespace($._config.cilium.namespace),
          ]),
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

    media: {
      uid: 3000,
      gid: 3000,

      server: 'storage.home.nlowe.dev',

      mount: {
        options:: [
          // Latest version, includes server side clone & copy, application IO advice, sparse files, space reservation,
          // application data block, labeled NFS, and more.
          'vers=4.2',

          // Disable access timestamps to reduce latencyg
          'noatime',

          // Use new non-privileged TCP Ports when a connection is re-established
          'noresvport',

          // Maximize receive and send buffers for increased throughput
          'rsize=1048576',
          'wsize=1048576',

          // Retry immediately on timeouts
          'hard',
          // 60 second timeout
          'timeo=600',

          // Retry twice before attempting other recovery actions
          'retrans=2',
        ],

        local volume = k.core.v1.volume,
        forKind(kind)::
          volume.withName(kind) +
          volume.nfs.withServer($._config.media.server) +
          volume.nfs.withPath($._config.media.mount[kind]),

        'k8s-generic-nfs': '/mnt/data/k8s/nfs',
        photos: '/mnt/data/media/photos',
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
