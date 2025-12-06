local k = import 'k.libsonnet';

local es = (import 'github.com/jsonnet-libs/external-secrets-libsonnet/0.19/main.libsonnet').nogroup.v1.externalSecret;

local image = import 'images.libsonnet';

{
  tunnel: {
    labels:: { app: 'cloudflared' },

    config:: {
      tunnel: 'homelab',
      // Name of the tunnel you want to run
      'credentials-file': '/etc/cloudflared/creds/credentials.json',
      // Serves the metrics server under /metrics and the readiness server under /ready
      metrics: '0.0.0.0:2000',
      // Autoupdates applied in a k8s pod will be lost when the pod is removed or restarted, so
      // autoupdate doesn't make sense in Kubernetes. However, outside of Kubernetes, we strongly
      // recommend using autoupdate.
      'no-autoupdate': true,
      // The `ingress` block tells cloudflared which local service to route incoming
      // requests to. For more about ingress rules, see
      // https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/configuration/ingress
      ingress: [
        {
          hostname: 'hass-cf.nlowe.dev',
          service: 'http://hass.smart-home.svc.cluster.local.:8123',
        },

        { service: 'http_status:503' },
      ],
    },

    local cm = k.core.v1.configMap,
    configMap:
      cm.new('cloudflared', {
        'config.yaml': std.manifestYamlDoc($.tunnel.config),
      }) +
      cm.metadata.withNamespace($.namespace.metadata.name) +
      cm.metadata.withLabels($.tunnel.labels),

    local container = k.core.v1.container,
    local mount = k.core.v1.volumeMount,
    container::
      image.forContainer('cloudflared') +
      container.withArgs([
        'tunnel',
        '--config',
        '/etc/cloudflared/config/config.yaml',
        'run',
      ]) +
      container.livenessProbe.httpGet.withPath('/ready') +
      container.livenessProbe.httpGet.withPort(2000) +
      container.livenessProbe.withFailureThreshold(1) +
      container.livenessProbe.withInitialDelaySeconds(10) +
      container.livenessProbe.withPeriodSeconds(10) +
      container.withVolumeMounts([
        mount.new('config', '/etc/cloudflared/config', readOnly=true),
        mount.new('creds', '/etc/cloudflared/creds', readOnly=true),
      ]),

    tunnelCreds:
      $._config.externalSecret.new('tunnel-credentials', $.namespace.metadata.name) +
      es.spec.withData([
        es.spec.data.withSecretKey('credentials.json') +
        es.spec.data.remoteRef.withKey('7bc66261-3d00-4e2d-91e2-b3180151b182'),
      ]),

    local deploy = k.apps.v1.deployment,
    local volume = k.core.v1.volume,
    local tsc = k.core.v1.topologySpreadConstraint,
    deployment:
      deploy.new('cloudflared', 3, [$.tunnel.container], $.tunnel.labels) +
      deploy.metadata.withNamespace($.namespace.metadata.name) +
      deploy.metadata.withLabels($.tunnel.labels) +
      deploy.spec.template.metadata.withAnnotations({
        'config-hash': std.md5(std.toString($.tunnel.configMap)),
      }) +
      deploy.spec.template.spec.withTopologySpreadConstraints([
        tsc.withMaxSkew(1) +
        tsc.withTopologyKey('kubernetes.io/hostname') +
        tsc.withWhenUnsatisfiable('DoNotSchedule') +
        tsc.labelSelector.withMatchLabels($.tunnel.labels) +
        tsc.withMatchLabelKeys(['pod-template-hash']),
      ]) +
      deploy.spec.template.spec.withVolumes([
        volume.fromSecret('creds', 'tunnel-credentials'),
        volume.fromConfigMap('config', $.tunnel.configMap.metadata.name, [
          { key: 'config.yaml', path: 'config.yaml' },
        ]),
      ]),
  },
}
