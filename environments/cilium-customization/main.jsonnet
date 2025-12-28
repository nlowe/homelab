(import 'homelab.libsonnet') +
(import 'bgp.libsonnet') +
(import 'gateway.libsonnet') +
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
