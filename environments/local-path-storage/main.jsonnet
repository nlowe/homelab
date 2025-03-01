local k = import 'k.libsonnet';

{
  _config+:: {
    storageClassConfigs: {
      [$.storageClasses.localSSD.metadata.name]: {
        nodePathMap: [
          {
            node: 'DEFAULT_PATH_FOR_NON_LISTED_NODES',
            paths: ['/mnt/k8s'],
          },
        ],
      },
    },
  },
} +
{
  [
  '%s_%s' % [
    std.asciiLower(obj.kind),
    std.asciiLower(std.strReplace(obj.metadata.name, '-', '_')),
  ]
  ]: obj
  for obj in std.parseYaml((importstr 'github.com/rancher/local-path-provisioner/deploy/local-path-storage.yaml'))
} +
{
  provisionerName:: 'rancher.io/local-path',

  configmap_local_path_config+: k.core.v1.configMap.withDataMixin({
    'config.json': std.manifestJson($._config),
  }),

  local sc = k.storage.v1.storageClass,
  storageClasses+: {
    localSSD:
      sc.new('local-ssd') +
      sc.withProvisioner($.provisionerName) +
      sc.withParameters({
        nodePath: '/mnt/k8s',
        pathPattern: '{{ .PVC.Namespace }}/{{ .PVC.Name }}',
      }) +
      sc.withVolumeBindingMode('WaitForFirstConsumer') +
      sc.withReclaimPolicy('Delete'),
  },
}
