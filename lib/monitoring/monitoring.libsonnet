local k = import 'k.libsonnet';

(import 'alloy.libsonnet') +
(import 'grafana.libsonnet') +
{
  monitoring+: {
    namespace: k.core.v1.namespace.new('monitoring'),
  },
}
