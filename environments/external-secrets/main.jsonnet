local k = import 'k.libsonnet';

local cm = import 'github.com/jsonnet-libs/cert-manager-libsonnet/1.15/main.libsonnet';
local issuer = cm.nogroup.v1.clusterIssuer;

local es = import 'github.com/nlowe/external-secrets-libsonnet/0.18/main.libsonnet';
local clusterSecretStore = es.nogroup.v1.clusterSecretStore;
local bitwardenProvider = clusterSecretStore.spec.provider.bitwardensecretsmanager;

(import 'homelab.libsonnet') +
(import 'bitwarden-sdk-server.libsonnet') +
(import 'external-secrets.libsonnet') +
{
  namespace: k.core.v1.namespace.new('external-secrets'),

  certs: {
    local issuer = cm.nogroup.v1.issuer,
    local cert = cm.nogroup.v1.certificate,

    ca: {
      issuer:
        issuer.new('selfsigned') +
        issuer.metadata.withNamespace($.namespace.metadata.name) +
        issuer.metadata.withLabels($.externalSecrets.labels) +
        {
          spec: {
            selfSigned: {},
          },
        },

      cert:
        cert.new('external-secrets-selfsigned-ca') +
        cert.metadata.withNamespace($.namespace.metadata.name) +
        cert.metadata.withLabels($.externalSecrets.labels) +
        cert.spec.withIsCA(true) +
        cert.spec.withCommonName('external-secrets-selfsigned-ca') +
        cert.spec.withSecretName('external-secrets-selfsigned-ca') +
        cert.spec.subject.withOrganizations([$.namespace.metadata.name]) +
        cert.spec.withDuration('%dh' % (24 * 365 * 50)) +
        cert.spec.withRenewBefore('%dh' % (24 * 30)) +
        cert.spec.privateKey.withAlgorithm('ECDSA') +
        cert.spec.privateKey.withSize(256) +
        cert.spec.secretTemplate.withLabels($.externalSecrets.labels) +
        cert.spec.issuerRef.withGroup('cert-manager.io') +
        cert.spec.issuerRef.withKind($.certs.ca.issuer.kind) +
        cert.spec.issuerRef.withName($.certs.ca.issuer.metadata.name),
    },

    issuer:
      issuer.new('external-secrets') +
      issuer.metadata.withNamespace($.namespace.metadata.name) +
      issuer.metadata.withLabels($.externalSecrets.labels) +
      issuer.spec.ca.withSecretName($.certs.ca.cert.spec.secretName),
  },

  bitwardenSecretStore:
    clusterSecretStore.new($._config.externalSecret.storeName) +
    clusterSecretStore.metadata.withLabels($.externalSecrets.labels) +
    bitwardenProvider.withApiURL('https://api.bitwarden.com') +
    bitwardenProvider.withIdentityURL('https://identity.bitwarden.com') +
    bitwardenProvider.auth.secretRef.credentials.withNamespace($.namespace.metadata.name) +
    bitwardenProvider.auth.secretRef.credentials.withName('bitwarden-access-token') +
    bitwardenProvider.auth.secretRef.credentials.withKey('token') +
    bitwardenProvider.withBitwardenServerSDKURL('https://bitwarden-sdk-server.external-secrets.svc.cluster.local:9998') +
    bitwardenProvider.caProvider.withType('Secret') +
    bitwardenProvider.caProvider.withNamespace($.namespace.metadata.name) +
    bitwardenProvider.caProvider.withName('external-secrets-selfsigned-ca') +
    bitwardenProvider.caProvider.withKey('tls.crt') +
    bitwardenProvider.withOrganizationID('bfc81819-6571-4d4d-a3aa-b3180142ddcd') +
    bitwardenProvider.withProjectID('311f59ac-ec9a-4a32-acfb-b31801433559'),
}
