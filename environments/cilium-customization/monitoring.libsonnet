local prom = import 'github.com/jsonnet-libs/prometheus-operator-libsonnet/0.83/main.libsonnet';

{
  monitoring+: {
    local pm = prom.monitoring.v1.podMonitor,
    local endpoint = pm.spec.podMetricsEndpoints,

    daemonset:
      pm.new('cilium') +
      pm.spec.withPodMetricsEndpoints([
        endpoint.withPort('prometheus'),
        endpoint.withPort('hubble-metrics'),
      ]) +
      pm.spec.selector.withMatchLabels({
        'k8s-app': 'cilium',
        'app.kubernetes.io/name': 'cilium-agent',
      }),

    envoy:
      pm.new('cilium-envoy') +
      pm.spec.withPodMetricsEndpoints([
        endpoint.withPort('envoy-metrics'),
      ]) +
      pm.spec.selector.withMatchLabels({
        'k8s-app': 'cilium-envoy',
        'app.kubernetes.io/name': 'cilium-envoy',
      }),

    hubble_relay:
      pm.new('hubble-relay') +
      pm.spec.withPodMetricsEndpoints([
        endpoint.withPort('prometheus'),
      ]) +
      pm.spec.selector.withMatchLabels({
        'k8s-app': 'hubble-relay',
        'app.kubernetes.io/name': 'hubble-relay',
      }),

    operator:
      pm.new('cilium-operator') +
      pm.spec.withPodMetricsEndpoints([
        endpoint.withPort('prometheus'),
      ]) +
      pm.spec.selector.withMatchLabels({
        'app.kubernetes.io/name': 'cilium-operator',
      }),
  },
}
