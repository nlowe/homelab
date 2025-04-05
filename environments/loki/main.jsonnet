local k = import 'k.libsonnet';
local g = (import 'github.com/jsonnet-libs/gateway-api-libsonnet/1.1/main.libsonnet').gateway;

local mixin = import 'github.com/grafana/loki/production/loki-mixin/mixin.libsonnet';
local prom = import 'github.com/jsonnet-libs/prometheus-operator-libsonnet/0.77/main.libsonnet';

local image = (import 'images.libsonnet').loki;

(import 'homelab.libsonnet') +
(import 'github.com/grafana/loki/production/ksonnet/loki/loki.libsonnet') +
{
  _images+:: {
    loki: image.loki.ref(),
    memcached: image.memcached.ref(),
    memcachedExporter: image.memcachedExporter.ref(),
    rollout_operator: image.rollout_operator.ref(),
  },

  _config+:: {
    namespace: 'loki',
    cluster: 'homelab',

    memberlist_ring_enabled: true,
    using_boltdb_shipper: false,
    using_tsdb_shipper: true,

    multi_zone_ingester_enabled: true,

    ingester_pvc_class: 'local-ssd',
    ingester_wal_disk_class: 'local-ssd',
    querier_pvc_class: 'local-ssd',
    ruler_pvc_class: 'local-ssd',
    compactor_pvc_class: 'local-ssd',

    ingester_allow_multiple_replicas_on_same_node: true,

    dns_resolver: 'rke2-coredns-rke2-coredns.kube-system.svc.cluster.local.',

    commonArgs+: {
      'config.expand-env': true,
    },

    // S3 variables -- Remove if not using s3
    storage_backend: 's3',
    // The loki jsonnet manifests make this annoying to point at minio
    client_configs+: {
      s3: {
        endpoint: 'minio.home.nlowe.dev.:9000',
        access_key_id: '${LOKI_S3_ACCESS_KEY_ID}',
        secret_access_key: '${LOKI_S3_SECRET_ACCESS_KEY}',
        s3forcepathstyle: true,
        bucketnames: 'loki',
        region: 'us-east-1',
      },
    },

    //Update the object_store and from fields
    loki+: {
      schema_config: {
        configs: [{
          from: '2025-02-01',
          store: 'tsdb',
          object_store: 's3',
          schema: 'v13',
          index: {
            prefix: '%s_index_' % $._config.table_prefix,
            period: '%dh' % $._config.index_period_hours,
          },
        }],
      },

      // fuck you I won't do what you told me
      limits_config+: {
        max_global_streams_per_user: 0,

        ingestion_rate_mb: 1e9,
        ingestion_burst_size_mb: 1e9,

        retention_period: '30d',
      },

      compactor+: {
        retention_enabled: true,
        delete_request_store: 's3',
      },

      frontend+: {
        tail_proxy_url: 'http://querier.%s.svc.cluster.local:3100' % $._config.namespace,
      },
    },

    replication_factor: 3,
  },

  // TODO: Get this from vault
  mountMinioSecret::
    k.core.v1.container.withEnvFromMixin([
      k.core.v1.envFromSource.secretRef.withName('storage-credentials'),
    ]),

  ingester_container+:: $.mountMinioSecret,
  querier_container+:: $.mountMinioSecret,
  ruler_container+:: $.mountMinioSecret,
  compactor_container+:: $.mountMinioSecret,

  monitoring: {
    local pr = prom.monitoring.v1.prometheusRule,
    rules:
      pr.new('loki') +
      pr.spec.withGroups(
        mixin.prometheusRules.groups +
        mixin.prometheusAlerts.groups,
      ),

    podMonitors: {
      local pm = prom.monitoring.v1.podMonitor,
      local endpoint = pm.spec.podMetricsEndpoints,

      dependencies: {
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

          distributor:
            pm.new('distributor') +
            pm.spec.withPodMetricsEndpoints([
              endpoint.withPort('http-metrics'),
            ]) +
            pm.spec.selector.withMatchLabels({ name: 'distributor' }),

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
            pm.spec.selector.withMatchLabels({ 'rollout-group': 'ingester' }),

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
    },
  },

  gateway: {
    local route = g.v1.httpRoute,
    local rule = route.spec.rules,

    route:
      route.new('loki') +
      route.metadata.withNamespace($._config.namespace) +
      $._config.caddy.gateway.route() +
      route.spec.withHostnames(['loki.home.nlowe.dev']) +
      route.spec.withRules([
        // TODO: Expose query-frontend?
        rule.withBackendRefs([
          rule.backendRefs.withName($.distributor_service.metadata.name) +
          rule.backendRefs.withNamespace($._config.namespace) +
          rule.backendRefs.withPort(3100),
        ]),
      ]),
  },
}
