local k = import 'k.libsonnet';

local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local helm = tk.helm.new(std.thisFile);

local cm = import 'github.com/jsonnet-libs/cert-manager-libsonnet/1.15/main.libsonnet';
local issuer = cm.nogroup.v1.clusterIssuer;
local cf = issuer.spec.acme.solvers.dns01.cloudflare;

{
  _config+:: {
    certManager+: {
      crds: {
        enabled: true,
        keep: true,
      },

      prometheus: {
        enabled: true,

        podmonitor: {
          enabled: true,
        },
      },
    },
  },

  certManager: {
    namespace: k.core.v1.namespace.new('cert-manager'),

    manifests: helm.template('cert-manager', '../charts/cert-manager', {
      namespace: $.certManager.namespace.metadata.name,
      values: $._config.certManager,
    }),

    csiDriver: helm.template('cert-manager-csi-driver', '../charts/cert-manager-csi-driver', {
      namespace: $.certManager.namespace.metadata.name,
    }),

    issuer:
      issuer.new('lets-encrypt') +
      issuer.metadata.withNamespace($.certManager.namespace.metadata.name) +
      issuer.spec.acme.withEmail('nathan@nlowe.dev') +
      issuer.spec.acme.privateKeySecretRef.withName('lets-encrypt') +
      issuer.spec.acme.withServer('https://acme-v02.api.letsencrypt.org/directory') +
      issuer.spec.acme.withSolvers([
        // TODO: Get this from vault and codify
        cf.apiTokenSecretRef.withName('cloudflare-api-token') +
        cf.apiTokenSecretRef.withKey('api-token') +
        issuer.spec.acme.solvers.selector.withDnsZones('nlowe.dev'),
      ]),
  },
}
