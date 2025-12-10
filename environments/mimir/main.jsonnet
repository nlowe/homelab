local k = import 'k.libsonnet';
local container = k.core.v1.container;
local envVar = k.core.v1.envVar;

local g = (import 'github.com/jsonnet-libs/gateway-api-libsonnet/1.1/main.libsonnet').gateway;

local mixin = import 'github.com/grafana/mimir/operations/mimir-mixin/mixin.libsonnet';
local prom = import 'github.com/jsonnet-libs/prometheus-operator-libsonnet/0.83/main.libsonnet';

local es = (import 'github.com/jsonnet-libs/external-secrets-libsonnet/0.19/main.libsonnet').nogroup.v1.externalSecret;

local image = (import 'images.libsonnet').mimir;

(import 'homelab.libsonnet') +
(import 'kafka.libsonnet') +
(import 'github.com/grafana/mimir/operations/mimir/mimir.libsonnet') +
{
  _images+:: {
    mimir: image.mimir.ref(),
    memcached: image.memcached.ref(),
    memcachedExporter: image.memcachedExporter.ref(),
    query_tee: image.query_tee.ref(),
    continuous_test: image.continuous_test.ref(),
    rollout_operator: image.rollout_operator.ref(),
  },

  _config+:: {
    namespace: 'mimir',
    cluster: 'homelab',
    external_url: 'https://mimir.home.nlowe.dev',
    usage_stats_enabled: false,

    ingest_storage_enabled: true,
    ingest_storage_kafka_backend: 'kafka',
    replication_factor: 2,
    store_gateway_replication_factor: 2,

    query_sharding_enabled: true,

    storageClass:: 'local-ssd',
    alertmanager_data_disk_class: $._config.storageClass,
    ingester_data_disk_class: $._config.storageClass,
    store_gateway_data_disk_class: $._config.storageClass,
    compactor_data_disk_class: $._config.storageClass,

    storage_backend: 's3',
    blocks_storage_bucket_name: 'mimir',
    blocksStorageConfig+: { 'blocks-storage.storage-prefix': 'blocks' },
    ruler_storage_bucket_name: 'mimir',
    rulerStorageConfig+: { 'ruler-storage.storage-prefix': 'ruler' },
    alertmanager_storage_bucket_name: 'mimir',
    alertmanagerStorageConfig+: { 'alertmanager-storage.storage-prefix': 'alertmanager' },
    storage_s3_endpoint: 'minio.home.nlowe.dev:9000',
    storage_s3_access_key_id: '$(MIMIR_S3_ACCESS_KEY_ID)',
    storage_s3_secret_access_key: '$(MIMIR_S3_SECRET_ACCESS_KEY)',
    aws_region: 'us-east-1',

    // Enable concurrent rollout of compactor through the usage of the rollout operator.
    rollout_operator_webhooks_enabled: true,
    zpdb_custom_resource_definition_enabled: true,
    replica_template_custom_resource_definition_enabled: true,
    cortex_compactor_concurrent_rollout_enabled: true,

    overrides_exporter_enabled: true,
    overrides_exporter_presets:: [],

    ruler_enabled: true,
    // Required for ingest storage
    ruler_remote_evaluation_enabled: true,

    // Replica Counts and "Zone" setup
    multi_zone_availability_zones: ['a', 'b', 'c'],

    ingester_allow_multiple_replicas_on_same_node: true,
    store_gateway_allow_multiple_replicas_on_same_node: true,

    multi_zone_ingester_enabled: true,
    multi_zone_store_gateway_enabled: true,
    multi_zone_distributor_enabled: true,

    // TODO: Turn these on when they get released
    // multi_zone_querier_enabled: true,
    // multi_zone_query_frontend_enabled: true,
    // multi_zone_query_scheduler_enabled: true,
    // multi_zone_memcached_enabled: true,

    // TODO: multi_zone_distributor_replicas? Defaults to the number of AZs
    // TODO: Querier replicas? Defaults to 2 per zone
    // TODO: Query Frontend replicas?
    // TODO: Query Scheduler replicas?
    // TODO: Ruler replicas? Defaults to 2 per zone
    // TODO: Remote Ruler Querier replicas? Defaults to 2 per zone
    multi_zone_ingester_replicas: 1 * std.length($._config.multi_zone_availability_zones),
    multi_zone_store_gateway_replicas: 1 * std.length($._config.multi_zone_availability_zones),

    // TODO: Turn these on when they get released
    // // One Replica per Zone
    // memcached_frontend_replicaa: 1,
    // memcached_index_queries_replicas: 1,
    // memcached_chunks_replicas: 1,
    // memcached_metadata_replicas: 1,

    // fuck you I won't do what you told me
    limits: {
      max_global_series_per_user: 0,
      max_global_metadata_per_user: 0,
      max_global_metadata_per_metric: 0,

      ingestion_rate: 1e9,
      ingestion_burst_size: 1e9,

      ruler_max_rules_per_rule_group: 0,
      ruler_max_rule_groups_per_tenant: 0,
      ruler_max_independent_rule_evaluation_concurrency_per_tenant: 0,

      // TODO: Tune compactor
      compactor_blocks_retention_period: '9500h',  // ~13 months
    },
  },

  ingest_storage_kafka_producer_address:: 'homelab-kafka-bootstrap.strimzi-system.svc.cluster.local:9092',
  ingest_storage_kafka_consumer_address:: 'homelab-kafka-bootstrap.strimzi-system.svc.cluster.local:9092',
  ingest_storage_kafka_client_args+:: {
    'ingest-storage.kafka.topic': $.kafka.topic.metadata.name,
    'ingest-storage.kafka.auto-create-topic-default-partitions': $.kafka.topic.spec.config['num.partitions'],
  },

  // No HA Write
  etcd:: null,
  distributor_args+:: {
    'distributor.ha-tracker.enable': false,
  },

  storageCredentialsSecret:
    $._config.externalSecret.new('storage-credentials', $._config.namespace) +
    es.spec.withData([
      es.spec.data.withSecretKey('MIMIR_S3_ACCESS_KEY_ID') +
      es.spec.data.remoteRef.withKey('f9509267-d0c2-4c0d-9bf4-b31801580da4'),

      es.spec.data.withSecretKey('MIMIR_S3_SECRET_ACCESS_KEY') +
      es.spec.data.remoteRef.withKey('3792ddc3-1fba-4c09-b91a-b31801582588'),
    ]),

  minioEnvCredentials::
    k.core.v1.container.withEnvFromMixin([
      k.core.v1.envFromSource.secretRef.withName($.storageCredentialsSecret.metadata.name),
    ]),

  // TODO: Actually use SASL and/or mTLS: https://github.com/grafana/mimir/issues/13366
  kafkaEnvCredentials:: container.withEnvMixin([
    envVar.new('MIMIR_KAFKA_USERNAME', 'mimir'),
    envVar.fromSecretRef('MIMIR_KAFKA_PASSWORD', $.kafka.userSecret.metadata.name, 'user.password'),
  ]),

  distributor_container+:: $.kafkaEnvCredentials,
  ingester_container+:: $.minioEnvCredentials + $.kafkaEnvCredentials,
  store_gateway_container+:: $.minioEnvCredentials,
  compactor_container+:: $.minioEnvCredentials,

  monitoring: {
    local pr = prom.monitoring.v1.prometheusRule,
    rules:
      pr.new('mimir') +
      pr.spec.withGroups(
        mixin.prometheusRules.groups +
        mixin.prometheusAlerts.groups,
      ),

    podMonitors: {
      local pm = prom.monitoring.v1.podMonitor,
      local endpoint = pm.spec.podMetricsEndpoints,

      dependencies: {
        // TODO: Update for zonal memcached
        memcached: {
          main:
            pm.new('memcached') +
            pm.spec.withPodMetricsEndpoints([
              endpoint.withPort('http-metrics'),
            ]) +
            pm.spec.selector.withMatchLabels({ name: 'memcached' }),

          frontend:
            pm.new('memcached-frontend') +
            pm.spec.withPodMetricsEndpoints([
              endpoint.withPort('http-metrics'),
            ]) +
            pm.spec.selector.withMatchLabels({ name: 'memcached-frontend' }),

          indexQueries:
            pm.new('memcached-index-queries') +
            pm.spec.withPodMetricsEndpoints([
              endpoint.withPort('http-metrics'),
            ]) +
            pm.spec.selector.withMatchLabels({ name: 'memcached-index-queries' }),

          metadata:
            pm.new('memcached-metadata') +
            pm.spec.withPodMetricsEndpoints([
              endpoint.withPort('http-metrics'),
            ]) +
            pm.spec.selector.withMatchLabels({ name: 'memcached-metadata' }),
        },
      },

      distributor:
        pm.new('distributor') +
        pm.spec.withPodMetricsEndpoints([
          endpoint.withPort('http-metrics'),
        ]) +
        pm.spec.selector.withMatchExpressions([
          pm.spec.selector.matchExpressions.withKey('name') +
          pm.spec.selector.matchExpressions.withOperator('In') +
          pm.spec.selector.matchExpressions.withValues([
            'distributor-zone-a',
            'distributor-zone-b',
            'distributor-zone-c',
          ]),
        ]),

      query_scheduler:
        pm.new('query-scheduler') +
        pm.spec.withPodMetricsEndpoints([
          endpoint.withPort('http-metrics'),
        ]) +
        pm.spec.selector.withMatchLabels({ name: 'query-scheduler' }),

      query_frontend:
        pm.new('query-frontend') +
        pm.spec.withPodMetricsEndpoints([
          endpoint.withPort('http-metrics'),
        ]) +
        pm.spec.selector.withMatchLabels({ name: 'query-frontend' }),

      querier:
        pm.new('querier') +
        pm.spec.withPodMetricsEndpoints([
          endpoint.withPort('http-metrics'),
        ]) +
        pm.spec.selector.withMatchLabels({ name: 'querier' }),

      ingester:
        pm.new('ingester') +
        pm.spec.withPodMetricsEndpoints([
          endpoint.withPort('http-metrics'),
        ]) +
        pm.spec.selector.withMatchExpressions([
          pm.spec.selector.matchExpressions.withKey('name') +
          pm.spec.selector.matchExpressions.withOperator('In') +
          pm.spec.selector.matchExpressions.withValues([
            'ingester-zone-a',
            'ingester-zone-b',
            'ingester-zone-c',
          ]),
        ]),

      store_gateway:
        pm.new('store-gateway') +
        pm.spec.withPodMetricsEndpoints([
          endpoint.withPort('http-metrics'),
        ]) +
        pm.spec.selector.withMatchExpressions([
          pm.spec.selector.matchExpressions.withKey('name') +
          pm.spec.selector.matchExpressions.withOperator('In') +
          pm.spec.selector.matchExpressions.withValues([
            'store-gateway-zone-a',
            'store-gateway-zone-b',
            'store-gateway-zone-c',
          ]),
        ]),

      compactor:
        pm.new('compactor') +
        pm.spec.withPodMetricsEndpoints([
          endpoint.withPort('http-metrics'),
        ]) +
        pm.spec.selector.withMatchLabels({ name: 'compactor' }),

      rolloutOperator:
        pm.new('rollout-operator') +
        pm.spec.withPodMetricsEndpoints([
          endpoint.withPort('http-metrics'),
        ]) +
        pm.spec.selector.withMatchLabels({ name: 'rollout-operator' }),
    },
  },

  gateway: {
    local route = g.v1.httpRoute,
    local rule = route.spec.rules,

    route:
      route.new('mimir') +
      route.metadata.withNamespace($._config.namespace) +
      $._config.caddy.gateway.route() +
      route.spec.withHostnames(['mimir.home.nlowe.dev']) +
      route.spec.withRules([
        rule.withMatches([
          rule.matches.path.withType('Exact') +
          rule.matches.path.withValue(path)
          for path in [
            '/api/v1/push',
            '/distributor/all_user_stats',
            '/distributor/ha_tracker',
          ]
        ]) +
        rule.withBackendRefs([
          rule.backendRefs.withName(service.metadata.name) +
          rule.backendRefs.withNamespace($._config.namespace) +
          rule.backendRefs.withPort(8080)
          for service in [
            $.distributor_zone_a_service,
            $.distributor_zone_b_service,
            $.distributor_zone_c_service,
          ]
        ]),

        rule.withMatches([
          rule.matches.path.withType('PathPrefix') +
          rule.matches.path.withValue('/prometheus'),
        ]) +
        rule.withBackendRefs([
          rule.backendRefs.withName($.query_frontend_service.metadata.name) +
          rule.backendRefs.withNamespace($._config.namespace) +
          rule.backendRefs.withPort(8080),
        ]),
      ]),
  },
}
