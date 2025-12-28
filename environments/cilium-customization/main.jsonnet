(import 'homelab.libsonnet') +
(import 'bgp.libsonnet') +
(import 'gateway.libsonnet') +
(import 'monitoring.libsonnet') +
{
  _config+:: {
    cilium+: {
      install: {
        bgp: {
          announce: {
            LoadBalancerIP: true,
          },
        },

        bgpControlPlane: {
          enabled: true,
        },

        kubeProxyReplacement: true,
        k8sServiceHost: '127.0.0.1',
        k8sServicePort: '6443',

        gatewayAPI: {
          enabled: true,
        },
        envoy: {
          enabled: true,
          securityContext: {
            capabilities: {
              keepCapNetBindService: true,
              envoy: [
                'NET_ADMIN',
                'BPF',
                'NET_BIND_SERVICE',
              ],
            },
          },
        },

        hubble: {
          enabled: true,
          relay: {
            enabled: true,
          },
          ui: {
            enabled: true,
          },
          metrics: {
            enabled: [
              'dns',
              'drop',
              'tcp',
              'flow',
              'port-distribution',
              'icmp',
              'httpV2;labelsContext=source_ip,source_namespace,source_workload,destination_ip,destination_namespace,destination_workload,traffic_direction',
            ],
          },
        },

        operator: {
          prometheus: {
            enabled: true,
          },
        },

        prometheus: {
          enabled: true,
        },
      },
    },
  },

  installConfig: {
    apiVersion: 'helm.cattle.io/v1',
    kind: 'HelmChartConfig',
    metadata: {
      name: 'rke2-cilium',
      namespace: 'kube-system',
    },
    spec: {
      valuesContent: std.manifestYamlDoc($._config.cilium.install),
    },
  },
}
