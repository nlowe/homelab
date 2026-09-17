local k = import 'k.libsonnet';
local g = (import 'github.com/jsonnet-libs/gateway-api-libsonnet/1.4/main.libsonnet').gateway;

local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local helm = tk.helm.new(std.thisFile);

local image = import 'images.libsonnet';

local es = (import 'github.com/jsonnet-libs/external-secrets-libsonnet/1.1/main.libsonnet').nogroup.v1.externalSecret;
local cnpg = (import 'github.com/jsonnet-libs/cloudnative-pg-libsonnet/1.27.0/main.libsonnet').postgresql.v1;

(import 'homelab.libsonnet') +
{
  _config+:: {
    helm_values: {
      controllers: {
        main: {
          containers: {
            main: {
              image: {
                image:: image.immich.server,

                repository: self.image.repo(),
                tag: self.image.version,
              },
              env: {
                TZ: 'America/New_York',

                IMMICH_TELEMETRY_INCLUDE: 'all',

                DB_HOSTNAME: 'immich-db-rw',
                DB_USERNAME: 'immich',
                DB_DATABASE_NAME: 'immich',
                DB_PASSWORD: {
                  valueFrom: {
                    secretKeyRef: {
                      name: 'immich-db-user',
                      key: 'password',
                    },
                  },
                },
              },
              securityContext: {
                runAsNonRoot: true,
                runAsUser: $._config.media.uid,
                runAsGroup: $._config.media.gid,
              },
            },
          },

          pod+: {
            securityContext: {
              fsGroup: $._config.media.gid,
              fsGroupChangePolicy: 'OnRootMismatch',
            },
          },
        },
      },

      immich: {
        metrics: {
          // TODO: No metrics for machine-learning?
          // TODO: PodMonitor for postgres and valkey
          enabled: true,
        },
        persistence: {
          library: {
            existingClaim: $.library.pvc.metadata.name,
          },
        },

        // https://immich.app/docs/install/config-file/
        // Handled in the UI
        configuration: {},
      },

      server: {
        enabled: true,
        controllers: {
          main: {
            containers: {
              main: {
                image: {
                  image:: image.immich.server,

                  repository: self.image.repo(),
                  tag: self.image.version,
                },
              },
            },
          },
        },
        ingress: {
          main: {
            enabled: false,
          },
        },

        serviceMonitor: {
          main: {
            enabled: false,
          },
        },

        podMonitor: {
          main: {
            enabled: true,
            podMetricsEndpoints: [
              { port: 'metrics-api', scheme: 'http' },
              { port: 'metrics-ms', scheme: 'http' },
            ],
          },
        },
      },

      'machine-learning': {
        enabled: true,
        controllers: {
          main: {
            containers: {
              main: {
                image: {
                  image:: image.immich['machine-learning'],

                  repository: self.image.repo(),
                  tag: self.image.version,
                },
                env: {
                  // TODO: Customize?
                  TRANSFORMERS_CACHE: '/cache',
                  HF_XET_CACHE: '/cache/huggingface-xet',
                  MPLCONFIGDIR: '/cache/matplotlib-config',
                },
              },
            },
          },
        },
        persistence: {
          cache: {
            enabled: true,
            type: 'persistentVolumeClaim',
            accessMode: 'ReadWriteMany',
            size: '10Gi',
            storageClass: 'nfs',
          },
        },
      },

      valkey: {
        enabled: true,
        controllers: {
          main: {
            containers: {
              main: {
                image: {
                  image:: image.immich.valkey,

                  repository: self.image.repo(),
                  tag: self.image.version,
                },
              },
            },
          },
        },
        persistence: {
          data: {
            enabled: true,
            type: 'persistentVolumeClaim',
            accessMode: 'ReadWriteOnce',
            size: '1Gi',
            storageClass: 'iscsi',
          },
        },
      },
    },
  },

  namespace: k.core.v1.namespace.new('immich'),

  db: {
    credentials:
      $._config.externalSecret.new('immich-db-user', $.namespace.metadata.name) +
      es.spec.withData([
        es.spec.data.withSecretKey('data') +
        es.spec.data.remoteRef.withKey('2e7b9c48-8efb-4999-ad1b-b4c60139e6da'),
      ]) +
      es.spec.target.template.metadata.withLabels({
        'cnpg.io/reload': 'true',
      }) +
      es.spec.target.template.withType('kubernetes.io/basic-auth') +
      es.spec.target.template.withEngineVersion('v2') +
      es.spec.target.template.withData({
        username: 'immich',
        password: '{{ .data }}',
      }),

    local cluster = cnpg.cluster,
    cluster:
      cluster.new('immich-db') +
      cluster.metadata.withNamespace($.namespace.metadata.name) +
      cluster.spec.withInstances(1) +
      cluster.spec.withImageName(image['pg-vectorchord'].ref()) +
      cluster.spec.storage.withSize('10Gi') +
      cluster.spec.storage.pvcTemplate.withAccessModes('ReadWriteOnce') +
      cluster.spec.storage.pvcTemplate.withStorageClassName('iscsi') +
      cluster.spec.postgresql.withShared_preload_libraries(['vchord']),

    // TODO: Use jsonnet-libs when it gets updated to use this resource
    role: {
      apiVersion: 'postgresql.cnpg.io/v1',
      kind: 'DatabaseRole',
      metadata: {
        name: 'immich',
        namespace: $.namespace.metadata.name,
      },
      spec: {
        cluster: {
          name: $.db.cluster.metadata.name,
        },

        name: 'immich',
        comment: 'immich Database Account',
        login: true,

        passwordSecret: {
          name: $.db.credentials.metadata.name,
        },
      },
    },

    local db = cnpg.database,
    local extension = db.spec.extensions,
    db:
      db.new('immich-db') +
      db.metadata.withNamespace($.namespace.metadata.name) +
      db.spec.withName('immich') +
      db.spec.withOwner($.db.role.spec.name) +
      db.spec.cluster.withName($.db.cluster.metadata.name) +
      db.spec.withExtensions([
        extension.withName('vector') +
        extension.withEnsure('present'),

        extension.withName('vchord') +
        extension.withEnsure('present'),

        extension.withName('earthdistance') +
        extension.withEnsure('present'),

        extension.withName('cube') +
        extension.withEnsure('present'),
      ]),
  },

  library: {
    labels:: { app: 'immich', kind: 'library' },
    resources:: { storage: '1Ti' },

    local pv = k.core.v1.persistentVolume,
    pv:
      pv.new('immich-library') +
      pv.metadata.withNamespace($.namespace.metadata.name) +
      pv.metadata.withLabels($.library.labels) +
      pv.spec.withCapacity($.library.resources) +
      pv.spec.withAccessModes(['ReadWriteMany']) +
      pv.spec.withPersistentVolumeReclaimPolicy('Retain') +
      pv.spec.withMountOptions($._config.media.mount.options) +
      pv.spec.nfs.withServer($._config.media.server) +
      pv.spec.nfs.withPath($._config.media.mount.photos),

    local pvc = k.core.v1.persistentVolumeClaim,
    pvc:
      pvc.new('immich-library') +
      pvc.metadata.withNamespace($.namespace.metadata.name) +
      pvc.metadata.withLabels($.library.labels) +
      pvc.spec.withStorageClassName('') +
      pvc.spec.withAccessModes(['ReadWriteMany']) +
      pvc.spec.resources.withRequests($.library.resources) +
      pvc.spec.selector.withMatchLabels($.library.labels),
  },

  immich: helm.template('immich', '../../charts/immich', {
    namespace: $.namespace.metadata.name,
    values: $._config.helm_values,
  }) {
    service_monitor_immich_server:: null,
  },

  local route = g.v1.httpRoute,
  local rule = route.spec.rules,
  route:
    route.new('immich') +
    route.metadata.withNamespace($.namespace.metadata.name) +
    $._config.cilium.gateway.route() +
    route.spec.withHostnames(['immich.home.nlowe.dev']) +
    route.spec.withRules([
      rule.withBackendRefs([
        rule.backendRefs.withName($.immich.service_immich_server.metadata.name) +
        rule.backendRefs.withNamespace($.immich.service_immich_server.metadata.namespace) +
        rule.backendRefs.withPort(2283),
      ]),
    ]),
}
