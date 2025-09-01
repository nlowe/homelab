local k = import 'k.libsonnet';

local matchLabel = k.meta.v1.labelSelectorRequirement;
local excludeKubeSystemSelector =
  matchLabel.withKey('kubernetes.io/metadata.name') +
  matchLabel.withOperator('NotIn') +
  matchLabel.withValues(['kube-system']);

{
  local map = k.admissionregistration.v1alpha1.mutatingAdmissionPolicy,
  local constraint = k.admissionregistration.v1alpha1.namedRuleWithOperations,
  local condition = k.admissionregistration.v1.matchCondition,
  local mu = k.admissionregistration.v1alpha1.mutation,

  // By default, k8s sets ndots to 5 which means most external host names aren't treated as fully-qualified. Some pods
  // do not accept fully qualified hostnames (names with a trailing '.') and thus require ndots to be set for the pod.
  //
  // Do this using a MutatingAdmissionPolicy which configures ndots to 1 for every pod unless the pod already specified
  // its own value for ndots, which causes lookups to treat hosts with at least one dot as fully-qualified.
  //
  // Note that because DNS Options are marked as an atomic list we cannot use an ApplyPatch, and JSONPatch does not
  // allow for creating options if they don't already exist easily so this overwrites all options unconditionally. To
  // set other options, pods must specify their own ndots so they are excluded from this MutatingAdmissionPolicy.
  //
  // MutatingAdmissionPolicy is alpha in 1.33 and requires the following flags be set on the apiserver:
  //     --feature-gates=...,MutatingAdmissionPolicy=true,...
  //     --runtime-config=...,admissionregistration.k8s.io/v1alpha1=true,...
  //
  // See https://v1-33.docs.kubernetes.io/docs/reference/access-authn-authz/mutating-admission-policy/#patch-type-apply-configuration
  // See https://github.com/kubernetes/kubernetes/issues/127137#issuecomment-2603247342
  ndots:
    map.new('pod-dns-default-ndots') +
    map.spec.matchConstraints.namespaceSelector.withMatchExpressions([
      excludeKubeSystemSelector,
    ]) +
    map.spec.matchConstraints.withResourceRules([
      constraint.withApiGroups('') +
      constraint.withApiVersions('v1') +
      constraint.withOperations('CREATE') +
      constraint.withResources('pods'),
    ]) +
    map.spec.withMatchConditions([
      condition.withName('does-not-already-specify-ndots') +
      condition.withExpression(|||
        !has(object.spec.dnsConfig) ||
        !has(object.spec.dnsConfig.options) ||
        !object.spec.dnsConfig.options.exists(opt, opt.name == "ndots")
      |||),
    ]) +
    map.spec.withReinvocationPolicy('IfNeeded') +
    map.spec.withMutations([
      mu.withPatchType('JSONPatch') +
      mu.jsonPatch.withExpression(|||
        [
          JSONPatch{
            op: "add", path: "/spec/dnsConfig",
            value: Object.spec.dnsConfig{
              options: [
                Object.spec.dnsConfig.options{
                  name: "ndots",
                  value: "1",  
                }
              ]
            }
          }
        ]
      |||),
    ]),

  local binding = k.admissionregistration.v1alpha1.mutatingAdmissionPolicyBinding,
  ndotsBinding:
    binding.new('pod-dns-default-ndots') +
    binding.spec.withPolicyName($.ndots.metadata.name) +
    binding.spec.matchResources.namespaceSelector.withMatchExpressions([
      excludeKubeSystemSelector,
    ]),
}
