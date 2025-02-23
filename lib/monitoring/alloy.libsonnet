local k = (import 'k.libsonnet');

local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local helm = tk.helm.new(std.thisFile);

{
  _config+:: {
    monitoring+: {
      alloy: {
        local port = k.core.v1.servicePort,
        syslogPorts:: [
          port.newNamed('udp-syslog', 514, 5514) +
          port.withProtocol('UDP'),
        ],

        helmValues:: {
          alloy: {
            configMap: {
              // I'll make my own
              create: false,
              name: $.monitoring.alloy.config.metadata.name,
              key: 'config.alloy',
            },

            clustering: {
              enabled: true,
              name: 'homelab',
            },

            enableReporting: false,

            extraPorts: $._config.monitoring.alloy.syslogPorts,

            local env = k.core.v1.envVar,
            extraEnv: [
              env.withName('K8S_NODE_NAME') +
              env.valueFrom.fieldRef.withFieldPath('spec.nodeName'),
            ],

            mounts: {
              varlog: true,

              extra: [
                {
                  name: 'procfs',
                  mountPath: '/host/proc',
                  readOnly: true,
                },
                {
                  name: 'sysfs',
                  mountPath: '/host/sys',
                  readOnly: true,
                },
                {
                  name: 'udev',
                  mountPath: '/host/run/udev/data',
                  readOnly: true,
                },
                {
                  name: 'containerd',
                  mountPath: '/host/run/k3s/containerd',
                  readOnly: true,
                },
              ],
            },
          },

          controller: {
            volumes: {
              extra: [
                {
                  name: 'procfs',
                  hostPath: {
                    path: '/proc',
                    type: '',
                  },
                },
                {
                  name: 'sysfs',
                  hostPath: {
                    path: '/sys',
                    type: '',
                  },
                },
                {
                  name: 'udev',
                  hostPath: {
                    path: '/run/udev/data',
                    type: '',
                  },
                },
                {
                  name: 'containerd',
                  hostPath: {
                    path: '/run/k3s/containerd',
                    type: '',
                  },
                },
              ],
            },
          },

          // TODO: resources
        },
      },
    },
  },

  monitoring+: {
    alloy: {
      labels:: { app: 'alloy' },

      manifests: helm.template('alloy', '../../charts/alloy', {
        namespace: $.monitoring.namespace.metadata.name,
        values: $._config.monitoring.alloy.helmValues,
      }) + {
        local namespaceMixin = { metadata+: { namespace: $.monitoring.namespace.metadata.name } },

        // The alloy chart is fucked, it doesn't add a namespace to the daemonset or services for whatever reason
        daemon_set_alloy+: namespaceMixin,
        service_alloy+: namespaceMixin,
        service_alloy_cluster+: namespaceMixin,
      },

      local cm = k.core.v1.configMap,
      config:
        cm.new('alloy-config', {
          'config.alloy': (import 'monitoring/alloy_config/config.jsonnet'),
        }) +
        cm.metadata.withNamespace($.monitoring.namespace.metadata.name) +
        cm.metadata.withLabels($.monitoring.alloy.labels),

      local svc = k.core.v1.service,
      syslogService:
        svc.new(
          'alloy-syslog',
          $.monitoring.alloy.manifests.daemon_set_alloy.spec.template.metadata.labels,
          $._config.monitoring.alloy.syslogPorts,
        ) +
        svc.metadata.withNamespace($.monitoring.namespace.metadata.name) +
        svc.metadata.withLabels($.monitoring.alloy.labels) +
        $.cilium.bgp.serviceMixins.alloy_syslog,
    },
  },
}
