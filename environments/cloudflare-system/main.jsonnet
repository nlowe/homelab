local k = import 'k.libsonnet';

(import 'tunnel.libsonnet') +
{
  namespace: k.core.v1.namespace.new('cloudflare-system'),
}
