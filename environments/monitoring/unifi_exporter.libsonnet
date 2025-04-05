local prom = import 'github.com/jsonnet-libs/prometheus-operator-libsonnet/0.77/main.libsonnet';
local k = import 'k.libsonnet';

local image = import 'images.libsonnet';

{
  _config+:: {
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

            // These are sent directly to alloy via syslog
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

  unifi_exporter+: {
    labels:: { app: 'unifi-exporter' },

    local cm = k.core.v1.configMap,
    config:
      cm.new('unifi-exporter-config', {
        'config.json': std.manifestJson($._config.unifi_exporter),
      }) +
      cm.metadata.withNamespace($.namespace.metadata.name) +
      cm.metadata.withLabels($.unifi_exporter.labels),

    local container = k.core.v1.container,
    local port = k.core.v1.containerPort,
    local envFrom = k.core.v1.envFromSource,
    local mount = k.core.v1.volumeMount,
    container::
      image.forContainer('unifi-exporter') +
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
      deploy.new('unifi-exporter', 1, [$.unifi_exporter.container], $.unifi_exporter.labels) +
      deploy.metadata.withNamespace($.namespace.metadata.name) +
      deploy.metadata.withLabels($.unifi_exporter.labels) +
      deploy.spec.strategy.withType('Recreate') +
      deploy.spec.template.metadata.withAnnotations({
        'config-hash': std.md5(std.toString($.unifi_exporter.config)),
      }) +
      deploy.spec.template.spec.withVolumes([
        volume.fromConfigMap('config', $.unifi_exporter.config.metadata.name, []),
      ]),

    local pm = prom.monitoring.v1.podMonitor,
    podMonitor:
      pm.new('unifi-exporter') +
      pm.metadata.withNamespace($.namespace.metadata.name) +
      pm.spec.withPodMetricsEndpoints([
        pm.spec.podMetricsEndpoints.withPort('http-metrics'),
      ]) +
      pm.spec.selector.withMatchLabels($.unifi_exporter.deployment.spec.template.metadata.labels),
  },
}
