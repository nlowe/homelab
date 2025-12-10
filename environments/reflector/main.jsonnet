local k = import 'k.libsonnet';

local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local helm = tk.helm.new(std.thisFile);

local image = import 'images.libsonnet';

(import 'homelab.libsonnet') +
{
  local this = self,

  labels:: { app: 'reflector' },

  helm_values:: {
    image: {
      repository: image.reflector.repo(),
      tag: image.reflector.version,
    },
  },

  namespace: k.core.v1.namespace.new('reflector-system'),

  manifests: helm.template('reflector', '../../charts/reflector', {
    namespace: $.namespace.metadata.name,
    values: this.helm_values,
  }),
}
