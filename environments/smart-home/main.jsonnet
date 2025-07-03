local k = import 'k.libsonnet';

(import 'homelab.libsonnet') +
(import 'esphome.libsonnet') +
(import 'home-assistant.libsonnet') +
(import 'vernemq.libsonnet') +
(import 'zwave-js-ui.libsonnet') +
{
  namespace: k.core.v1.namespace.new('smart-home'),
}
