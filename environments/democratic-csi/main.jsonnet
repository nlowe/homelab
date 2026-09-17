local k = import 'k.libsonnet';

local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local helm = tk.helm.new(std.thisFile);

local es = (import 'github.com/jsonnet-libs/external-secrets-libsonnet/1.1/main.libsonnet').nogroup.v1.externalSecret;

local image = (import 'images.libsonnet').democratic_csi;

(import 'homelab.libsonnet') +
{
  _config+:: {
    common:: {
      controller: {
        externalAttacher: {
          image: {
            image:: image.externalAttacher,
            registry: self.image.repo(),
            tag: self.image.version,
          },
        },
        externalProvisioner: {
          image: {
            image:: image.externalProvisioner,
            registry: self.image.repo(),
            tag: self.image.version,
          },
        },
        externalResizer: {
          image: {
            image:: image.externalResizer,
            registry: self.image.repo(),
            tag: self.image.version,
          },
        },
        externalSnapshotter: {
          image: {
            image:: image.externalSnapshotter,
            registry: self.image.repo(),
            tag: self.image.version,
          },
        },
        externalHealthMonitorController: {
          image: {
            image:: image.externalHealthMonitorController,
            registry: self.image.repo(),
            tag: self.image.version,
          },
        },
        driver: {
          image: {
            image:: image.driver,
            registry: self.image.repo(),
            tag: self.image.version,
          },
        },
      },

      node: {
        cleanup: {
          image: {
            image:: image.busybox,
            registry: self.image.repo(),
            tag: self.image.version,
          },
        },
        driver: {
          image: {
            image:: image.driver,
            registry: self.image.repo(),
            tag: self.image.version,
          },
        },
        driverRegistrar: {
          image: {
            image:: image.driverRegistrar,
            registry: self.image.repo(),
            tag: self.image.version,
          },
        },
      },

      csiProxy: {
        image: {
          image:: image.csiProxy,
          registry: self.image.repo(),
          tag: self.image.version,
        },
      },
    },

    iscsi: self.common {
      csiDriver: {
        name: 'org.democratic-csi.iscsi',
        fsGroupPolicy: 'File',
      },

      storageClasses: [
        {
          name: 'iscsi',
          defaultClass: true,
          reclaimPolicy: 'Delete',
          volumeBindingMode: 'Immediate',
          allowVolumeExpansion: true,

          parameters: {
            fsType: 'xfs',
          },

          mountOptions: ['noatime'],

          secrets: {
            'provisioner-secret': {},
            'controller-publish-secret': {},
            'node-stage-secret': {},
            'node-publish-secret': {},
            'controller-expand-secret': {},
          },
        },
      ],

      // TODO: Figure out snapshots
      volumeSnapshotClasses: [],

      driver: {
        config: {
          driver: 'freenas-api-iscsi',

          httpConnection: {
            protocol: 'https',
            host: 'storage.home.nlowe.dev',
            port: 443,
            apiKey: '{{ .truenasAPIKey }}',
            apiVersion: '2',
          },

          zfs: {
            datasetParentName: 'data/k8s/iscsi/v',
            detachedSnapshotsDatasetParentName: 'data/k8s/iscsi/s',
            zvolEnableReservation: false,
          },

          iscsi: {
            targetPortal: 'iscsi.storage.home.nlowe.dev',
            // for multipath
            targetPortals: ['iscsi.storage.home.nlowe.dev' /*, 'iscsi-2.storage.home.nlowe.dev'*/],

            namePrefix: 'csi-',
            nameSuffix: '-k8s',

            targetGroups: [
              {
                targetGroupPortalGroup: 1,
                targetGroupInitiatorGroup: 3,
                // None, CHAP, or CHAP Mutual
                targetGroupAuthType: 'None',
              },
            ],

            extentInsecureTpc: true,
            extentXenCompat: false,
            extentDisablePhysicalBlocksize: true,
            // 512, 1024, 2048, or 4096,
            extentBlocksize: 512,
            // "" (let FreeNAS decide, currently defaults to SSD), Unknown, SSD, 5400, 7200, 10000, 15000
            // TODO: Should this match the physical drives we have?
            extentRpm: 'SSD',
            // 0-100 (0 == ignore)
            extentAvailThreshold: 0,
          },
        },
      },
    },

    nfs: self.common {
      controller+: {
        enabled: true,
        externalResizer: {
          enabled: false,
        },

        strategy: 'deployment',
        hostNetwork: true,
        hostIPC: true,

        driver+: {
          securityContext+: {
            runAsNonRoot: true,
            runAsUser: $._config.media.uid,
            runAsGroup: $._config.media.gid,
            // TODO: fsGroup?
          },

          extraVolumeMounts: [
            {
              name: 'storage',
              mountPath: '/storage',
            },
          ],
        },

        extraVolumes: [
          {
            name: 'storage',
            nfs: {
              server: $._config.nfs.driver.config.nfs.shareHost,
              path: $._config.nfs.driver.config.nfs.shareBasePath,
            },
          },
        ],
      },

      csiDriver: {
        name: 'org.democratic-csi.nfs-client',
        fsGroupPolicy: 'File',
      },

      storageClasses: [
        {
          name: 'nfs',
          defaultClass: false,
          reclaimPolicy: 'Delete',
          volumeBindingMode: 'Immediate',
          allowVolumeExpansion: true,

          parameters: {
            fsType: 'nfs',
          },

          mountOptions: $._config.media.mount.options,

          secrets: {
            'provisioner-secret': {},
            'controller-publish-secret': {},
            'node-stage-secret': {},
            'node-publish-secret': {},
            'controller-expand-secret': {},
          },
        },
      ],

      // TODO: Figure out snapshots
      volumeSnapshotClasses: [],

      driver: {
        config: {
          driver: 'nfs-client',

          nfs: {
            shareHost: 'storage.home.nlowe.dev',
            shareBasePath: '/mnt/data/k8s/nfs/pv',
            controllerBasePath: '/storage',

            dirPermissionsMode: '0755',
            // TODO: Do we need names for these?
            dirPermissionsUser: $._config.media.uid,
            dirPermissionsGroup: $._config.media.gid,

            // TODO: snapshots?
          },
        },
      },
    },
  },

  namespace: k.core.v1.namespace.new('democratic-csi'),

  iscsi: helm.template('truenas-iscsi', '../../charts/democratic-csi', {
    namespace: $.namespace.metadata.name,
    values: $._config.iscsi,
  }) + {
    // We need to run this through external-secrets to pull in the apiKey, so force this version to be private
    secret_truenas_iscsi_democratic_csi_driver_config+:: {},
  },

  iscsiConfigSecret:
    $._config.externalSecret.new(
      name=$.iscsi.secret_truenas_iscsi_democratic_csi_driver_config.metadata.name,
      namespace=$.iscsi.secret_truenas_iscsi_democratic_csi_driver_config.metadata.namespace,
    ) +
    es.spec.withData([
      es.spec.data.withSecretKey('truenasAPIKey') +
      es.spec.data.remoteRef.withKey('7c436c12-f3f2-442d-b13a-b318015438e0'),
    ]) +
    es.spec.target.template.withEngineVersion('v2') +
    es.spec.target.template.withData($.iscsi.secret_truenas_iscsi_democratic_csi_driver_config.stringData),

  nfs: helm.template('nfs', '../../charts/democratic-csi', {
    namespace: $.namespace.metadata.name,
    values: $._config.nfs,
  }),
}
