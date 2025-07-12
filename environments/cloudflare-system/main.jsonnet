local k = import 'k.libsonnet';

(import 'homelab.libsonnet') +
(import 'tunnel.libsonnet') +
{
  namespace: k.core.v1.namespace.new('cloudflare-system'),
}
