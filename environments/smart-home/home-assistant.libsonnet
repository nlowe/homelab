local k = import 'k.libsonnet';
local g = (import 'github.com/jsonnet-libs/gateway-api-libsonnet/1.1/main.libsonnet').gateway;

local prom = import 'github.com/jsonnet-libs/prometheus-operator-libsonnet/0.77/main.libsonnet';

local es = (import 'github.com/nlowe/external-secrets-libsonnet/0.18/main.libsonnet').nogroup.v1.externalSecret;

local image = import 'images.libsonnet';

{
  homeAssistant: {
    labels:: { app: 'hass' },

    service: {
      local svc = k.core.v1.service,
      local port = k.core.v1.servicePort,

      ports:: {
        hass:
          port.withName('http') +
          port.withProtocol('TCP') +
          port.withPort(8123) +
          port.withTargetPort(8123),

        code:
          port.withName('http-code') +
          port.withProtocol('TCP') +
          port.withPort(8443) +
          port.withTargetPort(8443),
      },

      headless:
        svc.new(
          'hass-headless',
          $.homeAssistant.labels,
          [
            $.homeAssistant.service.ports.hass,
          ]
        ) +
        svc.metadata.withNamespace($.namespace.metadata.name) +
        svc.spec.withClusterIP('None'),

      app:
        svc.new(
          'hass',
          $.homeAssistant.labels,
          [
            $.homeAssistant.service.ports.hass,
            $.homeAssistant.service.ports.code,
          ]
        ) +
        svc.metadata.withNamespace($.namespace.metadata.name),
    },

    local secret = k.core.v1.secret,
    configSecret:
      secret.new('hass-config', null, 'Opaque') +
      secret.metadata.withNamespace($.namespace.metadata.name) +
      secret.withStringData({
        'configuration.yaml': '!include hass-config-nfs/main.yaml',
      }),

    containers:: {
      local container = k.core.v1.container,
      local env = k.core.v1.envVar,
      local mount = k.core.v1.volumeMount,

      hass:
        image.forContainer('home-assistant') +
        container.resources.withRequests({ memory: '8Gi' }) +
        container.resources.withLimits({ memory: '8Gi' }) +
        container.withPorts([{ name: 'http', containerPort: 8123 }]) +
        container.securityContext.withPrivileged(true) +
        container.withVolumeMounts([
          mount.withMountPath('/config') +
          mount.withName('data'),

          mount.withMountPath('/config/hass-config-nfs') +
          mount.withName('k8s-generic-nfs') +
          mount.withSubPath('hass-config') +
          mount.withReadOnly(true),

          mount.withMountPath('/config/configuration.yaml') +
          mount.withSubPath('configuration.yaml') +
          mount.withName('config') +
          mount.withReadOnly(true),
        ]),

      code:
        image.forContainer('code-server') +
        container.resources.withRequests({ memory: '4Gi' }) +
        container.resources.withLimits({ memory: '4Gi' }) +
        container.withPorts([{ name: 'http-code', containerPort: 8443 }]) +
        container.withEnv([
          env.new('PUID', '0'),
          env.new('PGID', '0'),
          env.new('DEFAULT_WORKSPACE', '/config/workspace'),
        ]) +
        container.withVolumeMounts([
          mount.withMountPath('/config') +
          mount.withName('code-server'),

          mount.withMountPath('/config/workspace/hass-config-nfs') +
          mount.withName('k8s-generic-nfs') +
          mount.withSubPath('hass-config') +
          mount.withReadOnly(true),

          mount.withMountPath('/config/workspace') +
          mount.withName('data'),

          mount.withMountPath('/root/.ssh') +
          mount.withName('github-ssh-key') +
          mount.withReadOnly(true),
        ]),
    },

    github_ssh_key_secret:
      $._config.externalSecret.new('github-ssh-key', $.namespace.metadata.name) +
      es.spec.withData([
        es.spec.data.withSecretKey('id_ed25519') +
        es.spec.data.remoteRef.withKey('de805969-0577-4c13-930d-b318015a29d0'),

        es.spec.data.withSecretKey('id_ed25519.pub') +
        es.spec.data.remoteRef.withKey('03aecc60-b715-4b52-83ea-b318015a39d8'),
      ]),

    local sts = k.apps.v1.statefulSet,
    local volume = k.core.v1.volume,
    local pvc = k.core.v1.persistentVolumeClaim,
    statefulSet:
      sts.new(
        'hass',
        1,
        [
          $.homeAssistant.containers.hass,
          $.homeAssistant.containers.code,
        ],
        [
          pvc.new('data') +
          pvc.spec.withAccessModes(['ReadWriteOnce']) +
          pvc.spec.resources.withRequests({ storage: '100Gi' }),

          pvc.new('code-server') +
          pvc.spec.withAccessModes(['ReadWriteOnce']) +
          pvc.spec.resources.withRequests({ storage: '5Gi' }),
        ],
        // Stupid auto name label
        null,
      ) +
      sts.metadata.withNamespace($.namespace.metadata.name) +
      sts.spec.withServiceName($.homeAssistant.service.headless.metadata.name) +
      sts.spec.selector.withMatchLabels($.homeAssistant.labels) +
      sts.spec.template.metadata.withAnnotations({
        'config-hash': std.md5(std.toString($.homeAssistant.configSecret)),
      }) +
      sts.spec.template.metadata.withLabels($.homeAssistant.labels) +
      sts.spec.template.spec.withHostNetwork(true) +
      sts.spec.template.spec.withDnsPolicy('ClusterFirstWithHostNet') +
      sts.spec.template.spec.withVolumes([
        volume.fromSecret('config', $.homeAssistant.configSecret.metadata.name),

        $._config.media.mount.forKind('k8s-generic-nfs'),

        volume.fromSecret('github-ssh-key', $.homeAssistant.github_ssh_key_secret.metadata.name) +
        volume.secret.withDefaultMode(std.parseOctal('0600')) +
        volume.secret.withItems([
          { key: 'id_ed25519', path: 'id_ed25519' },
          { key: 'id_ed25519.pub', path: 'id_ed25519.pub' },
        ]),
      ]),

    podMonitorToken:
      $._config.externalSecret.new('hass-prometheus-token', $.namespace.metadata.name) +
      es.spec.withData([
        es.spec.data.withSecretKey('token') +
        es.spec.data.remoteRef.withKey('7fd81213-f7a0-4768-b751-b318015ab910'),
      ]),

    local pm = prom.monitoring.v1.podMonitor,
    podMonitor:
      pm.new('hass') +
      pm.metadata.withNamespace($.namespace.metadata.name) +
      pm.spec.withPodMetricsEndpoints([
        pm.spec.podMetricsEndpoints.withPort('http') +
        pm.spec.podMetricsEndpoints.withPath('/api/prometheus') +
        pm.spec.podMetricsEndpoints.authorization.withType('Bearer') +
        pm.spec.podMetricsEndpoints.authorization.credentials.withName($.homeAssistant.podMonitorToken.metadata.name) +
        pm.spec.podMetricsEndpoints.authorization.credentials.withKey('token'),
      ]) +
      pm.spec.selector.withMatchLabels($.homeAssistant.statefulSet.spec.template.metadata.labels),

    local route = g.v1.httpRoute,
    local rule = route.spec.rules,
    route:
      route.new('home-assistant') +
      route.metadata.withNamespace('smart-home') +
      $._config.caddy.gateway.route() +
      route.spec.withHostnames(['hass.home.nlowe.dev']) +
      route.spec.withRules([
        // This is required because code-server requires a trailing / in the URL to work on a sub-path
        rule.withMatches([
          rule.matches.path.withType('Exact') +
          rule.matches.path.withValue('/_code_server'),
        ]) +
        rule.withFilters([
          rule.filters.withType('RequestRedirect') +
          rule.filters.requestRedirect.path.withType('ReplaceFullPath') +
          rule.filters.requestRedirect.path.withReplaceFullPath('/_code_server/'),
        ]),

        rule.withMatches([
          rule.matches.path.withType('PathPrefix') +
          // We need to omit the trailing / here so caddy-gateway doesn't strip off the leading "/", otherwise static assets won't load
          rule.matches.path.withValue('/_code_server'),
        ]) +
        rule.withFilters([
          rule.filters.withType('URLRewrite') +
          rule.filters.urlRewrite.path.withType('ReplacePrefixMatch') +
          rule.filters.urlRewrite.path.withReplacePrefixMatch('/'),
        ]) +
        rule.withBackendRefs([
          rule.backendRefs.withName($.homeAssistant.service.app.metadata.name) +
          rule.backendRefs.withNamespace($.homeAssistant.service.app.metadata.namespace) +
          rule.backendRefs.withPort(8443),
        ]),

        rule.withBackendRefs([
          rule.backendRefs.withName($.homeAssistant.service.app.metadata.name) +
          rule.backendRefs.withNamespace($.homeAssistant.service.app.metadata.namespace) +
          rule.backendRefs.withPort(8123),
        ]),
      ]),
  },
}
