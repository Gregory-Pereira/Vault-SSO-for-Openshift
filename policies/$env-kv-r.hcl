# sa_policy.hcl
path "k8s_secrets/data/$env/*" {
  capabilities = ["read", "list"]
}
