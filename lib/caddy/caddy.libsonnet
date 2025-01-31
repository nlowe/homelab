local k = import 'k.libsonnet';

local cm = import 'github.com/jsonnet-libs/cert-manager-libsonnet/1.15/main.libsonnet';

(import 'gateway.libsonnet') +
{
  _config+:: {
    caddy: {
      authorization: {
        resourceAttributes: {
          namespace: $.caddy.namespace.metadata.name,
          apiVersion: 'v1',
          resource: 'caddy',
          subresource: 'config',
          name: 'caddy',
        },
      },
    },
  },

  caddy+: {
    labels:: { app: 'caddy' },

    local ns = k.core.v1.namespace,
    namespace:
      ns.new('caddy-system') +
      ns.metadata.withLabels(
        $.caddy.labels {
          'pod-security.kubernetes.io/enforce': 'restricted',
          'pod-security.kubernetes.io/enforce-version': 'latest',
          'pod-security.kubernetes.io/audit': 'restricted',
          'pod-security.kubernetes.io/audit-version': 'latest',
          'pod-security.kubernetes.io/warn': 'restricted',
          'pod-security.kubernetes.io/warn-version': 'latest',
        }
      ),

    ca: {
      local issuer = cm.nogroup.v1.issuer,

      root:
        issuer.new('selfsigned') +
        issuer.metadata.withNamespace($.caddy.namespace.metadata.name) +
        issuer.metadata.withLabels($.caddy.labels) +
        {
          spec: {
            selfSigned: {},
          },
        },

      local cert = cm.nogroup.v1.certificate,
      cert:
        cert.new('caddy-selfsigned-ca') +
        cert.metadata.withNamespace($.caddy.namespace.metadata.name) +
        cert.metadata.withLabels($.caddy.labels) +
        cert.spec.withIsCA(true) +
        cert.spec.withCommonName('caddy-selfsigned-ca') +
        cert.spec.withSecretName('caddy-selfsigned-ca') +
        cert.spec.subject.withOrganizations([$.caddy.namespace.metadata.name]) +
        cert.spec.privateKey.withAlgorithm('ECDSA') +
        cert.spec.privateKey.withSize(256) +
        cert.spec.issuerRef.withGroup('cert-manager.io') +
        cert.spec.issuerRef.withKind($.caddy.ca.root.kind) +
        cert.spec.issuerRef.withName($.caddy.ca.root.metadata.name),

      issuer:
        issuer.new('caddy') +
        issuer.metadata.withNamespace($.caddy.namespace.metadata.name) +
        issuer.metadata.withLabels($.caddy.labels) +
        issuer.spec.ca.withSecretName($.caddy.ca.cert.spec.secretName),
    },

    local sa = k.core.v1.serviceAccount,
    serviceAccount:
      sa.new('caddy') +
      sa.metadata.withNamespace($.caddy.namespace.metadata.name) +
      sa.metadata.withLabels($.caddy.labels) +
      sa.withAutomountServiceAccountToken(false),

    local cr = k.rbac.v1.clusterRole,
    local rule = k.rbac.v1.policyRule,
    clusterRole:
      cr.new('caddy-system:caddy') +
      cr.metadata.withLabels($.caddy.labels) +
      cr.withRules([
        rule.withApiGroups(['authorization.k8s.io']) +
        rule.withResources(['subjectaccessreviews']) +
        rule.withVerbs(['create']),
      ]),

    local crb = k.rbac.v1.clusterRoleBinding,
    local subject = k.rbac.v1.subject,
    clusterRoleBinding:
      crb.new('caddy-system:caddy') +
      crb.metadata.withLabels($.caddy.labels) +
      crb.withSubjects([
        subject.fromServiceAccount($.caddy.serviceAccount),
      ]) +
      crb.bindRole($.caddy.clusterRole),

    local conf = k.core.v1.configMap,
    configMap:
      conf.new('caddy-kube-rbac-proxy', {
        'config.yaml': std.manifestYamlDoc($._config.caddy),
      }) +
      conf.metadata.withNamespace($.caddy.namespace.metadata.name) +
      conf.metadata.withLabels($.caddy.labels),

    containers:: {
      local container = k.core.v1.container,
      local containerPort = k.core.v1.containerPort,
      local env = k.core.v1.envVar,
      local mount = k.core.v1.volumeMount,

      kube_rbac_proxy:
        container.new('kube-rbac-proxy', 'quay.io/brancz/kube-rbac-proxy:v0.17.1@sha256:89d0be6da831f45fb53e7e40d216555997ccf6e27d66f62e50eb9a69ff9c9801') +
        container.withArgs([
          '--secure-listen-address=:2021',
          '--upstream=http://[::1]:2019/',
          '--tls-cipher-suites=TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305',
          '--client-ca-file=/var/run/secrets/tls/ca.crt',
          '--tls-cert-file=/var/run/secrets/tls/tls.crt',
          '--tls-private-key-file=/var/run/secrets/tls/tls.key',
          '--tls-reload-interval=1h',
          '--config-file=/etc/kube-rbac-proxy/config.yaml',
        ]) +
        container.withPorts([
          containerPort.withName('admin') + containerPort.withContainerPort(2021) + containerPort.withProtocol('TCP'),
        ]) +
        container.withEnv([
          env.withName('GOMEMLIMIT') +
          env.valueFrom.resourceFieldRef.withContainerName($.caddy.containers.kube_rbac_proxy.name) +
          env.valueFrom.resourceFieldRef.withResource('limits.memory'),
        ]) +
        container.withResourcesLimits('0.2', '128Mi') +
        container.withResourcesRequests('0.1', '64Mi') +
        container.withVolumeMounts([
          mount.new('kube-rbac-proxy', '/etc/kube-rbac-proxy', readOnly=true),
          mount.new('tls', '/var/run/secrets/tls', readOnly=true),
        ]) +
        container.securityContext.capabilities.withDrop(['ALL']) +
        container.securityContext.withPrivileged(false) +
        container.securityContext.withReadOnlyRootFilesystem(true) +
        container.securityContext.withAllowPrivilegeEscalation(false),

      caddy:
        container.new('caddy', 'ghcr.io/caddyserver/gateway:caddy-2.8.4') +
        container.withCommand(['caddy']) +
        container.withArgs(['run']) +
        container.withPorts([
          containerPort.withName('http') + containerPort.withContainerPort(80) + containerPort.withProtocol('TCP'),
          containerPort.withName('http2') + containerPort.withContainerPort(443) + containerPort.withProtocol('TCP'),
          containerPort.withName('http3') + containerPort.withContainerPort(443) + containerPort.withProtocol('UDP'),
        ]) +
        container.withEnv([
          env.new('CADDY_ADMIN', ':2019'),

          env.withName('GOMEMLIMIT') +
          env.valueFrom.resourceFieldRef.withContainerName($.caddy.containers.caddy.name) +
          env.valueFrom.resourceFieldRef.withResource('limits.memory'),
        ]) +
        container.withResourcesLimits('4', '4Gi') +
        container.withResourcesRequests('0.25', '1Gi') +
        container.withVolumeMounts([
          mount.new('config', '/config', readOnly=false),
          mount.new('data', '/data', readOnly=false),
          mount.new('tmp', '/tmp', readOnly=false),
        ]) +
        container.livenessProbe.httpGet.withPath('/metrics') +
        container.livenessProbe.httpGet.withPort(2019) +
        container.readinessProbe.httpGet.withPath('/metrics') +
        container.readinessProbe.httpGet.withPort(2019) +
        container.startupProbe.httpGet.withPath('/metrics') +
        container.startupProbe.httpGet.withPort(2019) +
        container.startupProbe.withFailureThreshold(10) +
        container.startupProbe.withSuccessThreshold(1) +
        container.startupProbe.withInitialDelaySeconds(1) +
        container.startupProbe.withPeriodSeconds(10) +
        container.startupProbe.withTimeoutSeconds(3) +
        container.securityContext.capabilities.withDrop(['ALL']) +
        container.securityContext.withPrivileged(false) +
        container.securityContext.withReadOnlyRootFilesystem(true) +
        container.securityContext.withAllowPrivilegeEscalation(false),
    },

    local deploy = k.apps.v1.deployment,
    local volume = k.core.v1.volume,
    local tsc = k.core.v1.topologySpreadConstraint,

    deployment:
      deploy.new(
        'caddy',
        replicas=3,
        containers=[
          $.caddy.containers.kube_rbac_proxy,
          $.caddy.containers.caddy,
        ],
        podLabels=$.caddy.labels,
      ) +
      deploy.metadata.withNamespace($.caddy.namespace.metadata.name) +
      deploy.metadata.withLabels($.caddy.labels) +
      deploy.spec.template.metadata.withAnnotations({
        'kubectl.kubernetes.io/default-container': 'caddy',
      }) +
      deploy.spec.template.spec.withVolumes([
        volume.fromEmptyDir('config', {}),
        volume.fromEmptyDir('data', {}),
        volume.fromEmptyDir('tmp', {}),

        volume.fromCsi('tls', 'csi.cert-manager.io', {
          'csi.cert-manager.io/fs-group': '100',
          'csi.cert-manager.io/issuer-kind': $.caddy.ca.issuer.kind,
          'csi.cert-manager.io/issuer-name': $.caddy.ca.issuer.metadata.name,
          'csi.cert-manager.io/duration': '72h',
          'csi.cert-manager.io/dns-names': '${POD_NAME},${POD_NAME}.${POD_NAMESPACE},caddy.${POD_NAMESPACE}.svc',
          'csi.cert-manager.io/key-usages': 'server auth',
        }) +
        volume.csi.withReadOnly(true),

        volume.fromConfigMap('kube-rbac-proxy', $.caddy.configMap.metadata.name, []),
      ]) +
      deploy.spec.template.spec.withTopologySpreadConstraints([
        tsc.withMaxSkew(1) +
        tsc.withTopologyKey('kubernetes.io/hostname') +
        tsc.withWhenUnsatisfiable('DoNotSchedule') +
        tsc.labelSelector.withMatchLabels($.caddy.labels) +
        tsc.withMatchLabelKeys(['pod-template-hash']),
      ]) +
      deploy.spec.template.spec.withServiceAccountName($.caddy.serviceAccount.metadata.name) +
      deploy.spec.template.spec.withAutomountServiceAccountToken(true) +
      deploy.spec.template.spec.withEnableServiceLinks(false) +
      deploy.spec.template.spec.securityContext.withRunAsUser(1000) +
      deploy.spec.template.spec.securityContext.withRunAsGroup(100) +
      deploy.spec.template.spec.securityContext.withRunAsNonRoot(true) +
      deploy.spec.template.spec.securityContext.withFsGroup(100) +
      deploy.spec.template.spec.securityContext.withSysctls([
        k.core.v1.sysctl.withName('net.ipv4.ip_unprivileged_port_start') +
        k.core.v1.sysctl.withValue('0'),
      ]) +
      deploy.spec.template.spec.securityContext.seccompProfile.withType('RuntimeDefault'),

    local service = k.core.v1.service,
    local port = k.core.v1.servicePort,
    service:
      service.new('caddy', $.caddy.labels, [
        port.newNamed('http', 80, 80) + port.withProtocol('TCP') + port.withAppProtocol('http'),
        port.newNamed('http2', 443, 443) + port.withProtocol('TCP') + port.withAppProtocol('http2'),
        port.newNamed('http3', 443, 443) + port.withProtocol('UDP') + port.withAppProtocol('http3'),
      ]) +
      service.metadata.withNamespace($.caddy.namespace.metadata.name) +
      service.metadata.withAnnotations({
        'lbipam.cilium.io/ips': '10.200.200.10',
      }) +
      service.metadata.withLabels(
        $.caddy.labels +
        $.cilium.bgp.labels + {
          // caddy-gateway hard-codes this check
          'gateway.caddyserver.com/owning-gateway': $.caddy.gateway.def.metadata.name,
        }
      ) +
      service.spec.withType('LoadBalancer') +
      service.spec.withLoadBalancerClass('io.cilium/bgp-control-plane'),
  },
}
