path "k8s_secrets/data/$env/*" {
    capabilities = ["create", "read", "update", "patch", "delete", "list", "sudo"]
}

path "k8s_secrets/*" {
    capabilities = ["list"]
}

path "k8s_secrets/metadata/$env/*" {
    capabilities = ["create", "read", "update", "patch", "delete", "list", "sudo"]
}
