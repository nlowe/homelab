local k = (import 'k.libsonnet');

local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local helm = tk.helm.new(std.thisFile);

local image = import 'images.libsonnet';

{
  _config+:: {
    alloy: {
      local port = k.core.v1.servicePort,
      syslogPorts:: [
        port.newNamed('udp-syslog', 514, 5514) +
        port.withProtocol('UDP'),
      ],

      helmValues:: {
        image: {
          image:: image.alloy,
          registry: self.image.registry,
          repository: self.image.name,
          tag: self.image.version,
        },

        configReloader: {
          image:: image['prometheus-config-reloader'],
          registry: self.image.registry,
          repository: self.image.name,
          tag: self.image.version,
        },

        alloy: {
          configMap: {
            // I'll make my own
            create: false,
            name: $.alloy.config.metadata.name,
            key: 'config.alloy',
          },

          clustering: {
            enabled: true,
            name: 'homelab',
          },

          enableReporting: false,

          extraPorts: $._config.alloy.syslogPorts,

          extraArgs: [
            '--cluster.advertise-address=$(POD_IP)',
          ],

          local env = k.core.v1.envVar,
          extraEnv: [
            env.withName('K8S_NODE_NAME') +
            env.valueFrom.fieldRef.withFieldPath('spec.nodeName'),

            env.withName('POD_IP') +
            env.valueFrom.fieldRef.withFieldPath('status.podIP'),
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
                name: 'systemd',
                mountPath: '/run/systemd/private',
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
          // Use Host Network to pick up network device stats from the host
          hostNetwork: true,
          dnsPolicy: 'ClusterFirstWithHostNet',

          // Extra volumes for exporters
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
                name: 'systemd',
                hostPath: {
                  path: '/run/systemd/private',
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

  alloy: {
    labels:: { app: 'alloy' },

    manifests: helm.template('alloy', '../../charts/alloy', {
      namespace: $.namespace.metadata.name,
      values: $._config.alloy.helmValues,
    }) + {
      local namespaceMixin = { metadata+: { namespace: $.namespace.metadata.name } },

      // The alloy chart is fucked, it doesn't add a namespace to the daemonset or services for whatever reason
      daemon_set_alloy+: namespaceMixin,
      service_alloy+: namespaceMixin,
      service_alloy_cluster+: namespaceMixin,
    },

    local cm = k.core.v1.configMap,
    config:
      cm.new('alloy-config', {
        'config.alloy': (import 'alloy_config/config.jsonnet'),
      }) +
      cm.metadata.withNamespace($.namespace.metadata.name) +
      cm.metadata.withLabels($.alloy.labels),

    local svc = k.core.v1.service,
    syslogService:
      svc.new(
        'alloy-syslog',
        $.alloy.manifests.daemon_set_alloy.spec.template.metadata.labels,
        $._config.alloy.syslogPorts,
      ) +
      svc.metadata.withNamespace($.namespace.metadata.name) +
      svc.metadata.withLabels($.alloy.labels) +
      $._config.cilium.bgp.serviceMixins.alloy_syslog,
  },
}
