local k = import 'k.libsonnet';

(import 'home-assistant.libsonnet') +
{
  smartHome+: {
    namespace: k.core.v1.namespace.new('smart-home'),
  },
}
