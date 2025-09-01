local k = import 'k.libsonnet';

local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local helm = tk.helm.new(std.thisFile);

local image = import 'images.libsonnet';

{
  bitwardenSDKServer: {
    local this = self,

    labels:: { app: 'bitwarden-sdk-server' },

    helm_values:: {
      image: {
        repository: image['bitwarden-sdk-server'].repo(),
        tag: image['bitwarden-sdk-server'].version,

        tls: {
          local volume = k.core.v1.volume,
          volumes: [
            volume.fromCsi('bitwarden-tls-certs', 'csi.cert-manager.io', {
              'csi.cert-manager.io/fs-group': std.toString(this.helm_values.podSecurityContext.fsGroup),
              'csi.cert-manager.io/issuer-kind': $.certs.issuer.kind,
              'csi.cert-manager.io/issuer-name': $.certs.issuer.metadata.name,
              // bitwarden-sdk-server doesn't support certificate re-loading: https://github.com/external-secrets/bitwarden-sdk-server/issues/38
              // Make it valid for a super long time, we'll get a fresh cert any time the container restarts. 30 years
              // of uptime is super optimistic, but one can dream.
              'csi.cert-manager.io/duration': '%dh' % (24 * 365 * 30),
              'csi.cert-manager.io/renew-before': '%dh' % (24 * 30),
              'csi.cert-manager.io/certificate-file': 'cert.pem',
              'csi.cert-manager.io/privatekey-file': 'key.pem',
              'csi.cert-manager.io/ca-file': 'ca.pem',
              'csi.cert-manager.io/common-name': '${POD_NAME}',
              'csi.cert-manager.io/dns-names': std.join(',', [
                '${POD_NAME}',
                'bitwarden-sdk-server',
                'bitwarden-sdk-server.${POD_NAMESPACE}',
                'bitwarden-sdk-server.${POD_NAMESPACE}.svc',
                'bitwarden-sdk-server.${POD_NAMESPACE}.svc.cluster.local',
              ]),
              'csi.cert-manager.io/key-usages': 'server auth',
            }) +
            volume.csi.withReadOnly(true),
          ],
        },
      },

      podSecurityContext: {
        fsGroup: 2000,
      },
    },

    manifests: helm.template('bitwarden-sdk-server', '../../charts/bitwarden-sdk-server', {
      namespace: $.namespace.metadata.name,
      values: this.helm_values,
    }),
  },
}
