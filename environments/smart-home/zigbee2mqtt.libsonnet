local k = import 'k.libsonnet';

local cm = import 'github.com/jsonnet-libs/cert-manager-libsonnet/1.15/main.libsonnet';
local g = (import 'github.com/jsonnet-libs/gateway-api-libsonnet/1.1/main.libsonnet').gateway;
local prom = import 'github.com/jsonnet-libs/prometheus-operator-libsonnet/0.77/main.libsonnet';

local image = import 'images.libsonnet';

{
  z2m: {
    local this = self,

    labels:: { app: 'zigbee2mqtt' },
    port:: 8080,

    // Based off of https://github.com/Koenkk/zigbee2mqtt-chart/blob/5e2bf6ebe6e00509119ddf4d11d5d21d589e1f27/charts/zigbee2mqtt/templates/configmap.yaml#L13
    config:: {
      // We keep version 3, even if the current version is 4. The reason is that previous installations
      // will not have any version set in the config map. If we would set 4, it would skip the migration and z2m would
      // have issues. Since we are moving to writable volumes, the init script will make version "soruce of truth" of existing
      // persisted config if any.
      // We will update this to 4 in future releases when we can assume users have upgraded.
      version: 3,

      // Define the files which contains the configs. As k8s config maps
      // Are read only by design, we need to extract dynamic config to external files
      devices: 'devices.yaml',
      groups: 'groups.yaml',

      homeassistant: {
        enabled: true,
        discovery_topic: 'homeassistant',
        status_topic: 'homeassistant/status',
      },

      permit_join: false,
      serial: {
        // https://www.zigbee2mqtt.io/guide/adapters/emberznet.html#network-tcp
        adapter: 'ember',
        port: 'tcp://zigbee-controller.home.nlowe.dev:6638',
      },

      mqtt: {
        server: 'mqtts://vernemq.smart-home.svc.cluster.local:8883',
        base_topic: 'zigbee2mqtt',

        cert: '/var/run/secrets/vernemq-client-tls/tls.crt',
        key: '/var/run/secrets/vernemq-client-tls/tls.key',
        ca: '/var/run/secrets/vernemq-client-tls/ca.crt',

        include_device_information: true,

        version: 5,
      },

      frontend: {
        enabled: true,
        port: this.port,
        url: 'https://zigbee2mqtt.home.nlowe.dev',
      },
    },

    local svc = k.core.v1.service,
    local port = k.core.v1.servicePort,
    service: {
      app:
        svc.new('zigbee2mqtt', this.labels, [
          port.withName('http') + port.withPort(this.port) + port.withTargetPort('http'),
        ]) +
        svc.metadata.withNamespace($.namespace.metadata.name) +
        svc.metadata.withLabels(this.labels),

      headless:
        this.service.app +
        svc.metadata.withName('zigbee2mqtt-headless') +
        svc.spec.withClusterIP('None'),
    },

    local conf = k.core.v1.configMap,
    configMap:
      conf.new('zigbee2mqtt', {
        'configuration.yaml': std.manifestYamlDoc(this.config),
      }) +
      conf.metadata.withNamespace($.namespace.metadata.name) +
      conf.metadata.withLabels(this.labels),

    local container = k.core.v1.container,
    local mount = k.core.v1.volumeMount,
    local env = k.core.v1.envVar,
    initContainer::
      image.forContainer('yq', container_name='prepare-config') +
      container.withCommand(['/bin/sh']) +
      container.withWorkingDir('/app/data') +
      container.withArgs([
        '-c',
        // this scripts copies all the data from the configmap to configuration.yaml (except the version)
        // and then copies the version from the configmap if it does not (already) exist in configuration.yaml
        //
        // See https://github.com/Koenkk/zigbee2mqtt-chart/blob/5e2bf6ebe6e00509119ddf4d11d5d21d589e1f27/charts/zigbee2mqtt/templates/statefulset.yaml#L99-L114
        |||
          if [ -f configuration.yaml ]
          then
            echo "Backing up existing configuration file to /app/data/configuration-backup.yaml"
            cp configuration.yaml configuration-backup.yaml
          else
            echo "configuration.yaml does not exists, creating one from config map /app/data/configmap-configuration.yaml"
            cp configmap-configuration.yaml configuration.yaml
          fi

          yq --inplace '. *= load("configmap-configuration.yaml") | del(.version) ' configuration.yaml
          yq eval-all  '. as $item ireduce ({}; . * $item )' configmap-configuration.yaml configuration.yaml > configuration.yaml
        |||,
      ]) +
      container.securityContext.withRunAsUser(0) +
      container.withVolumeMounts([
        mount.new('data', '/app/data', readOnly=false),

        mount.new('config', '/app/data/configmap-configuration.yaml', readOnly=true) +
        mount.withSubPath('configmap-configuration.yaml'),
      ]),

    container::
      image.forContainer('zigbee2mqtt') +
      container.withPorts([
        { containerPort: this.port, name: 'http' },
      ]) +
      container.withEnv([
        // Skip the onboarding workflow and use the configmap
        env.new('Z2M_ONBOARD_NO_SERVER', '1'),
      ]) +
      // TODO: Tune resources
      container.livenessProbe.httpGet.withPath('/') +
      container.livenessProbe.httpGet.withPort('http') +
      container.livenessProbe.withPeriodSeconds(10) +
      container.livenessProbe.withTimeoutSeconds(5) +
      container.livenessProbe.withFailureThreshold(3) +
      container.withVolumeMounts([
        mount.new('data', '/app/data', readOnly=false),

        mount.new('config', '/app/data/configmap-configuration.yaml', readOnly=true) +
        mount.withSubPath('configmap-configuration.yaml'),

        mount.new('vernemq-client-tls', '/var/run/secrets/vernemq-client-tls', readOnly=true),
      ]),

    local pvc = k.core.v1.persistentVolumeClaim,
    pvcTemplate::
      pvc.new('data') +
      pvc.spec.withAccessModes(['ReadWriteOnce']) +
      pvc.spec.resources.withRequests({ storage: '5Gi' }),

    local sts = k.apps.v1.statefulSet,
    local volume = k.core.v1.volume,
    local tsc = k.core.v1.topologySpreadConstraint,
    statefulSet:
      sts.new('zigbee2mqtt', 1, [self.container], [self.pvcTemplate], null) +
      sts.metadata.withNamespace($.namespace.metadata.name) +
      sts.metadata.withLabels(self.labels) +
      sts.spec.withServiceName(self.service.headless.metadata.name) +
      sts.spec.selector.withMatchLabels(self.labels) +
      sts.spec.template.metadata.withAnnotations({ 'config-hash': std.md5(std.toString(this.configMap)) }) +
      sts.spec.template.metadata.withLabels(self.labels) +
      sts.spec.template.spec.withInitContainers([this.initContainer]) +
      sts.spec.template.spec.withVolumes([
        volume.fromConfigMap('config', this.configMap.metadata.name, [
          { key: 'configuration.yaml', path: 'configmap-configuration.yaml' },
        ]),

        volume.fromCsi('vernemq-client-tls', 'csi.cert-manager.io', {
          'csi.cert-manager.io/issuer-kind': $.vernemq.certs.issuer.kind,
          'csi.cert-manager.io/issuer-name': $.vernemq.certs.issuer.metadata.name,
          // zigbee2mqtt doesn't seem to support certificate re-loading. Make it valid for a super long time, we'll get
          // a fresh cert any time the container restarts. 30 years of uptime is super optimistic, but one can dream.
          'csi.cert-manager.io/duration': '%dh' % (24 * 365 * 30),
          'csi.cert-manager.io/renew-before': '%dh' % (24 * 30),
          'csi.cert-manager.io/common-name': '${POD_NAME}.zigbee2mqtt-headless.${POD_NAMESPACE}.svc.cluster.local',
          'csi.cert-manager.io/key-usages': 'client auth',
        }) +
        volume.csi.withReadOnly(true),
      ]),

    local route = g.v1.httpRoute,
    local rule = route.spec.rules,
    route:
      route.new('zigbee2mqtt') +
      route.metadata.withNamespace($.namespace.metadata.name) +
      route.metadata.withLabels(this.labels) +
      $._config.caddy.gateway.route() +
      route.spec.withHostnames(['zigbee2mqtt.home.nlowe.dev']) +
      route.spec.withRules([
        rule.withBackendRefs([
          rule.backendRefs.withName(this.service.app.metadata.name) +
          rule.backendRefs.withNamespace(this.service.app.metadata.namespace) +
          rule.backendRefs.withPort(this.port),
        ]),
      ]),
  },
}
