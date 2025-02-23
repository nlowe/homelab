local k = import 'k.libsonnet';

{
  _config+:: {
    cilium+: {
      bgp+: {
        asn: 65020,
        peer: {
          addr: '10.200.0.1',
          asn: 65000,
        },
        serviceCIDR: '10.200.200.0/24',
      },
    },
  },

  cilium+: {
    bgp+: {
      labels:: { advertise: 'bgp' },

      local svc = k.core.v1.service,
      loadBalancerMixin(ips)::
        svc.metadata.withAnnotationsMixin({
          'lbipam.cilium.io/ips': std.join(',', if std.isArray(ips) then ips else [ips]),
        }) +
        svc.metadata.withLabelsMixin($.cilium.bgp.labels) +
        svc.spec.withType('LoadBalancer') +
        svc.spec.withLoadBalancerClass('io.cilium/bgp-control-plane') +
        svc.spec.withExternalTrafficPolicy('Local') +
        svc.spec.withInternalTrafficPolicy('Local'),

      serviceMixins:: {
        caddy: $.cilium.bgp.loadBalancerMixin('10.200.200.10'),
        alloy_syslog: $.cilium.bgp.loadBalancerMixin('10.200.200.11'),
      },

      pool: {
        apiVersion: 'cilium.io/v2alpha1',
        kind: 'CiliumLoadBalancerIPPool',
        metadata: {
          name: 'homelab',
        },
        spec: {
          blocks: [
            { cidr: $._config.cilium.bgp.serviceCIDR },
          ],
          serviceSelector: {
            matchLabels: $.cilium.bgp.labels,
          },
        },
      },

      peerConfig: {
        apiVersion: 'cilium.io/v2alpha1',
        kind: 'CiliumBGPPeerConfig',
        metadata: {
          name: 'udm-pro-max',
        },
        spec: {
          gracefulRestart: {
            enabled: true,
            restartTimeSeconds: 15,
          },
          families: [
            {
              afi: 'ipv4',
              safi: 'unicast',
              advertisements: {
                matchLabels: $.cilium.bgp.labels,
              },
            },
          ],
        },
      },

      clusterConfig: {
        apiVersion: 'cilium.io/v2alpha1',
        kind: 'CiliumBGPClusterConfig',
        metadata: {
          name: 'homelab',
        },
        spec: {
          bgpInstances: [{
            name: std.toString($._config.cilium.bgp.asn),
            localASN: $._config.cilium.bgp.asn,
            peers: [{
              name: 'udm-pro-max',
              peerASN: $._config.cilium.bgp.peer.asn,
              peerAddress: $._config.cilium.bgp.peer.addr,
              peerConfigRef: {
                name: $.cilium.bgp.peerConfig.metadata.name,
              },
            }],
          }],
        },
      },

      advertisement: {
        apiVersion: 'cilium.io/v2alpha1',
        kind: 'CiliumBGPAdvertisement',
        metadata: {
          name: 'homelab',
          labels: $.cilium.bgp.labels,
        },
        spec: {
          advertisements: [{
            advertisementType: 'Service',
            service: {
              addresses: ['LoadBalancerIP'],
            },
            selector: {
              matchLabels: $.cilium.bgp.labels,
            },
          }],
        },
      },
    },
  },
}
