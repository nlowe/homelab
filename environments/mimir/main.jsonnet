local k = import 'k.libsonnet';
local g = (import 'github.com/jsonnet-libs/gateway-api-libsonnet/1.2/main.libsonnet').gateway;

local mixin = import 'github.com/grafana/mimir/operations/mimir-mixin/mixin.libsonnet';
local prom = import 'github.com/jsonnet-libs/prometheus-operator-libsonnet/0.83/main.libsonnet';

local es = (import 'github.com/jsonnet-libs/external-secrets-libsonnet/0.19/main.libsonnet').nogroup.v1.externalSecret;

local image = (import 'images.libsonnet').mimir;

(import 'homelab.libsonnet') +
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
    // TODO: Kafka after https://github.com/grafana/mimir/issues/13366 is fixed

    namespace: 'mimir',
    cluster: 'homelab',
    external_url: 'https://mimir.home.nlowe.dev',

    alertmanager_enabled: true,
    ruler_enabled: true,

    storage_class:: 'local-ssd',
    alertmanager_data_disk_class: $._config.storage_class,
    ingester_data_disk_class: $._config.storage_class,
    ingester_allow_multiple_replicas_on_same_node: true,
    store_gateway_data_disk_class: $._config.storage_class,
    store_gateway_allow_multiple_replicas_on_same_node: true,
    compactor_data_disk_class: $._config.storage_class,

    multi_zone_availability_zones: ['a', 'b', 'c'],
    multi_zone_distributor_enabled: true,
    multi_zone_ingester_enabled: true,
    multi_zone_ingester_replicas: 3,
    multi_zone_store_gateway_enabled: true,
    multi_zone_store_gateway_replicas: 3,
    ruler_remote_evaluation_enabled: false,

    // Disable microservices autoscaling.
    autoscaling_querier_enabled: false,
    autoscaling_ruler_querier_enabled: false,

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

  // Annoyingly, the mimir manifests configure these for us for distributors but not for anything else
  ingester_zone_a_node_affinity_matchers+:: [$.newMimirNodeAffinityMatcherAZ($._config.multi_zone_availability_zones[0])],
  ingester_zone_b_node_affinity_matchers+:: [$.newMimirNodeAffinityMatcherAZ($._config.multi_zone_availability_zones[1])],
  ingester_zone_c_node_affinity_matchers+:: [$.newMimirNodeAffinityMatcherAZ($._config.multi_zone_availability_zones[2])],
  store_gateway_zone_a_node_affinity_matchers+:: [$.newMimirNodeAffinityMatcherAZ($._config.multi_zone_availability_zones[0])],
  store_gateway_zone_b_node_affinity_matchers+:: [$.newMimirNodeAffinityMatcherAZ($._config.multi_zone_availability_zones[1])],
  store_gateway_zone_c_node_affinity_matchers+:: [$.newMimirNodeAffinityMatcherAZ($._config.multi_zone_availability_zones[2])],

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

  mountMinioSecret::
    k.core.v1.container.withEnvFromMixin([
      k.core.v1.envFromSource.secretRef.withName($.storageCredentialsSecret.metadata.name),
    ]),

  ingester_container+:: $.mountMinioSecret,
  querier_container+:: $.mountMinioSecret,
  alertmanager_container+:: $.mountMinioSecret,
  ruler_container+:: $.mountMinioSecret,
  compactor_container+:: $.mountMinioSecret,
  store_gateway_container+:: $.mountMinioSecret,

  // Make a generic distributor service for in-cluster alloy
  distributor_zone_labels:: {
    'part-of': 'distributor',
  },

  distributor_label_mixin::
    k.apps.v1.deployment.spec.template.metadata.withLabelsMixin(
      $.distributor_zone_labels
    ),

  distributor_zone_a_deployment+: $.distributor_label_mixin,
  distributor_zone_b_deployment+: $.distributor_label_mixin,
  distributor_zone_c_deployment+: $.distributor_label_mixin,

  local svc = k.core.v1.service,
  distributor_zone_all_service:
    svc.new('distributor', $.distributor_zone_labels, $.distributor_zone_a_service.spec.ports),

  ruler_args+:: {
    // Mimir configures the wrong port by default
    'ruler.alertmanager-url': 'http://alertmanager.%(namespace)s.svc.%(cluster_domain)s:8080/alertmanager' % $._config,
  },

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

      local newPodMonitor(name, matchLabels=null) =
        pm.new(name) +
        pm.spec.withPodMetricsEndpoints([
          endpoint.withPort('http-metrics'),
        ]) +
        pm.spec.selector.withMatchLabels(if matchLabels != null then matchLabels else { name: name }),

      dependencies: {
        memcached: {
          main: newPodMonitor('memcached'),
          frontend: newPodMonitor('memcached-frontend'),
          indexQueries: newPodMonitor('memcached-index-queries'),
          metadata: newPodMonitor('memcached-metadata'),
        },

        rolloutOperator: newPodMonitor('rollout-operator'),
      },

      alertmanager: newPodMonitor('alertmanager'),
      compactor: newPodMonitor('compactor'),
      distributor: newPodMonitor('distributor', $.distributor_zone_labels),
      ingester: newPodMonitor('ingester', { 'rollout-group': 'ingester' }),
      querier: newPodMonitor('querier'),
      query_frontend: newPodMonitor('query-frontend'),
      query_scheduler: newPodMonitor('query-scheduler'),
      ruler: newPodMonitor('ruler'),
      store_gateway: newPodMonitor('store-gateway', { 'rollout-group': 'store-gateway' }),
    },
  },

  gateway: {
    local route = g.v1.httpRoute,
    local rule = route.spec.rules,
    route:
      route.new('mimir') +
      route.metadata.withNamespace($._config.namespace) +
      $._config.cilium.gateway.route() +
      route.spec.withHostnames(['mimir.home.nlowe.dev']) +
      route.spec.withRules([
        // TODO: Expose query-frontend?
        rule.withBackendRefs([
          rule.backendRefs.withName($.distributor_zone_all_service.metadata.name) +
          rule.backendRefs.withNamespace($._config.namespace) +
          rule.backendRefs.withPort(8080),
        ]),
      ]),
  },
}
// Remove CPU Requests, most of these are stuck on specific nodes due to local SSD usage
{
  local removeCPURequests = { resources+: { requests+: { cpu:: null } } },

  memcached+:: {
    memcached_container+: removeCPURequests,
    memcached_exporter+: removeCPURequests,
  },

  alertmanager_container+: removeCPURequests,
  compactor_container+: removeCPURequests,
  distributor_container+: removeCPURequests,
  ingester_container+: removeCPURequests,
  querier_container+: removeCPURequests,
  query_frontend_container+: removeCPURequests,
  query_scheduler_container+: removeCPURequests,
  ruler_container+: removeCPURequests,
  store_gateway_container+: removeCPURequests,
}
