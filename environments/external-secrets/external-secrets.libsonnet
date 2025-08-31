local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local helm = tk.helm.new(std.thisFile);

local prom = import 'github.com/jsonnet-libs/prometheus-operator-libsonnet/0.77/main.libsonnet';

local image = import 'images.libsonnet';

{
  externalSecrets: {
    local this = self,

    labels:: { app: 'external-secrets' },

    helm_values:: {
      image: {
        repository: image['external-secrets'].repo(),
        tag: image['external-secrets'].version,
      },

      leaderElect: true,
      openshiftFinalizers: false,

      webhook: {
        image: this.helm_values.image,

        certManager: {
          enabled: true,

          cert: {
            issuerRef: {
              name: $.certs.issuer.metadata.name,
            },
          },
        },
      },

      certController: {
        image: this.helm_values.image,
      },
    },

    manifests: helm.template('external-secrets', '../../charts/external-secrets', {
      namespace: $.namespace.metadata.name,
      values: this.helm_values,
    }),

    podMonitors: {
      local pm = prom.monitoring.v1.podMonitor,
      local endpoint = pm.spec.podMetricsEndpoints,

      controller:
        pm.new('external-secrets') +
        pm.spec.withPodMetricsEndpoints([
          endpoint.withPort('metrics'),
        ]) +
        pm.spec.selector.withMatchLabels($.externalSecrets.manifests.deployment_external_secrets.spec.template.metadata.labels),

      webhook:
        pm.new('external-secrets-webhook') +
        pm.spec.withPodMetricsEndpoints([
          endpoint.withPort('metrics'),
        ]) +
        pm.spec.selector.withMatchLabels($.externalSecrets.manifests.deployment_external_secrets_webhook.spec.template.metadata.labels),
    },
  },
}
