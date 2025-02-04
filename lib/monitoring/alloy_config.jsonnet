local alloy = import 'github.com/grafana/alloy/operations/alloy-syntax-jsonnet/main.libsonnet';

alloy.manifestAlloy({
  local this = self,

  local default_interval = '15s',
  local tenant_id = 'homelab',

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

    // Support native histograms by indicating support for PrometheusProto
    scrape_protocols: ['PrometheusProto', 'OpenMetricsText1.0.0', 'OpenMetricsText0.0.1', 'PrometheusText0.0.4'],

    scrape_interval: default_interval,
    scrape_timeout: default_interval,
  },

  // Node Exporter
  [alloy.block('prometheus.exporter.unix', 'node_exporter')]: {
    rootfs_path: '/host',
  },
  [alloy.block('prometheus.scrape', 'node_exporter')]: {
    targets: alloy.expr('prometheus.exporter.unix.node_exporter.targets'),
    forward_to: [this.relabel],

    job_name: 'node-exporter',

    // Support native histograms by indicating support for PrometheusProto
    scrape_protocols: ['PrometheusProto', 'OpenMetricsText1.0.0', 'OpenMetricsText0.0.1', 'PrometheusText0.0.4'],

    scrape_interval: default_interval,
    scrape_timeout: default_interval,
  },

  // Kubernetes Nodes
  [alloy.block('discovery.kubernetes', 'nodes')]: {
    role: 'node',
  },

  [alloy.block('discovery.relabel', 'k8s_node_cadvisor')]: {
    targets: alloy.expr('discovery.kubernetes.nodes.targets'),
    [alloy.block('rule', index=0)]: {
      action: 'labelmap',
      regex: '__meta_kubernetes_node_label_(.+)',
    },
    [alloy.block('rule', index=1)]: {
      action: 'replace',
      target_label: '__address__',
      replacement: 'kubernetes.default.svc.cluster.local.:443',
    },
    [alloy.block('rule', index=2)]: {
      action: 'replace',
      source_labels: ['__meta_kubernetes_node_name'],
      regex: '(.+)',
      target_label: '__metrics_path__',
      replacement: '/api/v1/nodes/${1}/proxy/metrics/cadvisor',
    },
  },

  [alloy.block('prometheus.scrape', 'cadvisor')]: {
    targets: alloy.expr('discovery.relabel.k8s_node_cadvisor.output'),
    forward_to: [this.mimir],

    honor_labels: true,
    scheme: 'https',
    bearer_token_file: '/var/run/secrets/kubernetes.io/serviceaccount/token',
    [alloy.block('tls_config')]: {
      ca_file: '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt',
    },

    // Support native histograms by indicating support for PrometheusProto
    scrape_protocols: ['PrometheusProto', 'OpenMetricsText1.0.0', 'OpenMetricsText0.0.1', 'PrometheusText0.0.4'],

    scrape_interval: default_interval,
    scrape_timeout: default_interval,
  },

  // TODO: Logs

  // TrueNAS
  [alloy.block('prometheus.scrape', 'truenas')]: {
    forward_to: [this.mimir],

    [alloy.block('clustering')]: {
      enabled: true,
    },

    targets: [
      { __address__: 'storage.home.nlowe.dev:9100', __metrics_path__: '/metrics', job: 'node-exporter', node: 'storage.home.nlowe.dev' },
      { __address__: 'minio.home.nlowe.dev:9000', __scheme__: 'https', __metrics_path__: '/minio/v2/metrics/node', job: 'minio/node', node: 'minio.home.nlowe.dev' },
      { __address__: 'minio.home.nlowe.dev:9000', __scheme__: 'https', __metrics_path__: '/minio/v2/metrics/bucket', job: 'minio/buckets', node: 'minio.home.nlowe.dev' },
    ],

    // Support native histograms by indicating support for PrometheusProto
    scrape_protocols: ['PrometheusProto', 'OpenMetricsText1.0.0', 'OpenMetricsText0.0.1', 'PrometheusText0.0.4'],

    scrape_interval: default_interval,
    scrape_timeout: default_interval,
  },

  // Pod Monitors
  // TODO: Is there a way to make this use native protos for native histograms?
  [alloy.block('prometheus.operator.podmonitors', 'all')]: {
    forward_to: [this.mimir],

    [alloy.block('clustering')]: {
      enabled: true,
    },

    [alloy.block('scrape')]: {
      default_scrape_interval: default_interval,
      default_scrape_timeout: default_interval,
    },

    // Inject Node Label
    [alloy.block('rule', index=0)]: {
      source_labels: ['__meta_kubernetes_pod_node_name'],
      target_label: 'node',
    },
  },

  // PrometheusRules
  [alloy.block('mimir.rules.kubernetes', 'local')]: {
    address: 'http://mimir-backend.mimir.svc.cluster.local.:8080',
    tenant_id: tenant_id,
    external_labels: {
      cluster: tenant_id,
    },
  },

  // ========================
  // Modify
  // ========================

  relabel:: alloy.expr('prometheus.relabel.local_node_label.receiver'),
  [alloy.block('prometheus.relabel', 'local_node_label')]: {
    forward_to: [this.mimir],

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
  mimir:: alloy.expr('prometheus.remote_write.mimir.receiver'),
  [alloy.block('prometheus.remote_write', 'mimir')]: {
    external_labels: {
      cluster: tenant_id,
    },

    [alloy.block('endpoint')]: {
      url: 'http://mimir-write.mimir.svc.cluster.local:8080/api/v1/push',
      send_native_histograms: true,

      headers: {
        'X-Scope-OrgID': tenant_id,
      },
    },
  },

  // TODO: Loki

})
