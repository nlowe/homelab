local k = import 'k.libsonnet';

local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local helm = tk.helm.new(std.thisFile);

local cm = import 'github.com/jsonnet-libs/cert-manager-libsonnet/1.15/main.libsonnet';
local issuer = cm.nogroup.v1.clusterIssuer;
local cf = issuer.spec.acme.solvers.dns01.cloudflare;

local image = import 'images.libsonnet';

(import 'homelab.libsonnet') +
{
  _config+:: {
    helm_values:: {
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

      // Codify Images
      image: {
        image:: image['cert-manager-controller'],

        repository: self.image.repo(),
        tag: self.image.version,
      },

      webhook: {
        image: {
          image:: image['cert-manager-webhook'],

          repository: self.image.repo(),
          tag: self.image.version,
        },
      },

      cainjector: {
        image: {
          image:: image['cert-manager-cainjector'],

          repository: self.image.repo(),
          tag: self.image.version,
        },
      },

      acmesolver: {
        image: {
          image:: image['cert-manager-acmesolver'],

          repository: self.image.repo(),
          tag: self.image.version,
        },
      },

      startupapicheck: {
        image: {
          image:: image['cert-manager-startupapicheck'],

          repository: self.image.repo(),
          tag: self.image.version,
        },
      },
    },
  },

  namespace: k.core.v1.namespace.new('cert-manager'),

  manifests: helm.template('cert-manager', '../../charts/cert-manager', {
    namespace: $.namespace.metadata.name,
    values: $._config.helm_values,
  }),

  csiDriver: helm.template('cert-manager-csi-driver', '../../charts/cert-manager-csi-driver', {
    namespace: $.namespace.metadata.name,
    values: {
      image: {
        image:: image['cert-manager-csi-driver'],

        repository: self.image.repo(),
        tag: self.image.version,
      },
      nodeDriverRegistrarImage: {
        image:: image['csi-node-driver-registrar'],

        repository: self.image.repo(),
        tag: self.image.version,
      },
      livenessProbeImage: {
        image:: image['sig-storage-livenessprobe'],

        repository: self.image.repo(),
        tag: self.image.version,
      },
    },
  }),

  issuer:
    issuer.new($._config.letsEncrypt.issuer.name) +
    issuer.metadata.withNamespace($.namespace.metadata.name) +
    issuer.spec.acme.withEmail('nathan@nlowe.dev') +
    issuer.spec.acme.privateKeySecretRef.withName('lets-encrypt') +
    issuer.spec.acme.withServer('https://acme-v02.api.letsencrypt.org/directory') +
    issuer.spec.acme.withSolvers([
      // TODO: Get this from vault and codify
      cf.apiTokenSecretRef.withName('cloudflare-api-token') +
      cf.apiTokenSecretRef.withKey('api-token') +
      issuer.spec.acme.solvers.selector.withDnsZones('nlowe.dev'),
    ]),
}
