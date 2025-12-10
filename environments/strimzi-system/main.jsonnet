local k = import 'k.libsonnet';
local g = (import 'github.com/jsonnet-libs/gateway-api-libsonnet/1.1/main.libsonnet').gateway;

local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local helm = tk.helm.new(std.thisFile);

local mixin = import 'github.com/grafana/mimir/operations/mimir-mixin/mixin.libsonnet';
local prom = import 'github.com/jsonnet-libs/prometheus-operator-libsonnet/0.83/main.libsonnet';

local es = (import 'github.com/jsonnet-libs/external-secrets-libsonnet/0.19/main.libsonnet').nogroup.v1.externalSecret;

local image = (import 'images.libsonnet').strimzi;

// TODO: Upgrade to v1 when jsonnet-libs gets 0.49
local kafka = (import 'github.com/jsonnet-libs/strimzi-libsonnet/0.48/main.libsonnet').kafka.v1beta2;

(import 'homelab.libsonnet') +
{
  _config+:: {
    namespace: 'strimzi-system',
    version: {
      // See https://strimzi.io/downloads/
      kafka: '4.1.1',
      metadata: '4.1-IV1',
    },

    // See https://github.com/strimzi/strimzi-kafka-operator/tree/main/helm-charts/helm3/strimzi-kafka-operator
    helm_values:: {
      defaultImageTag: image.operator.version,
      podDisruptionBudget: {
        enabled: true,
      },

      resources: {
        limits: {
          memory: '4Gi',
        },
      },

      generateNetworkPolicy: false,
    },
  },

  operator: helm.template('strimzi-kafka-operator', '../../charts/strimzi-kafka-operator', {
    namespace: $._config.namespace,
    values: $._config.helm_values,
    nameFormat: '{{ print .metadata.namespace "_" .kind "_" .metadata.name | snakecase }}',
  }),

  // TODO: Monitoring

  local nodePool = kafka.kafkaNodePool,
  nodePool:
    nodePool.new('nodes') +
    nodePool.metadata.withNamespace($._config.namespace) +
    nodePool.metadata.withLabels($._config.strimzi.clusterLabel) +
    nodePool.spec.withReplicas(3) +
    nodePool.spec.withRoles(['broker', 'controller']) +
    nodePool.spec.storage.withType('persistent-claim') +
    nodePool.spec.storage.withSize('100Gi') +
    nodePool.spec.storage.withClass('local-ssd'),

  local cluster = kafka.kafka,
  local listener = cluster.spec.kafka.listeners,
  cluster:
    cluster.new('homelab') +
    cluster.metadata.withNamespace($._config.namespace) +
    cluster.spec.kafka.withVersion($._config.version.kafka) +
    cluster.spec.kafka.withMetadataVersion($._config.version.metadata) +
    cluster.spec.kafka.withListeners([

      listener.withName('plain') +
      listener.withPort(9092) +
      listener.withType('internal') +
      listener.withTls(false),

      listener.withName('tls') +
      listener.withPort(9093) +
      listener.withType('internal') +
      listener.withTls(true),
    ]) +
    cluster.spec.kafka.authorization.withType('simple') +
    cluster.spec.kafka.authorization.withSuperUsers([
      'nlowe',
      'CN=nlowe',
    ]) +
    cluster.spec.kafka.withConfig({
      'offsets.topic.replication.factor': 3,
      'transaction.state.log.replication.factor': 3,
      'transaction.state.log.min.isr': 2,
      'num.partitions': 3,
      'default.replication.factor': 2,
      'min.insync.replicas': 2,
      'auto.create.topics.enable': false,
    }) +
    {
      spec+: {
        entityOperator+: {
          topicOperator+: {},
          userOperator+: {},
        },
      },
    },

  local user = kafka.kafkaUser,
  local acl = user.spec.authorization.acls,
  user:
    user.new('nlowe') +
    user.metadata.withNamespace('strimzi-system') +
    user.metadata.withLabels($._config.strimzi.clusterLabel) +
    user.spec.authentication.withType('tls'),
}
