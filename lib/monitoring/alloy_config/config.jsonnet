local alloy = import 'github.com/grafana/alloy/operations/alloy-syntax-jsonnet/main.libsonnet';

alloy.manifestAlloy(
  (import 'metrics.jsonnet') +
  (import 'logs.jsonnet') +
  {
    [alloy.block('logging')]: {
      level: 'info',
      format: 'logfmt',
    },
  }
)
