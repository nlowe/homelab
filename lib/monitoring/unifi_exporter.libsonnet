local prom = import 'github.com/jsonnet-libs/prometheus-operator-libsonnet/0.77/main.libsonnet';
local k = import 'k.libsonnet';

{
  _config+:: {
    monitoring+: {
      unifi_exporter: {
        prometheus: {
          disable: false,
          namespace: 'unifi',
          report_errors: true,
        },

        influxdb: {
          disable: true,
        },

        unifi: {
          controllers: [
            {
              // UDM Pro Max
              url: 'https://10.1.0.1',

              save_dpi: true,

              // TODO: Un-comment when we deploy loki
              // save_ids: true,
              // save_events: true,
              // save_alarms: true,
              // save_anomalies: true,
            },
            // TODO: NVR?
          ],
        },
      },
    },
  },

  monitoring+: {
    unifi_exporter+: {
      labels:: { app: 'unifi-exporter' },

      local cm = k.core.v1.configMap,
      config:
        cm.new('unifi-exporter-config', {
          'config.json': std.manifestJson($._config.monitoring.unifi_exporter),
        }) +
        cm.metadata.withNamespace($.monitoring.namespace.metadata.name) +
        cm.metadata.withLabels($.monitoring.unifi_exporter.labels),

      local container = k.core.v1.container,
      local port = k.core.v1.containerPort,
      local envFrom = k.core.v1.envFromSource,
      local mount = k.core.v1.volumeMount,
      container::
        container.new('unifi-exporter', 'ghcr.io/unpoller/unpoller:v2.14.1') +
        container.withArgs([
          '--config=/etc/unifi-exporter/config.json',
        ]) +
        container.withPorts([
          port.newNamed(9130, 'http-metrics'),
        ]) +
        container.withEnvFrom([
          // TODO: Vault + AVP this
          envFrom.secretRef.withName('unifi-exporter-credentials') +
          envFrom.withPrefix('UP_UNIFI_CONTROLLER_0_'),
        ]) +
        container.withVolumeMounts([
          mount.new('config', '/etc/unifi-exporter', readOnly=true),
        ]),

      local deploy = k.apps.v1.deployment,
      local volume = k.core.v1.volume,
      deployment:
        deploy.new('unifi-exporter', 1, [$.monitoring.unifi_exporter.container], $.monitoring.unifi_exporter.labels) +
        deploy.metadata.withNamespace($.monitoring.namespace.metadata.name) +
        deploy.metadata.withLabels($.monitoring.unifi_exporter.labels) +
        deploy.spec.strategy.withType('Recreate') +
        deploy.spec.template.metadata.withAnnotations({
          'config-hash': std.md5(std.toString($.monitoring.unifi_exporter.config)),
        }) +
        deploy.spec.template.spec.withVolumes([
          volume.fromConfigMap('config', $.monitoring.unifi_exporter.config.metadata.name, []),
        ]),

      local pm = prom.monitoring.v1.podMonitor,
      podMonitor:
        pm.new('unifi-exporter') +
        pm.metadata.withNamespace($.monitoring.namespace.metadata.name) +
        pm.spec.withPodMetricsEndpoints([
          pm.spec.podMetricsEndpoints.withPort('http-metrics'),
        ]) +
        pm.spec.selector.withMatchLabels($.monitoring.unifi_exporter.deployment.spec.template.metadata.labels),
    },
  },
}
