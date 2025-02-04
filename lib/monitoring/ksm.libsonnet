local prom = import 'github.com/jsonnet-libs/prometheus-operator-libsonnet/0.77/main.libsonnet';

{
  monitoring+: {
    kubeStateMetrics: (import 'github.com/kubernetes/kube-state-metrics/jsonnet/kube-state-metrics/kube-state-metrics.libsonnet') {
      name:: 'kube-state-metrics',
      namespace:: $.monitoring.namespace.metadata.name,
      version:: '2.15.0',
      image:: 'registry.k8s.io/kube-state-metrics/kube-state-metrics:v%s' % $.monitoring.kubeStateMetrics.version,

      local pm = prom.monitoring.v1.podMonitor,
      podMonitor:
        pm.new('kube-state-metrics') +
        pm.metadata.withNamespace($.monitoring.namespace.metadata.name) +
        pm.spec.withPodMetricsEndpoints([
          pm.spec.podMetricsEndpoints.withPort('http-metrics'),
          pm.spec.podMetricsEndpoints.withPort('telemetry'),
        ]) +
        pm.spec.selector.withMatchLabels($.monitoring.kubeStateMetrics.deployment.spec.template.metadata.labels),
    },
  },
}
