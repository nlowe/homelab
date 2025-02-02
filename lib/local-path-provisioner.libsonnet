local k = import 'k.libsonnet';
local manifests = {
  [
  '%s_%s' % [
    std.asciiLower(obj.kind),
    std.asciiLower(std.strReplace(obj.metadata.name, '-', '_')),
  ]
  ]: obj
  for obj in std.parseYaml((importstr 'github.com/rancher/local-path-provisioner/deploy/local-path-storage.yaml'))
};

{
  _config+:: {
    localPathProvisioner: {
      storageClassConfigs: {
        [$.localPathProvisioner.storageClasses.mimir.metadata.name]: {
          nodePathMap: [
            {
              node: 'DEFAULT_PATH_FOR_NON_LISTED_NODES',
              paths: ['/mnt/mimir'],
            },
          ],
        },
        [$.localPathProvisioner.storageClasses.loki.metadata.name]: {
          nodePathMap: [
            {
              node: 'DEFAULT_PATH_FOR_NON_LISTED_NODES',
              paths: ['/mnt/loki'],
            },
          ],
        },
      },
    },
  },

  localPathProvisioner: manifests {
    provisionerName:: 'rancher.io/local-path',

    configmap_local_path_config+: k.core.v1.configMap.withDataMixin({
      'config.json': std.manifestJson($._config.localPathProvisioner),
    }),

    local sc = k.storage.v1.storageClass,
    storageClasses+: {
      mimir:
        sc.new('mimir-local') +
        sc.withProvisioner($.localPathProvisioner.provisionerName) +
        sc.withParameters({
          nodePath: '/mnt/mimir',
          pathPattern: '{{ .PVC.Namespace }}/{{ .PVC.Name }}',
        }) +
        sc.withVolumeBindingMode('WaitForFirstConsumer') +
        sc.withReclaimPolicy('Delete'),

      loki:
        sc.new('loki-local') +
        sc.withProvisioner($.localPathProvisioner.provisionerName) +
        sc.withParameters({
          nodePath: '/mnt/loki',
          pathPattern: '{{ .PVC.Namespace }}/{{ .PVC.Name }}',
        }) +
        sc.withVolumeBindingMode('WaitForFirstConsumer') +
        sc.withReclaimPolicy('Delete'),
    },
  },
}
