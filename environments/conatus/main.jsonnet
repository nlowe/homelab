local k = import 'k.libsonnet';
local g = (import 'github.com/jsonnet-libs/gateway-api-libsonnet/1.4/main.libsonnet').gateway;

local image = import 'images.libsonnet';

local es = (import 'github.com/jsonnet-libs/external-secrets-libsonnet/1.1/main.libsonnet').nogroup.v1.externalSecret;
local cnpg = (import 'github.com/jsonnet-libs/cloudnative-pg-libsonnet/1.27.0/main.libsonnet').postgresql.v1;

local prom = import 'github.com/jsonnet-libs/prometheus-operator-libsonnet/0.86/main.libsonnet';
local pm = prom.monitoring.v1.podMonitor;
local endpoint = pm.spec.podMetricsEndpoints;

(import 'homelab.libsonnet') +
{
  labels:: { app: 'conatus' },
  port:: 3000,

  namespace: k.core.v1.namespace.new('conatus'),

  db: {
    credentials:
      $._config.externalSecret.new('conatus-db-user', $.namespace.metadata.name) +
      es.spec.withData([
        es.spec.data.withSecretKey('data') +
        es.spec.data.remoteRef.withKey('717f1282-5e79-4b06-8583-b4d60125da54'),
      ]) +
      es.spec.target.template.metadata.withLabels({
        'cnpg.io/reload': 'true',
      }) +
      es.spec.target.template.withType('kubernetes.io/basic-auth') +
      es.spec.target.template.withEngineVersion('v2') +
      es.spec.target.template.withData({
        username: 'conatus',
        password: '{{ .data }}',
        uri: 'postgresql://conatus:{{ .data | urlquery }}@conatus-db-rw.conatus.svc.cluster.local.:5432/conatus',
      }),

    local cluster = cnpg.cluster,
    cluster:
      cluster.new('conatus-db') +
      cluster.metadata.withNamespace($.namespace.metadata.name) +
      cluster.spec.withInstances(1) +
      cluster.spec.withImageName(image.pg.ref()) +
      cluster.spec.storage.withSize('10Gi') +
      cluster.spec.storage.pvcTemplate.withAccessModes('ReadWriteOnce') +
      cluster.spec.storage.pvcTemplate.withStorageClassName('iscsi'),

    // TODO: Use jsonnet-libs when it gets updated to use this resource
    role: {
      apiVersion: 'postgresql.cnpg.io/v1',
      kind: 'DatabaseRole',
      metadata: {
        name: 'conatus',
        namespace: $.namespace.metadata.name,
      },
      spec: {
        cluster: {
          name: $.db.cluster.metadata.name,
        },

        name: 'conatus',
        comment: 'conatus Database Account',
        login: true,

        passwordSecret: {
          name: $.db.credentials.metadata.name,
        },
      },
    },

    local db = cnpg.database,
    db:
      db.new('conatus-db') +
      db.metadata.withNamespace($.namespace.metadata.name) +
      db.spec.withName('conatus') +
      db.spec.withOwner($.db.role.spec.name) +
      db.spec.cluster.withName($.db.cluster.metadata.name),

    podMonitor:
      pm.new('conatus-db') +
      pm.spec.withPodMetricsEndpoints([
        endpoint.withPort('metrics'),
      ]) +
      pm.spec.selector.withMatchLabels({
        'cnpg.io/cluster': 'conatus-db',
      }),
  },

  authSecret:
    $._config.externalSecret.new('conatus-auth-secret', $.namespace.metadata.name) +
    es.spec.withData(
      es.spec.data.withSecretKey('AUTH_SECRET') +
      es.spec.data.remoteRef.withKey('453690b2-c9b1-4dc3-95df-b4d6012d23c9')
    ),

  s3Config:
    $._config.externalSecret.new('s3-config', $.namespace.metadata.name) +
    es.spec.withData([
      es.spec.data.withSecretKey('data') +
      es.spec.data.remoteRef.withKey('05dd6e75-8ca7-47b5-9c07-b4d601212aa1'),
    ]) +
    es.spec.target.template.withEngineVersion('v2') +
    es.spec.target.template.withData({
      S3_ENDPOINT: 'minio.home.nlowe.dev',
      S3_PORT: '9000',
      S3_BUCKET: 'conatus',
      S3_ACCESS_KEY: 'conatus',
      S3_SECRET_KEY: '{{ .data }}',
    }),

  local container = k.core.v1.container,
  local env = k.core.v1.envVar,
  local envFrom = k.core.v1.envFromSource,
  containers:: {
    migrate:
      image.forContainer('conatus-ops', container_name='migrate', group=image.conatus) +
      container.withCommand(['npm', 'run', 'migrate']) +
      container.withEnv([
        env.fromSecretRef('DATABASE_URL', $.db.credentials.metadata.name, 'uri'),
      ]),

    app:
      image.forContainer('conatus', group=image.conatus) +
      container.withPorts([
        { containerPort: $.port, name: 'http', protocol: 'TCP' },
      ]) +
      // TODO: Tune resources
      container.livenessProbe.httpGet.withPath('/api/health') +
      container.livenessProbe.httpGet.withPort($.port) +
      container.withEnv([
        env.fromSecretRef('DATABASE_URL', $.db.credentials.metadata.name, 'uri'),

        env.new('AUTH_URL', 'https://todo.home.nlowe.dev'),
        env.new('PUBLIC_BASE_URL', 'https://todo.home.nlowe.dev'),

        env.new('REGISTRATION_MODE', 'invite-only'),
        env.new('CONATUS_DEV_MODE', '0'),

        // TODO: SMPT_* after we configure proton mail proxy
      ]) +
      container.withEnvFrom([
        envFrom.secretRef.withName($.authSecret.metadata.name),
        envFrom.secretRef.withName($.s3Config.metadata.name),
      ]),
  },

  local deploy = k.apps.v1.deployment,
  deployment:
    deploy.new('conatus', 1, [$.containers.app], $.labels) +
    deploy.metadata.withLabels($.labels) +
    deploy.spec.template.spec.withInitContainers([$.containers.migrate]),

  local svc = k.core.v1.service,
  local port = k.core.v1.servicePort,
  service:
    svc.new('conatus', $.labels, [
      port.withName('http') +
      port.withPort($.port) +
      port.withTargetPort('http'),
    ]) +
    svc.metadata.withNamespace($.namespace.metadata.name) +
    svc.metadata.withLabels($.labels),

  local route = g.v1.httpRoute,
  local rule = route.spec.rules,
  route:
    route.new('conatus') +
    route.metadata.withNamespace($.namespace.metadata.name) +
    $._config.cilium.gateway.route() +
    route.spec.withHostnames(['todo.home.nlowe.dev']) +
    route.spec.withRules([
      rule.withBackendRefs([
        rule.backendRefs.withName($.service.metadata.name) +
        rule.backendRefs.withNamespace($.service.metadata.namespace) +
        rule.backendRefs.withPort($.port),
      ]),
    ]),
}
