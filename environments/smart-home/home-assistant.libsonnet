local k = import 'k.libsonnet';
local g = (import 'github.com/jsonnet-libs/gateway-api-libsonnet/1.1/main.libsonnet').gateway;
local prom = import 'github.com/jsonnet-libs/prometheus-operator-libsonnet/0.77/main.libsonnet';

{
  _config+:: {
    homeAssistant: {
      version:: '2025.1.4',
      // std.manifestYamlDoc escapes tags, so this string gets appended raw to the marshaled config
      appendRawConfig:: |||
        automation ui: !include automations.yaml
        fan: !include_dir_merge_list automations/fan/
        switch: !include_dir_merge_list automations/switch/
      |||,

      default_config: {},
      http: {
        use_x_forwarded_for: true,
        trusted_proxies: [
          '10.0.0.0/8',
          '127.0.0.1',
        ],
      },

      prometheus: {
        namespace: 'hass',
      },
    },
  },

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
        'configuration.yaml':
          std.join('\n', [
            std.manifestYamlDoc($._config.homeAssistant),
            $._config.homeAssistant.appendRawConfig,
          ]),
      }),

    containers:: {
      local container = k.core.v1.container,
      local env = k.core.v1.envVar,
      local mount = k.core.v1.volumeMount,

      hass:
        container.new('home-assistant', 'ghcr.io/home-assistant/home-assistant:%s' % $._config.homeAssistant.version) +
        container.resources.withRequests({ memory: '8Gi' }) +
        container.resources.withLimits({ memory: '8Gi' }) +
        container.withPorts([{ name: 'http', containerPort: 8123 }]) +
        container.securityContext.withPrivileged(true) +
        container.withVolumeMounts([
          mount.withMountPath('/config') +
          mount.withName('data'),

          mount.withMountPath('/config/configuration.yaml') +
          mount.withSubPath('configuration.yaml') +
          mount.withName('config') +
          mount.withReadOnly(true),
        ]),

      code:
        container.new('code-server', 'linuxserver/code-server:4.97.2') +
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

          mount.withMountPath('/config/workspace') +
          mount.withName('data'),
        ]),
    },

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
      sts.spec.template.spec.dnsConfig.withOptions([{ name: 'ndots', value: '1' }]) +
      sts.spec.template.spec.withVolumes([
        volume.fromSecret('config', $.homeAssistant.configSecret.metadata.name),
      ]),

    local pm = prom.monitoring.v1.podMonitor,
    podMonitor:
      pm.new('hass') +
      pm.metadata.withNamespace($.namespace.metadata.name) +
      pm.spec.withPodMetricsEndpoints([
        pm.spec.podMetricsEndpoints.withPort('http') +
        pm.spec.podMetricsEndpoints.withPath('/api/prometheus') +
        // TODO: Vault + AVP this
        pm.spec.podMetricsEndpoints.authorization.withType('Bearer') +
        pm.spec.podMetricsEndpoints.authorization.credentials.withName('hass-prometheus-token') +
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
