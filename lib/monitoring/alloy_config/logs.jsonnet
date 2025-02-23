local alloy = import 'github.com/grafana/alloy/operations/alloy-syntax-jsonnet/main.libsonnet';

{
  local this = self,

  local tenant_id = 'homelab',

  // Node Logs
  [alloy.block('loki.source.journal', 'systemd')]: {
    forward_to: [this.loki],
    relabel_rules: alloy.expr('loki.relabel.systemd_add_unit.rules'),
    path: '/var/log/journal',
  },
  [alloy.block('loki.relabel', 'systemd_add_unit')]: {
    forward_to: [],

    [alloy.block('rule', index=0)]: {
      source_labels: ['__journal__systemd_unit'],
      target_label: 'systemd_unit',
    },
  },

  // k8s events
  [alloy.block('loki.source.kubernetes_events', 'cluster')]: {
    forward_to: [this.loki],
  },

  // k8s pods
  [alloy.block('discovery.kubernetes', 'pods')]: {
    role: 'pod',

    [alloy.block('selectors', index=0)]: {
      role: 'pod',
      field: alloy.expr('"spec.nodeName=" + sys.env("K8S_NODE_NAME")'),
    },
  },
  [alloy.block('discovery.relabel', 'pod_logs')]: {
    targets: alloy.expr('discovery.kubernetes.pods.targets'),

    [alloy.block('rule', index=0)]: {
      source_labels: ['__meta_kubernetes_namespace'],
      target_label: 'namespace',
    },

    [alloy.block('rule', index=1)]: {
      source_labels: ['__meta_kubernetes_pod_name'],
      target_label: 'pod',
    },

    [alloy.block('rule', index=2)]: {
      source_labels: ['__meta_kubernetes_pod_container_name'],
      target_label: 'container',
    },

    [alloy.block('rule', index=3)]: {
      source_labels: ['__meta_kubernetes_namespace', '__meta_kubernetes_pod_name'],
      separator: '/',
      target_label: 'job',
    },

    [alloy.block('rule', index=4)]: {
      source_labels: ['__meta_kubernetes_namespace', '__meta_kubernetes_pod_name', '__meta_kubernetes_pod_uid'],
      separator: '_',
      target_label: '__pod_log_dir',
    },

    [alloy.block('rule', index=5)]: {
      source_labels: ['__pod_log_dir', '__meta_kubernetes_pod_container_name'],
      separator: '/',
      action: 'replace',
      replacement: '/var/log/pods/$1/*.log',
      target_label: '__path__',
    },
  },
  [alloy.block('local.file_match', 'pod_logs')]: {
    path_targets: alloy.expr('discovery.relabel.pod_logs.output'),
  },
  [alloy.block('loki.source.file', 'pod_logs')]: {
    targets: alloy.expr('local.file_match.pod_logs.targets'),
    forward_to: [alloy.expr('loki.process.pod_logs.receiver')],
  },
  [alloy.block('loki.process', 'pod_logs')]: {
    [alloy.block('stage.cri', index=0)]: {},
    [alloy.block('stage.labels', index=1)]: {
      values: {
        flags: '',
        stream: '',
      },
    },

    forward_to: [this.loki],
  },

  // Syslog for unifi switches
  [alloy.block('loki.relabel', 'syslog')]: {
    forward_to: [],

    [alloy.block('rule', index=0)]: {
      action: 'labelmap',
      regex: '__syslog_message_(.+)',
      replacement: '$1',
    },
  },
  [alloy.block('loki.source.syslog', 'ingest')]: {
    forward_to: [this.loki],
    relabel_rules: alloy.expr('loki.relabel.syslog.rules'),

    [alloy.block('listener', index=0)]: {
      address: '0.0.0.0:5514',
      protocol: 'udp',
      syslog_format: 'rfc3164',
      // TODO: Alloy can't currently parse rfc3164 timestamps, see https://github.com/grafana/alloy/pull/2755
      use_incoming_timestamp: false,
      labels: {
        component: 'loki.source.syslog',
        protocol: 'udp',
      },
    },
  },

  // Loki Output
  loki:: alloy.expr('loki.write.loki.receiver'),
  [alloy.block('loki.write', 'loki')]: {
    external_labels: {
      cluster: tenant_id,
    },

    [alloy.block('endpoint')]: {
      url: 'http://distributor.loki.svc.cluster.local.:3100/loki/api/v1/push',

      headers: {
        'X-Scope-OrgID': tenant_id,
      },
    },
  },
}
