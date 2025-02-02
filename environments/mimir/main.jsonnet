local k = import 'k.libsonnet';

local mimir = import 'mimir/mimir.libsonnet';

mimir {
  _config+:: {
    namespace: 'mimir',
    cluster: 'homelab',
    external_url: 'https://mimir.home.nlowe.dev',

    deployment_mode: 'read-write',
    mimir_write_data_disk_class: 'mimir-local',
    mimir_write_allow_multiple_replicas_on_same_node: true,
    mimir_backend_data_disk_class: 'mimir-local',
    mimir_backend_allow_multiple_replicas_on_same_node: true,

    mimir_read_replicas: 3,
    mimir_backend_replicas: 3,

    multi_zone_ingester_enabled: true,
    multi_zone_store_gateway_enabled: true,
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

      // TODO: Tune compactor
      compactor_blocks_retention_period: '9500h',  // ~13 months
    },
  },

  // No HA Write
  etcd:: null,
  distributor_args+:: {
    'distributor.ha-tracker.enable': false,
  },

  // TODO: Get this from vault
  mountMinioSecret::
    k.core.v1.container.withEnvFromMixin([
      k.core.v1.envFromSource.secretRef.withName('storage-credentials'),
    ]),

  mimir_write_container+:: $.mountMinioSecret,
  mimir_read_container+:: $.mountMinioSecret,
  mimir_backend_container+:: $.mountMinioSecret,
}
