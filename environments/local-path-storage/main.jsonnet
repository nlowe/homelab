local k = import 'k.libsonnet';

local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local helm = tk.helm.new(std.thisFile);

local image = import 'images.libsonnet';

{
  _config+:: {
    image: {
      repository: image['local-path-provisioner'].repo(),
      tag: image['local-path-provisioner'].version,
    },

    helperImage: {
      repository: image.busybox.repo(),
      tag: image.busybox.version,
    },

    storageClass: {
      provisionerName: 'rancher.io/local-path',
      name: 'local-ssd',
      pathPattern: '{{ .PVC.Namespace }}/{{ .PVC.Name }}/',
    },

    nodePathMap: [
      {
        node: 'DEFAULT_PATH_FOR_NON_LISTED_NODES',
        paths: ['/mnt/k8s'],
      },
    ],
  },

  namespace: k.core.v1.namespace.new('local-path-storage'),

  provisioner: helm.template('local-path-provisioner', '../../charts/local-path-provisioner', {
    namespace: $.namespace.metadata.name,
    values: $._config,
  }),
}
