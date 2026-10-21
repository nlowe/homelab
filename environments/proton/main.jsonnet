local k = import 'k.libsonnet';

local es = (import 'github.com/jsonnet-libs/external-secrets-libsonnet/1.1/main.libsonnet').nogroup.v1.externalSecret;

local image = import 'images.libsonnet';

(import 'homelab.libsonnet') +
{
  namespace: k.core.v1.namespace.new('proton'),

  labels:: { app: 'email-bridge' },

  local svc = k.core.v1.service,
  local port = k.core.v1.servicePort,
  service: {
    app:
      svc.new('email-bridge', $.labels, [
        // This is technically SMTPS, but the bridge only exposes 25
        port.withName('smtp') +
        port.withPort(25) +
        port.withTargetPort('smtp'),

        port.withName('smtps') +
        port.withPort(456) +
        port.withTargetPort('smtp'),

        // This is technically IMAPS, but the bridge only exposes 143
        port.withName('imap') +
        port.withPort(143) +
        port.withTargetPort('imap'),

        port.withName('imaps') +
        port.withPort(993) +
        port.withTargetPort('imap'),
      ]) +
      svc.metadata.withNamespace($.namespace.metadata.name) +
      svc.metadata.withLabels($.labels),

    headless:
      $.service.app +
      svc.metadata.withName('email-bridge-headless') +
      svc.spec.withClusterIP('None'),
  },

  keyringPassphrase:
    $._config.externalSecret.new('email-bridge-keyring-passphrase', $.namespace.metadata.name) +
    es.spec.withData([
      es.spec.data.withSecretKey('KEYRING_PASSPHRASE') +
      es.spec.data.remoteRef.withKey('b507fe27-9ada-4f9e-b18f-b4ea0140dba1'),
    ]),

  // TODO: Use cert-manager to issue a server cert if/when proton-bridge remembers cert paths between starts

  local container = k.core.v1.container,
  local envFrom = k.core.v1.envFromSource,
  local mount = k.core.v1.volumeMount,
  container::
    image.forContainer('protonmail-bridge', container_name='bridge') +
    // There's no easy way to log in to accounts with a two factor code in an init container, and the brdige enforces
    // a single process. Un-comment this command to exec into the container to run "bash /protonmail/entrypoint.sh init"
    // then "login" to setup an account. The initial sync will take a while (30-60 minutes). You will also want to run
    //
    // updates autoupdates disable
    // yes
    //
    // telemetry disable
    // yes
    //
    // change imap-security
    // yes
    //
    // change smtp-security
    // yes
    //
    // Be sure to run "info" to get SMTP/IMAP credentials.
    //
    // container.withCommand(['/bin/bash', '-c', 'sleep infinity']) +
    container.withPorts([
      { containerPort: 25, name: 'smtp', protocol: 'TCP' },
      { containerPort: 143, name: 'imap', protocol: 'TCP' },
    ]) +
    container.withEnvFrom([
      envFrom.secretRef.withName($.keyringPassphrase.metadata.name),
    ]) +
    // TODO: Tune resources: https://github.com/sdwilsh/ansible-playbooks/blob/abdd468387c9370b0ffc050c12d887a0e97e7efe/kustomization/components/proton-bridge/statefulset.yml#L35-L37
    // TODO: Probes: https://github.com/sdwilsh/ansible-playbooks/blob/abdd468387c9370b0ffc050c12d887a0e97e7efe/kustomization/components/proton-bridge/statefulset.yml#L20-L29
    container.withVolumeMounts([
      mount.withMountPath('/root') +
      mount.withName('data'),
    ]),


  local pvc = k.core.v1.persistentVolumeClaim,
  pvcTemplate::
    pvc.new('data') +
    pvc.spec.withAccessModes(['ReadWriteOnce']) +
    // TODO: how much data does this need?
    pvc.spec.resources.withRequests({ storage: '10Gi' }),

  local sts = k.apps.v1.statefulSet,
  local volume = k.core.v1.volume,
  statefulSet:
    sts.new('email-bridge', 1, [$.container], [$.pvcTemplate], null) +
    sts.metadata.withNamespace($.namespace.metadata.name) +
    sts.metadata.withLabels($.labels) +
    sts.spec.withServiceName($.service.headless.metadata.name) +
    sts.spec.selector.withMatchLabels($.labels) +
    sts.spec.template.metadata.withLabels($.labels),
}
