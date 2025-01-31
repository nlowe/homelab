local k = import 'k.libsonnet';

local cm = import 'github.com/jsonnet-libs/cert-manager-libsonnet/1.15/main.libsonnet';
local g = (import 'github.com/jsonnet-libs/gateway-api-libsonnet/1.1/main.libsonnet').gateway;

{
  caddy+: {
    gateway: {
      labels:: { app: 'caddy-gateway' },

      crds: [
        // The cilium operator seems to require the experimental release
        std.parseYaml((importstr 'github.com/kubernetes-sigs/gateway-api/config/crd/experimental/gateway.networking.k8s.io_gatewayclasses.yaml')),
        std.parseYaml((importstr 'github.com/kubernetes-sigs/gateway-api/config/crd/experimental/gateway.networking.k8s.io_gateways.yaml')),
        std.parseYaml((importstr 'github.com/kubernetes-sigs/gateway-api/config/crd/experimental/gateway.networking.k8s.io_httproutes.yaml')),
        std.parseYaml((importstr 'github.com/kubernetes-sigs/gateway-api/config/crd/experimental/gateway.networking.k8s.io_referencegrants.yaml')),
        std.parseYaml((importstr 'github.com/kubernetes-sigs/gateway-api/config/crd/experimental/gateway.networking.k8s.io_tcproutes.yaml')),
        std.parseYaml((importstr 'github.com/kubernetes-sigs/gateway-api/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml')),
        std.parseYaml((importstr 'github.com/kubernetes-sigs/gateway-api/config/crd/experimental/gateway.networking.k8s.io_udproutes.yaml')),
        std.parseYaml((importstr 'github.com/kubernetes-sigs/gateway-api/config/crd/experimental/gateway.networking.k8s.io_grpcroutes.yaml')),
        std.parseYaml((importstr 'github.com/kubernetes-sigs/gateway-api/config/crd/experimental/gateway.networking.k8s.io_backendtlspolicies.yaml')),
      ],

      local cert = cm.nogroup.v1.certificate,
      cert:
        cert.new('homelab-tls') +
        cert.metadata.withNamespace($.caddy.namespace.metadata.name) +
        cert.spec.withSecretName('homelab-tls') +
        cert.spec.withDnsNames([
          'home.nlowe.dev',
          '*.home.nlowe.dev',
        ]) +
        cert.spec.issuerRef.withKind($.certManager.issuer.kind) +
        cert.spec.issuerRef.withName($.certManager.issuer.metadata.name),

      local sa = k.core.v1.serviceAccount,
      serviceAccount:
        sa.new('caddy-gateway') +
        sa.metadata.withNamespace($.caddy.namespace.metadata.name) +
        sa.metadata.withLabels($.caddy.gateway.labels) +
        sa.withAutomountServiceAccountToken(false),

      local cr = k.rbac.v1.clusterRole,
      local rule = k.rbac.v1.policyRule,
      clusterRole:
        cr.new('caddy-system:caddy-gateway') +
        cr.metadata.withLabels($.caddy.gateway.labels) +
        cr.withRules([
          rule.withApiGroups(['']) +
          rule.withResources([
            'configmaps',
            'endpoints',
            'namespaces',
            'secrets',
            'services',
          ]) +
          rule.withVerbs(['get', 'list', 'watch']),

          rule.withApiGroups(['apiextensions.k8s.io']) +
          rule.withResources(['customresourcedefinitions']) +
          rule.withVerbs(['get']),

          rule.withApiGroups(['gateway.networking.k8s.io']) +
          rule.withResources([
            'backendtlspolicies',
            'gatewayclasses',
            'gateways',
            'grpcroutes',
            'httproutes',
            'referencegrants',
            'tcproutes',
            'tlsroutes',
            'udproutes',
          ]) +
          rule.withVerbs(['get', 'list', 'watch']),

          rule.withApiGroups(['gateway.networking.k8s.io']) +
          rule.withResources([
            'backendtlspolicies/finalizers',
            'gatewayclasses/finalizers',
            'gateways/finalizers',
            'grpcroutes/finalizers',
            'httproutes/finalizers',
            'referencegrants/finalizers',
            'tcproutes/finalizers',
            'tlsroutes/finalizers',
            'udproutes/finalizers',
          ]) +
          rule.withVerbs(['update']),

          rule.withApiGroups(['gateway.networking.k8s.io']) +
          rule.withResources([
            'backendtlspolicies/status',
            'gatewayclasses/status',
            'gateways/status',
            'grpcroutes/status',
            'httproutes/status',
            'referencegrants/status',
            'tcproutes/status',
            'tlsroutes/status',
            'udproutes/status',
          ]) +
          rule.withVerbs(['patch', 'update']),
        ]),

      local crb = k.rbac.v1.clusterRoleBinding,
      local subject = k.rbac.v1.subject,
      clusterRoleBinding:
        crb.new('caddy-system:caddy-gateway') +
        crb.metadata.withLabels($.caddy.gateway.labels) +
        crb.withSubjects([
          subject.fromServiceAccount($.caddy.gateway.serviceAccount),
        ]) +
        crb.bindRole($.caddy.gateway.clusterRole),

      local r = k.rbac.v1.role,
      role:
        r.new('caddy-gateway') +
        r.metadata.withNamespace($.caddy.namespace.metadata.name) +
        r.metadata.withLabels($.caddy.gateway.labels) +
        r.withRules([
          // This weird resource rule is used by kube-rbac-proxy to allow access to the Caddy Admin API.
          rule.withApiGroups(['']) +
          rule.withResources(['caddy/config']) +
          rule.withVerbs(['create']),

          rule.withApiGroups(['']) +
          rule.withResources(['events']) +
          rule.withVerbs(['create', 'patch']),

          rule.withApiGroups(['coordination.k8s.io']) +
          rule.withResources(['leases']) +
          rule.withVerbs(['create']),

          rule.withApiGroups(['coordination.k8s.io']) +
          rule.withResources(['leases']) +
          // https://github.com/caddyserver/gateway/blob/bcf7db1ab28721b301c88e4e1b788dd182e7bb3b/main.go#L101
          rule.withResourceNames(['657d83d7.caddyserver.com']) +
          rule.withVerbs(['get', 'patch', 'update']),
        ]),

      local rb = k.rbac.v1.roleBinding,
      roleBinding:
        rb.new('caddy-system:caddy-gateway') +
        rb.metadata.withNamespace($.caddy.namespace.metadata.name) +
        rb.metadata.withLabels($.caddy.gateway.labels) +
        rb.withSubjects([
          subject.fromServiceAccount($.caddy.gateway.serviceAccount),
        ]) +
        rb.bindRole($.caddy.gateway.role),

      local service = k.core.v1.service,
      local port = k.core.v1.servicePort,
      service:
        service.new('caddy-gateway', $.caddy.gateway.labels, [
          port.newNamed('metrics', 8080, 8080) + port.withProtocol('TCP'),
        ]) +
        service.metadata.withNamespace($.caddy.namespace.metadata.name) +
        service.metadata.withLabels($.caddy.gateway.labels) +
        service.spec.withType('ClusterIP'),

      local container = k.core.v1.container,
      local containerPort = k.core.v1.containerPort,
      local env = k.core.v1.envVar,
      local mount = k.core.v1.volumeMount,
      container::
        container.new('caddy-gateway', 'ghcr.io/caddyserver/gateway:latest') +
        container.withArgs(['--leader-elect']) +
        container.withPorts([
          containerPort.withName('metrics') + containerPort.withContainerPort(8080) + containerPort.withProtocol('TCP'),
          containerPort.withName('health') + containerPort.withContainerPort(8081) + containerPort.withProtocol('TCP'),
        ]) +
        container.withEnv([
          env.withName('GOMEMLIMIT') +
          env.valueFrom.resourceFieldRef.withContainerName($.caddy.gateway.container.name) +
          env.valueFrom.resourceFieldRef.withResource('limits.memory'),
        ]) +
        container.withResourcesLimits('0.5', '2Gi') +
        container.withResourcesRequests('0.25', '1Gi') +
        container.withVolumeMounts([
          mount.new('tls', '/var/run/secrets/tls', readOnly=true),
        ]) +
        container.livenessProbe.httpGet.withPath('healthz') +
        container.livenessProbe.httpGet.withPort('health') +
        container.livenessProbe.httpGet.withScheme('HTTP') +
        container.livenessProbe.withInitialDelaySeconds(5) +
        container.livenessProbe.withTimeoutSeconds(5) +
        container.livenessProbe.withPeriodSeconds(5) +
        container.livenessProbe.withSuccessThreshold(1) +
        container.livenessProbe.withFailureThreshold(3) +
        container.readinessProbe.httpGet.withPath('readyz') +
        container.readinessProbe.httpGet.withPort('health') +
        container.readinessProbe.httpGet.withScheme('HTTP') +
        container.readinessProbe.withInitialDelaySeconds(5) +
        container.readinessProbe.withPeriodSeconds(10) +
        container.securityContext.capabilities.withDrop(['ALL']) +
        container.securityContext.withPrivileged(false) +
        container.securityContext.withReadOnlyRootFilesystem(true) +
        container.securityContext.withAllowPrivilegeEscalation(false),

      local deploy = k.apps.v1.deployment,
      local volume = k.core.v1.volume,
      local tsc = k.core.v1.topologySpreadConstraint,
      deployment:
        deploy.new(
          'caddy-gateway',
          replicas=1,
          containers=[$.caddy.gateway.container],
          podLabels=$.caddy.gateway.labels,
        ) +
        deploy.metadata.withNamespace($.caddy.namespace.metadata.name) +
        deploy.metadata.withLabels($.caddy.gateway.labels) +
        deploy.spec.withReplicas(1) +
        deploy.spec.template.spec.withVolumes([
          volume.fromCsi('tls', 'csi.cert-manager.io', {
            'csi.cert-manager.io/fs-group': '100',
            'csi.cert-manager.io/issuer-kind': $.caddy.ca.issuer.kind,
            'csi.cert-manager.io/issuer-name': $.caddy.ca.issuer.metadata.name,
            'csi.cert-manager.io/duration': '72h',
            'csi.cert-manager.io/common-name': 'system:serviceaccount:caddy-system:caddy-gateway',
            'csi.cert-manager.io/dns-names': 'caddy-gateway.${POD_NAMESPACE}.svc',
            'csi.cert-manager.io/key-usages': 'client auth',
          }) +
          volume.csi.withReadOnly(true),
        ]) +
        deploy.spec.template.spec.withTopologySpreadConstraints([
          tsc.withMaxSkew(1) +
          tsc.withTopologyKey('kubernetes.io/hostname') +
          tsc.withWhenUnsatisfiable('DoNotSchedule') +
          tsc.labelSelector.withMatchLabels($.caddy.gateway.labels) +
          tsc.withMatchLabelKeys(['pod-template-hash']),
        ]) +
        deploy.spec.template.spec.withServiceAccountName($.caddy.gateway.serviceAccount.metadata.name) +
        deploy.spec.template.spec.withAutomountServiceAccountToken(true) +
        deploy.spec.template.spec.withEnableServiceLinks(false) +
        deploy.spec.template.spec.securityContext.withRunAsUser(1000) +
        deploy.spec.template.spec.securityContext.withRunAsGroup(100) +
        deploy.spec.template.spec.securityContext.withRunAsNonRoot(true) +
        deploy.spec.template.spec.securityContext.withFsGroup(100) +
        deploy.spec.template.spec.securityContext.seccompProfile.withType('RuntimeDefault'),

      local gwc = g.v1.gatewayClass,
      class:
        gwc.new('caddy') +
        gwc.metadata.withLabels($.caddy.gateway.labels) +
        gwc.spec.withControllerName('caddyserver.com/gateway-controller'),

      local gateway = g.v1.gateway,
      local listener = gateway.spec.listeners,

      def:
        gateway.new('caddy') +
        gateway.metadata.withNamespace($.caddy.namespace.metadata.name) +
        gateway.metadata.withLabels($.caddy.labels) +
        gateway.spec.withGatewayClassName($.caddy.gateway.class.metadata.name) +
        gateway.spec.withListeners([
          listener.withName('http') +
          listener.withProtocol('HTTP') +
          listener.withPort(80) +
          listener.allowedRoutes.namespaces.withFrom('All'),

          listener.withName('https') +
          listener.withProtocol('HTTPS') +
          listener.withPort(443) +
          listener.allowedRoutes.namespaces.withFrom('All') +
          listener.withHostname('*.home.nlowe.dev') +
          listener.tls.withCertificateRefs([
            listener.tls.certificateRefs.withKind('Secret') +
            listener.tls.certificateRefs.withName($.caddy.gateway.cert.spec.secretName),
          ]),
        ]),

      local route = g.v1.httpRoute,
      local routeRule = route.spec.rules,
      httpToHttpsRedirect:
        route.new('caddy-https-redirect') +
        route.metadata.withNamespace($.caddy.namespace.metadata.name) +
        route.spec.withParentRefs([
          {
            name: $.caddy.gateway.def.metadata.name,
            namespace: $.caddy.gateway.def.metadata.namespace,
            sectionName: 'http',
          },
        ]) +
        route.spec.withHostnames([]) +
        route.spec.withRules([
          routeRule.withFilters([
            routeRule.filters.withType('RequestRedirect') +
            routeRule.filters.requestRedirect.withScheme('https') +
            routeRule.filters.requestRedirect.withPort(443),
          ]),
        ]),
    },
  },
}
