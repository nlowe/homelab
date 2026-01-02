local alloy = import 'github.com/grafana/alloy/operations/alloy-syntax-jsonnet/main.libsonnet';

{
  local tenant_id = 'homelab',

  // PrometheusRules
  [alloy.block('mimir.rules.kubernetes', 'local')]: {
    address: 'http://ruler.mimir.svc.cluster.local.:8080',
    tenant_id: tenant_id,
    external_labels: {
      cluster: tenant_id,
    },
  },
}
