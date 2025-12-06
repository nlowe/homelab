local prom = import 'github.com/jsonnet-libs/prometheus-operator-libsonnet/0.83/main.libsonnet';

local image = (import 'images.libsonnet')['kube-state-metrics'];

{
  kubeStateMetrics: (import 'github.com/kubernetes/kube-state-metrics/jsonnet/kube-state-metrics/kube-state-metrics.libsonnet') {
    name:: 'kube-state-metrics',
    namespace:: $.namespace.metadata.name,
    version:: std.lstripChars(image.version, 'v'),
    image:: image.ref(),

    local pm = prom.monitoring.v1.podMonitor,
    local relabel = prom.monitoring.v1.podMonitor.spec.podMetricsEndpoints.metricRelabelings,
    podMonitor:
      pm.new('kube-state-metrics') +
      pm.metadata.withNamespace($.namespace.metadata.name) +
      pm.spec.withPodMetricsEndpoints([
        pm.spec.podMetricsEndpoints.withPort('http-metrics') +
        pm.spec.podMetricsEndpoints.withMetricRelabelings([
          // Re-map exported_ labels
          relabel.withAction('labelmap') +
          relabel.withRegex('exported_(.+)') +
          relabel.withReplacement('$1'),

          relabel.withAction('labeldrop') +
          relabel.withRegex('exported_.+'),
        ]),

        pm.spec.podMetricsEndpoints.withPort('telemetry'),
      ]) +
      pm.spec.selector.withMatchLabels($.kubeStateMetrics.deployment.spec.template.metadata.labels),
  },
}
