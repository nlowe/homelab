local k = import 'k.libsonnet';
local g = (import 'github.com/jsonnet-libs/gateway-api-libsonnet/1.4/main.libsonnet').gateway;

local es = (import 'github.com/jsonnet-libs/external-secrets-libsonnet/1.1/main.libsonnet').nogroup.v1.externalSecret;

local image = import 'images.libsonnet';

{
  esphome: {
    local this = self,

    labels:: { app: 'esphome', role: 'dashboard' },
    agentLabels:: this.labels { role: 'build-agent' },

    local svc = k.core.v1.service,
    local port = k.core.v1.servicePort,
    service: {
      dashboard: {
        app:
          svc.new('esphome', this.labels, [
            port.withName('http') +
            port.withPort(80) +
            port.withTargetPort('http'),

            port.withName('websocket') +
            port.withPort(3000) +
            port.withTargetPort('websocket'),
          ]) +
          svc.metadata.withNamespace($.namespace.metadata.name) +
          svc.metadata.withLabels(this.labels),

        headless:
          this.service.dashboard.app +
          svc.metadata.withName('esphome-headless') +
          svc.spec.withClusterIP('None'),
      },

      agents:
        svc.new('esphome-build-agent', this.agentLabels, [
          port.withName('peer-link') +
          port.withPort(6055) +
          port.withTargetPort('peer-link'),
        ]) +
        svc.metadata.withNamespace($.namespace.metadata.name) +
        svc.metadata.withLabels(this.agentLabels),
    },

    dashboardPassword:
      $._config.externalSecret.new('esphome-dashboard-password', $.namespace.metadata.name) +
      es.spec.withData(
        es.spec.data.withSecretKey('ESPHOME_PASSWORD') +
        es.spec.data.remoteRef.withKey('016d7ab6-dccc-4d8d-bd57-b48b0157be8a')
      ),

    local container = k.core.v1.container,
    local env = k.core.v1.envVar,
    local mount = k.core.v1.volumeMount,
    container:: {
      dashboard:
        image.forContainer('esphome') +
        container.withArgs(['dashboard', '/data']) +
        container.withPorts([
          { containerPort: 6052, name: 'http', protocol: 'TCP' },
        ]) +
        container.withEnv([
          env.new('ESPHOME_USERNAME', 'nlowe'),
          env.fromSecretRef('ESPHOME_PASSWORD', this.dashboardPassword.metadata.name, 'ESPHOME_PASSWORD'),
        ]) +
        // TODO: Tune resources
        container.withVolumeMounts([
          mount.withMountPath('/data') +
          mount.withName('data'),

          mount.withMountPath('/data/local_components') +
          mount.withName('k8s-generic-nfs') +
          mount.withSubPath('esphome-local-components') +
          mount.withReadOnly(true),
        ]),

      agent:
        image.forContainer('esphome') +
        container.withArgs(['dashboard', '--remote-build-only', '/data']) +
        container.withPorts([
          { containerPort: 6055, name: 'peer-link', protocol: 'TCP' },
        ]) +
        // TODO: Tune resources
        container.withVolumeMounts([
          mount.withMountPath('/data') +
          mount.withName('data'),
        ]),
    },

    local pvc = k.core.v1.persistentVolumeClaim,
    pvcTemplate::
      pvc.new('data') +
      pvc.spec.withAccessModes(['ReadWriteOnce']) +
      pvc.spec.resources.withRequests({ storage: '25Gi' }),

    local sts = k.apps.v1.statefulSet,
    statefulSet: {
      dashboard:
        sts.new('esphome', 1, [this.container.dashboard], [this.pvcTemplate], null) +
        sts.metadata.withNamespace($.namespace.metadata.name) +
        sts.metadata.withLabels(this.labels) +
        sts.spec.withServiceName(this.service.dashboard.headless.metadata.name) +
        sts.spec.selector.withMatchLabels(this.labels) +
        sts.spec.template.metadata.withLabels(this.labels) +
        sts.spec.template.spec.withHostNetwork(true) +
        sts.spec.template.spec.withDnsPolicy('ClusterFirstWithHostNet') +
        sts.spec.template.spec.withVolumes([
          $._config.media.mount.forKind('k8s-generic-nfs'),
        ]),

      local affinity = k.core.v1.podAffinityTerm,
      agents:
        sts.new('esphome-build-agent', 3, [this.container.agent], [this.pvcTemplate], null) +
        sts.metadata.withNamespace($.namespace.metadata.name) +
        sts.metadata.withLabels(this.agentLabels) +
        sts.spec.withServiceName(this.service.agents.metadata.name) +
        sts.spec.selector.withMatchLabels(this.agentLabels) +
        sts.spec.withPodManagementPolicy('Parallel') +
        sts.spec.template.metadata.withLabels(this.agentLabels) +
        sts.spec.template.spec.affinity.podAntiAffinity.withRequiredDuringSchedulingIgnoredDuringExecution([
          affinity.withTopologyKey('kubernetes.io/hostname') +
          affinity.labelSelector.withMatchLabels(this.agentLabels) +
          affinity.withMatchLabelKeys(['controller-revision-hash']),
        ]),
    },

    local route = g.v1.httpRoute,
    local rule = route.spec.rules,
    route:
      route.new('esphome') +
      route.metadata.withNamespace($.namespace.metadata.name) +
      $._config.cilium.gateway.route() +
      route.spec.withHostnames(['esp.home.nlowe.dev']) +
      route.spec.withRules([
        rule.withBackendRefs([
          rule.backendRefs.withName(this.service.dashboard.app.metadata.name) +
          rule.backendRefs.withNamespace(this.service.dashboard.app.metadata.namespace) +
          rule.backendRefs.withPort(80),
        ]),
      ]),
  },
}
