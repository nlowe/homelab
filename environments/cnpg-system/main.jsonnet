local k = import 'k.libsonnet';

local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local helm = tk.helm.new(std.thisFile);

local image = import 'images.libsonnet';

(import 'homelab.libsonnet') +
{
  _config+:: {
    helm_values:: {
      image: {
        image:: image['cloudnative-pg'],

        repository: self.image.repo(),
        tag: self.image.version,
      },

      config: {
        data: {
          OPERATOR_IMAGE_NAME: image['cloudnative-pg'].ref(),
          PGBOUNCER_IMAGE_NAME: image.pgbouncer.ref(),
          POSTGRES_IMAGE_NAME: image.pg.ref(),
        },
      },

      // TODO: Resources

      monitoring: {
        podMonitorEnabled: true,
        grafanaDashboard: {
          create: false,
        },
      },
    },
  },

  namespace: k.core.v1.namespace.new('cnpg-system'),

  operator: helm.template('cnpg', '../../charts/cloudnative-pg', {
    namespace: $.namespace.metadata.name,
    values: $._config.helm_values,
  }),
}
