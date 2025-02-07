local k = import 'k.libsonnet';

(import 'esphome.libsonnet') +
(import 'home-assistant.libsonnet') +
(import 'zwave-js-ui.libsonnet') +
{
  smartHome+: {
    namespace: k.core.v1.namespace.new('smart-home'),
  },
}
