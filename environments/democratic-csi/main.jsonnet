local k = import 'k.libsonnet';

local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local helm = tk.helm.new(std.thisFile);

local image = (import 'images.libsonnet').democratic_csi;

{
  _config+:: {
    iscsi: {
      controller: {
        externalAttacher: {
          image: image.externalAttacher.ref(),
        },
        externalProvisioner: {
          image: image.externalProvisioner.ref(),
        },
        externalResizer: {
          image: image.externalResizer.ref(),
        },
        externalSnapshotter: {
          image: image.externalSnapshotter.ref(),
        },
        externalHealthMonitorController: {
          image: image.externalHealthMonitorController.ref(),
        },
        driver: {
          image: image.driver.ref(),
        },
      },

      node: {
        cleanup: {
          image: image.busybox.ref(),
        },
        driver: {
          image: image.driver.ref(),
        },
        driverRegistrar: {
          image: image.driverRegistrar.ref(),
        },
      },

      csiProxy: {
        image: image.csiProxy.ref(),
      },

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
        // TODO: NFS?
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
            // TODO: Secret?
            apiKey: 'TODO: Get this from vault',
            apiVersion: '2',
          },

          zfs: {
            datasetParentName: 'data/k8s/iscsi/v',
            detachedSnapshotsDatasetParentName: 'data/k8s/iscsi/s',
            zvolEnableReservation: false,
          },

          iscsi: {
            targetPortal: 'iscsi-1.storage.home.nlowe.dev',
            // for multipath
            targetPortals: ['iscsi-1.storage.home.nlowe.dev', 'iscsi-2.storage.home.nlowe.dev'],

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
  },

  namespace: k.core.v1.namespace.new('democratic-csi'),

  iscsi: helm.template('truenas-iscsi', '../../charts/democratic-csi', {
    namespace: $.namespace.metadata.name,
    values: $._config.iscsi,
  }) + {
    // TODO: Re-enable this when we can fetch the API Token from vault
    secret_truenas_iscsi_democratic_csi_driver_config:: null,
    daemon_set_truenas_iscsi_democratic_csi_node+: {
      spec+: { template+: { metadata+: { annotations+: { 'checksum/secret':: null } } } },
    },
    deployment_truenas_iscsi_democratic_csi_controller+: {
      spec+: { template+: { metadata+: { annotations+: { 'checksum/secret':: null } } } },
    },
  },
}
