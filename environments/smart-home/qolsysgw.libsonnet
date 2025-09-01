local k = import 'k.libsonnet';

local g = (import 'github.com/jsonnet-libs/gateway-api-libsonnet/1.1/main.libsonnet').gateway;

local es = (import 'github.com/nlowe/external-secrets-libsonnet/0.18/main.libsonnet').nogroup.v1.externalSecret;

local image = import 'images.libsonnet';

{
  // This setup is quite stupid. AppDaemon isn't well suited for containers because it assumes you're just dropping
  // python files on disk for the "apps" you want to run. It can't reload MQTT credentials when they change so we have
  // to use long-lived certificates (although to be fair, all other MQTT clients currently deployed here also have this
  // problem). Like HomeAssistant it's annoying to configure with code if you have to include any secrets at all (hence
  // the template mess with external-secrets and go templates).
  //
  // TODO: Scrap this entirely and write our own implementation that doesn't use appdaemon
  qolsysgw: {
    local this = self,

    labels:: { app: 'qolsysgw' },
    port:: 5050,

    appdaemon_config:: {
      appdaemon: {
        time_zone: 'America/New_York',
        latitude: '{{ $data.latitude | float64 }}',
        longitude: '{{ $data.longitude | float64 }}',
        elevation: '{{ $data.elevation | int }}',

        plugins: {
          HASS: {
            type: 'hass',
            ha_url: 'http://hass.smart-home.svc.cluster.local:8123',
            token: '{{ $data.hass_token }}',
          },

          MQTT: {
            type: 'mqtt',
            namespace: 'appdaemon',
            client_topics: 'NONE',

            client_host: 'vernemq.smart-home.svc.cluster.local',
            client_port: 8883,

            client_cert: '/var/run/secrets/vernemq-client-tls/tls.crt',
            client_key: '/var/run/secrets/vernemq-client-tls/tls.key',
            ca_cert: '/var/run/secrets/vernemq-client-tls/ca.crt',
          },
        },

        app_dir: '/apps',
        production_mode: true,
      },

      http: {
        url: 'http://0.0.0.0:5050',
      },
      api: {},
      admin: {},
    },

    appdaemon_config_secret:
      $._config.externalSecret.new('appdaemon-config', $.namespace.metadata.name) +
      es.spec.withData([
        es.spec.data.withSecretKey('data') +
        es.spec.data.remoteRef.withKey('102f248f-3504-4707-9a87-b31900216adb'),
      ]) +
      es.spec.target.template.withEngineVersion('v2') +
      es.spec.target.template.withData({
        'appdaemon.yaml': '{{ $data := fromYaml .data }}\n' + std.manifestYamlDoc($.qolsysgw.appdaemon_config),
      }),

    qolsysgw_config:: {
      qolsys_panel: {
        module: 'gateway',
        class: 'QolsysGateway',

        panel_host: 'alarm-panel.home.nlowe.dev',
        panel_mac: '{{ $data.panel_mac }}',
        panel_token: '{{ $data.panel_token }}',
        panel_user_code: '{{ $data.panel_user_code }}',
        panel_unique_id: 'qolsys_iq4_alarm_panel',
        panel_device_name: 'Qolsys IQ4 Alarm Panel',

        arm_stay_exit_delay: 0,

        mqtt_namespace: this.appdaemon_config.appdaemon.plugins.MQTT.namespace,
      },
    },
    qolsysgw_config_secret:
      $._config.externalSecret.new('qolsysgw-config', $.namespace.metadata.name) +
      es.spec.withData([
        es.spec.data.withSecretKey('data') +
        es.spec.data.remoteRef.withKey('102f248f-3504-4707-9a87-b31900216adb'),
      ]) +
      es.spec.target.template.withEngineVersion('v2') +
      es.spec.target.template.withData({
        'apps.yaml': '{{ $data := fromYaml .data }}\n' + std.manifestYamlDoc($.qolsysgw.qolsysgw_config),
      }),


    local svc = k.core.v1.service,
    local port = k.core.v1.servicePort,
    service: {
      app:
        svc.new('qolsysgw', this.labels, [
          port.withName('http') + port.withPort(this.port) + port.withTargetPort('http'),
        ]) +
        svc.metadata.withNamespace($.namespace.metadata.name) +
        svc.metadata.withLabels(this.labels),

      headless:
        this.service.app +
        svc.metadata.withName('qolsysgw-headless') +
        svc.spec.withClusterIP('None'),
    },

    local container = k.core.v1.container,
    local mount = k.core.v1.volumeMount,
    container::
      image.forContainer('qolsysgw') +
      container.withPorts([
        { containerPort: this.port, name: 'http' },
      ]) +
      // TODO: Tune resources
      // Use a TCP Probe because appdaemon doesn't really provide a good HTTP API to use and loading the frontend causes
      // a bunch of log spam
      container.livenessProbe.tcpSocket.withPort('http') +
      container.livenessProbe.withPeriodSeconds(10) +
      container.livenessProbe.withTimeoutSeconds(5) +
      container.livenessProbe.withFailureThreshold(3) +
      container.withVolumeMounts([
        mount.new('data', '/conf', readOnly=false),

        mount.new('config', '/conf/appdaemon.yaml', readOnly=true) +
        mount.withSubPath('appdaemon.yaml'),

        mount.new('app-config', '/apps/apps.yaml', readOnly=true) +
        mount.withSubPath('apps.yaml'),

        mount.new('vernemq-client-tls', '/var/run/secrets/vernemq-client-tls', readOnly=true),
      ]),

    local pvc = k.core.v1.persistentVolumeClaim,
    pvcTemplate::
      pvc.new('data') +
      pvc.spec.withAccessModes(['ReadWriteOnce']) +
      pvc.spec.resources.withRequests({ storage: '5Gi' }),

    local sts = k.apps.v1.statefulSet,
    local volume = k.core.v1.volume,
    statefulSet:
      sts.new('qolsysgw', 1, [self.container], [self.pvcTemplate], null) +
      sts.metadata.withNamespace($.namespace.metadata.name) +
      sts.metadata.withLabels(self.labels) +
      sts.spec.withServiceName(self.service.headless.metadata.name) +
      sts.spec.selector.withMatchLabels(self.labels) +
      sts.spec.template.metadata.withAnnotations({ 'config-hash': std.md5(std.toString(this.appdaemon_config_secret)) }) +
      sts.spec.template.metadata.withLabels(self.labels) +
      sts.spec.template.spec.dnsConfig.withOptions([{ name: 'ndots', value: '1' }]) +
      sts.spec.template.spec.withVolumes([
        volume.fromSecret('config', this.appdaemon_config_secret.metadata.name) +
        volume.secret.withItems([
          { key: 'appdaemon.yaml', path: 'appdaemon.yaml' },
        ]),
        volume.fromSecret('app-config', this.qolsysgw_config_secret.metadata.name) +
        volume.secret.withItems([
          { key: 'apps.yaml', path: 'apps.yaml' },
        ]),

        volume.fromCsi('vernemq-client-tls', 'csi.cert-manager.io', {
          'csi.cert-manager.io/issuer-kind': $.vernemq.certs.issuer.kind,
          'csi.cert-manager.io/issuer-name': $.vernemq.certs.issuer.metadata.name,
          // The MQTT library that appdaemon uses doesn't seem to support certificate re-loading. Make it valid for a
          // super long time, we'll get a fresh cert any time the container restarts. 30 years of uptime is super
          // optimistic, but one can dream.
          'csi.cert-manager.io/duration': '%dh' % (24 * 365 * 30),
          'csi.cert-manager.io/renew-before': '%dh' % (24 * 30),
          'csi.cert-manager.io/common-name': '${POD_NAME}.qolsysgw-headless.${POD_NAMESPACE}.svc.cluster.local',
          'csi.cert-manager.io/key-usages': 'client auth',
        }) +
        volume.csi.withReadOnly(true),
      ]),

    local route = g.v1.httpRoute,
    local rule = route.spec.rules,
    route:
      route.new('qolsysgw') +
      route.metadata.withNamespace($.namespace.metadata.name) +
      route.metadata.withLabels(this.labels) +
      $._config.caddy.gateway.route() +
      route.spec.withHostnames(['qolsysgw.home.nlowe.dev']) +
      route.spec.withRules([
        rule.withBackendRefs([
          rule.backendRefs.withName(this.service.app.metadata.name) +
          rule.backendRefs.withNamespace(this.service.app.metadata.namespace) +
          rule.backendRefs.withPort(this.port),
        ]),
      ]),
  },
}
