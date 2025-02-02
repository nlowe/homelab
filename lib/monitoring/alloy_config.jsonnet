local alloy = import 'github.com/grafana/alloy/operations/alloy-syntax-jsonnet/main.libsonnet';

alloy.manifestAlloy({
  local this = self,

  [alloy.block('logging')]: {
    level: 'info',
    format: 'logfmt',
  },

  // ========================
  // Inputs
  // ========================

  // Collect metrics for alloy itself
  [alloy.block('prometheus.exporter.self', 'alloy')]: {},
  [alloy.block('prometheus.scrape', 'alloy')]: {
    targets: alloy.expr('prometheus.exporter.self.alloy.targets'),
    forward_to: [this.relabel],

    job_name: 'alloy',

    scrape_interval: '10s',
    scrape_timeout: '10s',
  },

  // Node Exporter
  [alloy.block('prometheus.exporter.unix', 'node_exporter')]: {
    rootfs_path: '/host',
  },
  [alloy.block('prometheus.scrape', 'node_exporter')]: {
    targets: alloy.expr('prometheus.exporter.unix.node_exporter.targets'),
    forward_to: [this.relabel],

    job_name: 'node-exporter',

    scrape_interval: '10s',
    scrape_timeout: '10s',
  },

  // TODO: Logs

  // TODO: TrueNAS

  // TODO: PodMonitors (+ CRDs?)

  // ========================
  // Modify
  // ========================

  relabel:: alloy.expr('prometheus.relabel.local_node_label.receiver'),
  [alloy.block('prometheus.relabel', 'local_node_label')]: {
    forward_to: [alloy.expr('prometheus.remote_write.mimir.receiver')],

    [alloy.block('rule', index=0)]: {
      source_labels: ['__address__'],
      target_label: 'node',
      replacement: alloy.expr('sys.env("K8S_NODE_NAME")'),
    },
  },

  // ========================
  // Outputs
  // ========================

  // Mimir
  [alloy.block('prometheus.remote_write', 'mimir')]: {
    [alloy.block('endpoint')]: {
      url: 'http://mimir-write.mimir.svc.cluster.local:8080/api/v1/push',
      send_native_histograms: true,

      headers: {
        'X-Scope-OrgID': 'homelab',
      },
    },
  },

  // TODO: Loki

})
