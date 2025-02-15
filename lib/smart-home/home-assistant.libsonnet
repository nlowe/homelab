local k = import 'k.libsonnet';
local g = (import 'github.com/jsonnet-libs/gateway-api-libsonnet/1.1/main.libsonnet').gateway;

{
  _config+:: {
    smartHome+: {
      homeAssistant: {
        version:: '2025.1.4',
        // std.manifestYamlDoc escapes tags, so this string gets appended raw to the marshaled config
        appendRawConfig:: |||
          automation ui: !include automations.yaml
        |||,

        default_config: {},
        http: {
          use_x_forwarded_for: true,
          trusted_proxies: [
            '10.0.0.0/8',
            '127.0.0.1',
          ],
        },

        smartir: {},
      },
    },
  },

  smartHome+: {
    homeAssistant: {
      labels:: { app: 'hass' },

      service: {
        local svc = k.core.v1.service,
        local port = k.core.v1.servicePort,

        port::
          port.withName('http') +
          port.withProtocol('TCP') +
          port.withPort(8123) +
          port.withTargetPort(8123),

        headless:
          svc.new(
            'hass-headless',
            $.smartHome.homeAssistant.labels,
            [
              $.smartHome.homeAssistant.service.port,
            ]
          ) +
          svc.metadata.withNamespace($.smartHome.namespace.metadata.name) +
          svc.spec.withClusterIP('None'),

        app:
          svc.new(
            'hass',
            $.smartHome.homeAssistant.labels,
            [
              $.smartHome.homeAssistant.service.port,
            ]
          ) +
          svc.metadata.withNamespace($.smartHome.namespace.metadata.name),
      },

      local secret = k.core.v1.secret,
      configSecret:
        secret.new('hass-config', null, 'Opaque') +
        secret.metadata.withNamespace($.smartHome.namespace.metadata.name) +
        secret.withStringData({
          'configuration.yaml':
            std.join('\n', [
              std.manifestYamlDoc($._config.smartHome.homeAssistant),
              $._config.smartHome.homeAssistant.appendRawConfig,
            ]),
        }),

      local container = k.core.v1.container,
      local mount = k.core.v1.volumeMount,
      container::
        container.new('home-assistant', 'ghcr.io/home-assistant/home-assistant:%s' % $._config.smartHome.homeAssistant.version) +
        container.resources.withRequests({ memory: '8Gi' }) +
        container.resources.withLimits({ memory: '8Gi' }) +
        container.withPorts([{ containerPort: 8123 }]) +
        container.securityContext.withPrivileged(true) +
        container.withVolumeMounts([
          mount.withMountPath('/config') +
          mount.withName('data'),

          mount.withMountPath('/config/configuration.yaml') +
          mount.withSubPath('configuration.yaml') +
          mount.withName('config') +
          mount.withReadOnly(true),
        ]),

      local sts = k.apps.v1.statefulSet,
      local volume = k.core.v1.volume,
      local pvc = k.core.v1.persistentVolumeClaim,
      statefulSet:
        sts.new(
          'hass',
          1,
          [
            $.smartHome.homeAssistant.container,
          ],
          [
            pvc.new('data') +
            pvc.spec.withAccessModes(['ReadWriteOnce']) +
            pvc.spec.resources.withRequests({ storage: '100Gi' }),
          ],
          // Stupid auto name label
          null,
        ) +
        sts.metadata.withNamespace($.smartHome.namespace.metadata.name) +
        sts.spec.withServiceName($.smartHome.homeAssistant.service.headless.metadata.name) +
        sts.spec.selector.withMatchLabels($.smartHome.homeAssistant.labels) +
        sts.spec.template.metadata.withAnnotations({
          'config-hash': std.md5(std.toString($.smartHome.homeAssistant.configSecret)),
        }) +
        sts.spec.template.metadata.withLabels($.smartHome.homeAssistant.labels) +
        sts.spec.template.spec.withHostNetwork(true) +
        sts.spec.template.spec.withDnsPolicy('ClusterFirstWithHostNet') +
        sts.spec.template.spec.dnsConfig.withOptions([{ name: 'ndots', value: '1' }]) +
        sts.spec.template.spec.withVolumes([
          volume.fromSecret('config', $.smartHome.homeAssistant.configSecret.metadata.name),
        ]),

      local route = g.v1.httpRoute,
      local rule = route.spec.rules,
      route:
        route.new('home-assistant') +
        route.metadata.withNamespace('smart-home') +
        route.spec.withParentRefs([
          route.spec.parentRefs.withName($.caddy.gateway.def.metadata.name) +
          route.spec.parentRefs.withNamespace($.caddy.gateway.def.metadata.namespace),
        ]) +
        route.spec.withHostnames(['hass.home.nlowe.dev']) +
        route.spec.withRules([
          rule.withBackendRefs([
            rule.backendRefs.withName($.smartHome.homeAssistant.service.app.metadata.name) +
            rule.backendRefs.withNamespace($.smartHome.homeAssistant.service.app.metadata.namespace) +
            rule.backendRefs.withPort(8123),
          ]),
        ]),
    },
  },
}
