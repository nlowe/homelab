local k = import 'k.libsonnet';

(import 'alloy.libsonnet') +
(import 'ksm.libsonnet') +
(import 'grafana.libsonnet') +
(import 'unifi_exporter.libsonnet') +
{
  monitoring+: {
    namespace: k.core.v1.namespace.new('monitoring'),

    prometheusOperator: {
      local manifests = (import 'github.com/prometheus-operator/prometheus-operator/jsonnet/prometheus-operator/prometheus-operator.libsonnet')({}),

      crd: {
        [k]: manifests[k]
        for k in std.objectFields(manifests)
        // https://github.com/prometheus-operator/prometheus-operator/blob/1d2dca5a93d50fe09d7662860f80448d2e37ff1a/jsonnet/prometheus-operator/prometheus-operator.libsonnet#L39
        if std.startsWith(k, '0') && std.endsWith(k, 'CustomResourceDefinition')
      },
    },
  },
}
