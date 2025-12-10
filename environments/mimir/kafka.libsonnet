local k = import 'k.libsonnet';
local g = (import 'github.com/jsonnet-libs/gateway-api-libsonnet/1.1/main.libsonnet').gateway;

local mixin = import 'github.com/grafana/mimir/operations/mimir-mixin/mixin.libsonnet';
local prom = import 'github.com/jsonnet-libs/prometheus-operator-libsonnet/0.83/main.libsonnet';

local es = (import 'github.com/jsonnet-libs/external-secrets-libsonnet/0.19/main.libsonnet').nogroup.v1.externalSecret;

// TODO: Upgrade to v1 when jsonnet-libs gets 0.49
local kafka = (import 'github.com/jsonnet-libs/strimzi-libsonnet/0.48/main.libsonnet').kafka.v1beta2;

{
  kafka+: {
    local topic = kafka.kafkaTopic,
    topic:
      topic.new('mimir') +
      topic.metadata.withNamespace('strimzi-system') +
      topic.metadata.withLabels($._config.strimzi.clusterLabel) +
      topic.spec.withConfig({
        'num.partitions': 500,
        'retention.ms': 12 * 60 * 60 * 1000,  // 12h
        'segment.bytes': 256 * 1024 * 1024,  // 256Mb
      }),

    local user = kafka.kafkaUser,
    local acl = user.spec.authorization.acls,
    user:
      user.new('mimir') +
      user.metadata.withNamespace('strimzi-system') +
      user.metadata.withLabels($._config.strimzi.clusterLabel) +
      // https://github.com/grafana/mimir/issues/13366
      // user.spec.authentication.withType('tls') +
      user.spec.authorization.withType('simple') +
      user.spec.authorization.withAcls([
        acl.resource.withType('topic') +
        acl.resource.withName($.kafka.topic.metadata.name) +
        acl.resource.withPatternType('literal') +
        acl.withOperations(['All']) +
        acl.withHost('*'),

        acl.resource.withType('group') +
        acl.resource.withName('ingester-') +
        acl.resource.withPatternType('prefix') +
        acl.withOperations(['All']) +
        acl.withHost('*'),
      ]) +
      user.spec.template.secret.metadata.withAnnotationsMixin(
        $._config.reflector.toNamespaces(['mimir']).metadata.annotations
      ),

    local secret = k.core.v1.secret,
    userSecret:
      secret.new('kafka-user', {}, 'Opaque') +
      $._config.reflector.from($.kafka.user.metadata.namespace, $.kafka.user.metadata.name) +
      { data:: null },
  },
}
