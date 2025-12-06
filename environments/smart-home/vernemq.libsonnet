local k = import 'k.libsonnet';

local cm = import 'github.com/jsonnet-libs/cert-manager-libsonnet/1.15/main.libsonnet';
local g = (import 'github.com/jsonnet-libs/gateway-api-libsonnet/1.1/main.libsonnet').gateway;
local prom = import 'github.com/jsonnet-libs/prometheus-operator-libsonnet/0.83/main.libsonnet';

local image = import 'images.libsonnet';

{
  vernemq: {
    local this = self,

    labels:: {
      app: 'vernemq',
      selector:: std.join(',', [
        '%s=%s' % [k, this.labels[k]]
        for k in std.objectFields(this.labels)
      ]),
    },
    port:: 8888,

    certs: {
      local issuer = cm.nogroup.v1.issuer,
      local cert = cm.nogroup.v1.certificate,

      ca: {
        issuer:
          issuer.new('selfsigned') +
          issuer.metadata.withNamespace($.namespace.metadata.name) +
          issuer.metadata.withLabels(this.labels) +
          {
            spec: {
              selfSigned: {},
            },
          },

        cert:
          cert.new('vernemq-selfsigned-ca') +
          cert.metadata.withNamespace($.namespace.metadata.name) +
          cert.metadata.withLabels(this.labels) +
          cert.spec.withIsCA(true) +
          cert.spec.withCommonName('vernemq-selfsigned-ca') +
          cert.spec.withSecretName('vernemq-selfsigned-ca') +
          cert.spec.subject.withOrganizations([$.namespace.metadata.name]) +
          cert.spec.withDuration('%dh' % (24 * 365 * 50)) +
          cert.spec.withRenewBefore('%dh' % (24 * 30)) +
          cert.spec.privateKey.withAlgorithm('ECDSA') +
          cert.spec.privateKey.withSize(256) +
          cert.spec.secretTemplate.withLabels(this.labels) +
          cert.spec.issuerRef.withGroup('cert-manager.io') +
          cert.spec.issuerRef.withKind(this.certs.ca.issuer.kind) +
          cert.spec.issuerRef.withName(this.certs.ca.issuer.metadata.name),
      },

      issuer:
        issuer.new('vernemq') +
        issuer.metadata.withNamespace($.namespace.metadata.name) +
        issuer.metadata.withLabels(this.labels) +
        issuer.spec.ca.withSecretName(this.certs.ca.cert.spec.secretName),

      clients: {
        new(name)::
          cert.new('vernemq-%s' % name) +
          cert.metadata.withNamespace($.namespace.metadata.name) +
          cert.metadata.withLabels(this.labels { client: name }) +
          cert.spec.withIsCA(false) +
          cert.spec.withCommonName(name) +
          cert.spec.withSecretName('vernemq-%s-tls' % name) +
          cert.spec.subject.withOrganizations([$.namespace.metadata.name]) +
          cert.spec.withDuration('72h') +
          cert.spec.privateKey.withAlgorithm('ECDSA') +
          cert.spec.privateKey.withSize(256) +
          cert.spec.withUsages('client auth') +
          cert.spec.secretTemplate.withLabels(this.labels { client: name }) +
          cert.spec.issuerRef.withGroup('cert-manager.io') +
          cert.spec.issuerRef.withKind(this.certs.issuer.kind) +
          cert.spec.issuerRef.withName(this.certs.issuer.metadata.name),

        hass:
          self.new('home-assistant') +
          // home-assistant made a really stupid decision and we can't specify the client cert from a mounted file, so
          // unfortunately this ***has*** to be long-lived because they make you point-click configure it through the
          // browser which requires uploading a cert.
          //
          // A cert valid for 30 years should be sufficient right?
          //
          // See: https://www.home-assistant.io/blog/2020/04/14/the-future-of-yaml/
          // See: https://github.com/home-assistant/architecture/blob/master/adr/0010-integration-configuration.md
          cert.spec.withDuration('%dh' % (24 * 365 * 30)) +
          cert.spec.withRenewBefore('%dh' % (24 * 30)),

        mqttx:
          self.new('mqttx') +
          // Long-lived cert for mqttx, runs outside the cluster
          cert.spec.withDuration('%dh' % (24 * 365 * 30)) +
          cert.spec.withRenewBefore('%dh' % (24 * 30)),
      },
    },

    local svc = k.core.v1.service,
    local port = k.core.v1.servicePort,
    service: {
      api:
        svc.new('vernemq-api', this.labels, [
          port.withName('api') + port.withPort(this.port) + port.withTargetPort('api'),
        ]) +
        svc.metadata.withNamespace($.namespace.metadata.name) +
        svc.metadata.withLabels(this.labels),

      app:
        this.service.api +
        svc.metadata.withName('vernemq') +
        svc.spec.withPortsMixin([
          port.withName('empd') + port.withPort(4369),
          port.withName('mqtts') + port.withPort(8883) + port.withTargetPort('mqtts'),
          port.withName('wss') + port.withPort(8443) + port.withTargetPort('wss'),
        ]),

      mqttsExternal:
        svc.new('vernemq-mqtts', this.labels, [
          port.withName('mqtts') + port.withPort(8883) + port.withTargetPort('mqtts'),
        ]) +
        svc.metadata.withNamespace($.namespace.metadata.name) +
        svc.metadata.withLabels(this.labels) +
        $._config.cilium.bgp.serviceMixins.vernemq_mqtts,

      headless:
        this.service.app +
        svc.metadata.withName('vernemq-headless') +
        svc.spec.withClusterIP('None'),
    },

    local sa = k.core.v1.serviceAccount,
    serviceAccount:
      sa.new('vernemq') +
      sa.metadata.withNamespace($.namespace.metadata.name) +
      sa.metadata.withLabels(this.labels),

    local r = k.rbac.v1.role,
    local pr = k.rbac.v1.policyRule,
    role:
      r.new('vernemq') +
      r.metadata.withNamespace($.namespace.metadata.name) +
      r.metadata.withLabels(this.labels) +
      r.withRules([
        pr.withApiGroups(['']) +
        pr.withResources(['pods']) +
        pr.withVerbs(['get', 'list']),

        pr.withApiGroups(['apps']) +
        pr.withResources(['statefulsets']) +
        pr.withVerbs(['get']),
      ]),

    local rb = k.rbac.v1.roleBinding,
    local subject = k.rbac.v1.subject,
    roleBinding:
      rb.new('vernemq') +
      rb.metadata.withNamespace($.namespace.metadata.name) +
      rb.metadata.withLabels(this.labels) +
      rb.withSubjects([
        subject.fromServiceAccount(this.serviceAccount),
      ]) +
      rb.bindRole(this.role),

    local pdb = k.policy.v1.podDisruptionBudget,
    pdb:
      pdb.new('vernemq') +
      pdb.metadata.withNamespace($.namespace.metadata.name) +
      pdb.metadata.withLabels(this.labels) +
      pdb.spec.selector.withMatchLabels(this.labels) +
      pdb.spec.withMinAvailable(1),

    local container = k.core.v1.container,
    local mount = k.core.v1.volumeMount,
    local env = k.core.v1.envVar,
    container::
      image.forContainer('vernemq') +
      container.withPorts([
        { containerPort: 8883, name: 'mqtts' },
        { containerPort: 4369, name: 'epmd' },
        { containerPort: 44053, name: 'vmq' },
        { containerPort: 8080, name: 'ws' },
        { containerPort: 8443, name: 'wss' },
        { containerPort: this.port, name: 'api' },
        { containerPort: 3000, name: 'metrics' },
        // TODO: Helm also exposes 9100 - 9109, wtf is this for?
      ]) +
      container.withEnv([
        env.fromFieldPath('MY_POD_NAME', 'metadata.name'),
        env.fromFieldPath('MY_POD_IP', 'status.podIP'),
        env.new('DOCKER_VERNEMQ_ACCEPT_EULA', 'yes'),
        env.new('DOCKER_VERNEMQ_DISCOVERY_KUBERNETES', '1'),
        env.new('DOCKER_VERNEMQ_KUBERNETES_LABEL_SELECTOR', this.labels.selector),
        // Treat the mTLS Identity as sufficient, don't require a separate auth db entry
        env.new('DOCKER_VERNEMQ_ALLOW_ANONYMOUS', 'on'),
        // TODO: Can we disable this entirely? This seems silly but it doesn't start if you use "off"
        env.new('DOCKER_VERNEMQ_LISTENER__TCP__DEFAULT', '127.0.0.1:1883'),
        env.new('DOCKER_VERNEMQ_LISTENER__WS__DEFAULT', '127.0.0.1:8080'),
        env.new('DOCKER_VERNEMQ_LISTENER__SSL__DEFAULT', '$(MY_POD_IP):8883'),
        env.new('DOCKER_VERNEMQ_LISTENER__WSS__DEFAULT', '$(MY_POD_IP):8443'),
        env.new('DOCKER_VERNEMQ_LISTENER__SSL__ALLOWED_PROTOCOL_VERSIONS', '3,4,5'),
        env.new('DOCKER_VERNEMQ_LISTENER__WSS__ALLOWED_PROTOCOL_VERSIONS', '3,4,5'),
        env.new('DOCKER_VERNEMQ_LISTENER__SSL__REQUIRE_CERTIFICATE', 'on'),
        env.new('DOCKER_VERNEMQ_LISTENER__WSS__REQUIRE_CERTIFICATE', 'on'),
        env.new('DOCKER_VERNEMQ_LISTENER__SSL__USE_IDENTITY_AS_USERNAME', 'on'),
        env.new('DOCKER_VERNEMQ_LISTENER__WSS__USE_IDENTITY_AS_USERNAME', 'on'),
        env.new('DOCKER_VERNEMQ_LISTENER__SSL__CERTFILE', '/var/run/secrets/tls/tls.crt'),
        env.new('DOCKER_VERNEMQ_LISTENER__WSS__CERTFILE', '/var/run/secrets/tls/tls.crt'),
        env.new('DOCKER_VERNEMQ_LISTENER__SSL__KEYFILE', '/var/run/secrets/tls/tls.key'),
        env.new('DOCKER_VERNEMQ_LISTENER__WSS__KEYFILE', '/var/run/secrets/tls/tls.key'),
        env.new('DOCKER_VERNEMQ_LISTENER__SSL__CAFILE', '/var/run/secrets/tls/ca.crt'),
        env.new('DOCKER_VERNEMQ_LISTENER__WSS__CAFILE', '/var/run/secrets/tls/ca.crt'),
        // Add this localhost listener in order to get the port forwarding working
        env.new('DOCKER_VERNEMQ_LISTENER__TCP__LOCALHOST', '127.0.0.1:1883'),
        // TODO: Netsplit config?
      ]) +
      // TODO: Tune resources
      container.startupProbe.httpGet.withPath('/health/ping') +
      container.startupProbe.httpGet.withPort('api') +
      container.startupProbe.withPeriodSeconds(10) +
      container.startupProbe.withTimeoutSeconds(5) +
      container.startupProbe.withSuccessThreshold(1) +
      container.startupProbe.withFailureThreshold(30) +
      container.livenessProbe.httpGet.withPath('/health/ping') +
      container.livenessProbe.httpGet.withPort('api') +
      container.livenessProbe.withPeriodSeconds(10) +
      container.livenessProbe.withTimeoutSeconds(5) +
      container.livenessProbe.withSuccessThreshold(1) +
      container.livenessProbe.withFailureThreshold(3) +
      // TODO: Helm uses /health/ping here but this seems more correct, it will fail if any of the configured listeners are down or suspended
      container.readinessProbe.httpGet.withPath('/health/listeners') +
      container.readinessProbe.httpGet.withPort('api') +
      container.readinessProbe.withPeriodSeconds(10) +
      container.readinessProbe.withTimeoutSeconds(5) +
      container.readinessProbe.withSuccessThreshold(1) +
      container.readinessProbe.withFailureThreshold(3) +
      container.withVolumeMounts([
        mount.new('data', '/vernemq/var', readOnly=false),
        mount.new('tls', '/var/run/secrets/tls', readOnly=true),
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
      sts.new('vernemq', 3, [self.container], [self.pvcTemplate], null) +
      sts.metadata.withNamespace($.namespace.metadata.name) +
      sts.metadata.withLabels(self.labels) +
      sts.spec.withServiceName(self.service.headless.metadata.name) +
      sts.spec.selector.withMatchLabels(self.labels) +
      sts.spec.template.metadata.withLabels(self.labels) +
      sts.spec.template.spec.withServiceAccountName(this.serviceAccount.metadata.name) +
      sts.spec.template.spec.securityContext.withRunAsUser(10000) +
      sts.spec.template.spec.securityContext.withRunAsGroup(10000) +
      sts.spec.template.spec.securityContext.withFsGroup(10000) +
      sts.spec.template.spec.withVolumes([
        volume.fromCsi('tls', 'csi.cert-manager.io', {
          'csi.cert-manager.io/fs-group': '10000',
          'csi.cert-manager.io/issuer-kind': this.certs.issuer.kind,
          'csi.cert-manager.io/issuer-name': this.certs.issuer.metadata.name,
          'csi.cert-manager.io/duration': '72h',
          'csi.cert-manager.io/common-name': '${POD_NAME}.vernemq-headless.${POD_NAMESPACE}.svc.cluster.local',
          'csi.cert-manager.io/dns-names': std.join(',', [
            '${POD_NAME}',
            '${POD_NAME}.vernemq-headless',
            '${POD_NAME}.vernemq-headless.${POD_NAMESPACE}',
            '${POD_NAME}.vernemq-headless.${POD_NAMESPACE}.svc',
            '${POD_NAME}.vernemq-headless.${POD_NAMESPACE}.svc.cluster.local',
            'vernemq',
            'vernemq.${POD_NAMESPACE}',
            'vernemq.${POD_NAMESPACE}.svc',
            'vernemq.${POD_NAMESPACE}.svc.cluster.local',
            'mqtt.home.nlowe.dev',
          ]),
          'csi.cert-manager.io/key-usages': 'server auth',
        }) +
        volume.csi.withReadOnly(true),
      ]) +
      sts.spec.template.spec.withTopologySpreadConstraints([
        tsc.withMaxSkew(1) +
        tsc.withTopologyKey('kubernetes.io/hostname') +
        tsc.withWhenUnsatisfiable('DoNotSchedule') +
        tsc.labelSelector.withMatchLabels(this.labels),
      ]),

    local pm = prom.monitoring.v1.podMonitor,
    local relabel = prom.monitoring.v1.podMonitor.spec.podMetricsEndpoints.metricRelabelings,
    podMonitor:
      pm.new('vernemq') +
      pm.metadata.withNamespace($.namespace.metadata.name) +
      pm.metadata.withLabels(this.labels) +
      pm.spec.withPodMetricsEndpoints([
        pm.spec.podMetricsEndpoints.withPort('api') +
        pm.spec.podMetricsEndpoints.withMetricRelabelings([
          // This label conflicts with the kube node label, drop it, we don't need it
          relabel.withAction('labeldrop') +
          relabel.withRegex('^node$'),
        ]),
      ]) +
      pm.spec.selector.withMatchLabels(this.statefulSet.spec.template.metadata.labels),

    local route = g.v1.httpRoute,
    local rule = route.spec.rules,
    route:
      route.new('vernemq') +
      route.metadata.withNamespace($.namespace.metadata.name) +
      route.metadata.withLabels(this.labels) +
      $._config.caddy.gateway.route() +
      route.spec.withHostnames(['vernemq.home.nlowe.dev']) +
      route.spec.withRules([
        // The status page is hosted at /status, and the root URL just 404s, so redirect to the status page to make it
        // easier to get to in the first place.
        rule.withMatches([
          rule.matches.path.withType('Exact') +
          rule.matches.path.withValue('/'),
        ]) +
        rule.withFilters([
          rule.filters.withType('RequestRedirect') +
          rule.filters.requestRedirect.path.withType('ReplaceFullPath') +
          rule.filters.requestRedirect.path.withReplaceFullPath('/status'),
        ]),

        rule.withBackendRefs([
          rule.backendRefs.withName(this.service.api.metadata.name) +
          rule.backendRefs.withNamespace(this.service.api.metadata.namespace) +
          rule.backendRefs.withPort(this.port),
        ]),
      ]),
  },
}
