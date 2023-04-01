# Vault OIDC for Openshift
This repository documents how Op1st and Rosa setup SSO for Vault via Authenticating against the Openshift Cluster. The goal of this documentation is for other teams to see how we set it up, and can use it as a guide on setting it up for their own deployments.

## Don't Have Vault Setup Yet?
If you do not already have Vault setup on Openshift and wish to, see our documentation for this: [`Setting-Up-Vault.md`](./Setting-Up-Vault.md).

## OIDC Provider
Single sign on requires some framework for authorization, in this case we will showcase how to make it work on the Open ID Connect framework (OIDC), with Dex as our provider. We chose this because Rosa already uses a deployment of Dex. This is setup in our [gitops-repo](https://github.com/redhat-et/rosa-apps.git) and you can structure your deployment of Dex based off this. Some key files/file-types to note about the dex deployment:
  1. `rosa-apps/argocd` related files -- since this is a gitops repo, we use argocd coupled with kustomize to bundle and deploy what we have in Git. In our deployment, the argocd [app-of-apps](https://github.com/redhat-et/rosa-apps/blob/main/argocd/overlays/rosa/applications/app-of-apps/rosa-app-of-apps.yaml) application automatically picks up and syncs the [Dex application](https://github.com/redhat-et/rosa-apps/blob/main/argocd/overlays/rosa/applications/envs/rosa/cluster-management/dex.yaml).
  2. `rosa-apps/cluster-scope` -- these are files that are not deployment or instance specific, rather are cluster level resources that would be required for any deployment of Dex. In this case, this is only the [dex namespace](https://github.com/redhat-et/rosa-apps/tree/main/cluster-scope/base/core/namespaces/dex).
  3. `rosa-apps/dex` -- in this path we store all the application specific content. There are two seperate directories in this path:
    - `base` -- Base refers to all the base kubernetes and openshift manifests (routes, services, etc.). No changes are required to base you can migrate it as is.
    - `overlays` -- dex deployment manifests specific to your environment. You will need this [`dex-clients` secret](https://github.com/redhat-et/rosa-apps/blob/main/dex/overlays/rosa/sealed-secrets/dex-clients-sealed.yaml) (we use sealed-screts for secret management) so Dex can keep track of all the OIDC clients and their corresponding secrets, however you can manage this secret any way you see fit (eso, sealed secrets, regular k8s secret, etc.). The other key file here is the [`config` file](https://github.com/redhat-et/rosa-apps/blob/main/dex/overlays/rosa/configmaps/files/config.yaml). This is important to setting up SSO for vault because you will need to add vault as a static OIDC client of Dex; this is done for us in that config file [on lines 19-24](https://github.com/redhat-et/rosa-apps/blob/main/dex/overlays/rosa/configmaps/files/config.yaml#L19-L24), where the base url is your vault route and the relative path is the default path for OIDC.

## Vault OIDC
If you have properly followed the steps in our [`Setting-Up-Vault.md`](./Setting-Up-Vault.md) documentation, and configured Dex as your OIDC provider, you should at this point have everything you need: 
  - a running deployment of dex
  - an unsealed instance of vault that you can authenticate to with the `initial-root-token`
  - a `kv` secrets engine created in vault
From here on out you will need to configure various vault speicifc role and manifests, examples for which will be stored in this repo. Authenitcate to the cluster and you can begin to complete these.

### Policies
Select the Policies tab in the top left. You will find examples of our vault `policies` in the [`policies` directory](./policies) in this repo. The [`admin`](./policies/admin.hcl) and [`default`](./policies/default.hcl) ones should have been created by vault and thus exist, however they have been supplied just in case they get deleted by accident. This repo provides 2 other examples of policies for your cluster, a [read policy](./policies/$env-kv-r.hcl) and [write policy](./policies/$env-kv-rw.hcl). Note that the file name and the contents of the file contain `$env`, which stub out your environment, and kv refers to key-value as the type of secret engine we used earlier. Make sure to replace the file names with your environment (example policy name: `rosa-kv-rw.hcl`), and the `$env` values with the `path`s of the [read policy](./policies/$env-kv-r.hcl) and [write policy](./policies/$env-kv-rw.hcl), which refers to the base path for a given secret engine to access the secrets that should be scoped to the policy we just created.

To create the policies, navigate to the `Policies` tab and select `Create ACL Policy`. Name each policy as discribed above, one read, one write, and stubbing out `$env`. Copy the contents of the corresponding `.hcl` policy file, found in the [policies directory](../policies) for each one, click `Create Policy`, and then repeat for the other policy.

### Auth methods
Click on `Access` in the top left and select the `Auth Methods` tab. There should already be a token auth method created for you by default, and if you followed our docs, you should also have username and password already setup. 

We will need to create 2 auth methods, one of type `oidc` and one of type `kubernetes`.

#### Kuberenetes Auth Method

Starting with the `kubernetes`, select `Enable a new auth method` and `kubernetes` from the `Infra` auth method type row. For your path, name it after the kubernetes cluster handling the authentication, for us we call it `rosa-k8s`. You do not need to change any options in the `Method Options` menu, leave it as is. Click `Enable` to continue and it will take you to the configure screen. Here enter your Openshift cluster's API route (this can be found in Openshift by going to the `Home` menu then `Overview` tab) in the `kubernetes host` box and click save. Repeat this, by creating an auth method for each cluster that you have. You can verify your `kuberenetes auth method` against the [Rosa `kuberenetes auth method` configuration](Kubernetes-cluster-auth-method.png).
 
#### OIDC Auth Method

Next we will setup the `oidc` `auth method`. Again, go to `Enable a new auth method` but select `oidc` as the type and continue. Leave the path as simply `oidc` and select `List method when unauthenticated` under `Method Options` . Click `Enable Method` and then continue to the configuration screen. For the `OIDC discovery URL` enter your Dex route (in the Rosa cluster this looks like: `https://dex-dex.apps.open-svc-sts.k1wl.p1.openshiftapps.com`). For `Default role` enter `ocp-user`. *NOTE: this role has not yet been configured, this is something we will do later*. Click the `OIDC Options` at the bottom. Enter `vault` for the `OIDC Client ID`, and enter or generate a password for the `OIDC Client Secret`. This `OIDC Client Secret` is not system generated so feel free to make it whatever, however it serves as A UUID for your OIDC provider, to keep track of the clients and thus must be unique. Make sure to back this key-value pairing into a kubernetes secret in the `Dex` namespace, or better yet a sealed or external secret to track this in git. You can verify your `oidc` vault setup against [the Rosa `oidc auth method` configuration](./assets/OIDC-auth-method.png).

### Roles
This section will cover creating the required roles, one per `auth method`. Both of these roles should be created from the Terminal within the Vault UI (click on terminal icon in the top right next to the profile icon). Theoretically they can be created from the vault binary on your local system by connecting to your Vault instance in your Openshift cluster, but this is not reliable. This is why these roles were provided as vault binary commands with key value pairings rather than `.hcl` policy files.

#### Kuberenetes Auth Method Role

Starting with the role for your kuberenetes auth method, we will use a script such as this from the terminal in the vault ui:

##### Stubbed command
```
vault write auth/rosa-k8s/role/$env-ops bound_service_account_names="vault-secret-fetcher" bound_service_account_namespaces="", token_policies="$env-kv-r"
```

As with every other resource we have added to vault so far, make sure to replace `$env` with your environment name in the role name and the role `token_policy` with the [read policy we created earlier](./README.md#Policies). Additionally in the command the `bound_service_account_namespaces` have been left empty, however you should enter a comma seperated list (as a string) of all namespace in which you wish to use external secrets. This command looked like this for the Rosa environment:

##### Rosa Command
```
vault write auth/rosa-k8s/role/rosa-ops bound_service_account_names="vault-secret-fetcher" bound_service_account_namespaces="dex,openshift-config,openshift-ingress,openshift-image-registry", token_policies="rosa-kv-r"
```

#### OIDC Auth Method Role

Remeber when setting up the `OIDC Auth Method`, we set the default role as `ocp-user`? Since there is only one value you will need to replace, we have simply provided the Rosa command as an example below, replace the `allowed_redirect_uris` with your vault redirect uri that you setup in the dex config ([see rosa example](https://github.com/redhat-et/rosa-apps/blob/main/dex/overlays/rosa/configmaps/files/config.yaml#L19-L24)).

##### Rosa Command
```
vault write auth/oidc/role/ocp-user allowed_redirect_uris="https://rosa-vault-ui-vault.apps.open-svc-sts.k1wl.p1.openshiftapps.com/ui/vault/auth/oidc/oidc/callback" groups_claim="groups" oidc_scopes="openid,email,groups,profile" policies="default" token_policies="default" token_ttl="3600" ttl="3600"
```

### Groups
We will simply be configuring one admin group, based off of our openshift `cluster-admins` group, if you wish to do more, you can do that at your own discression. Select `Groups` under the `Access` tab, and then select `Create group`.

For the `Name`, pass `vault-admins`, set the `Type` to `external`, and select the `$env-kv-rw` policy that we created earlier, and click `create`.

Select the `vault-admins` group you just created and navigate to the `Aliases` tab, and click `Add alias`. Set the `Name` to the name of your Openshift group, in our case, `cluster-admins` although this can be any openshift group. Set the `Auth Backend` to your Kubernetes Auth Method (if you have multiple, then the one that refers to cluster on which the group you want to use for authentication lives). Click `Create` to finish.

## Wrapping Up And Links To Further Documentation
Congratulations, if you have followed the all the steps up until now, you should have a properly setup vault instance with OIDC enabled. Topics that havent been covered yet are expanding which namespaces on a cluster can used external secrets, and adding new teams to vault, and how to create external secrets. Thankfully the wonderful [Operate-First](https://github.com/operate-first) community have written documentation on this, below will be linked only the most relevent pieces of documentation but you can purouse the enirety of their `Vault` and `ESO` docs [here](https://github.com/operate-first/apps/tree/master/docs/content/vault_eso). One thing that should be noted, however, is that some values will vary between the Rosa Vault instance and the Op1st one, and therefore some steps we would take will differ from their documentation, but it does a good job explaining what to do and how even if the values arent the same. Some examples of values that would differ: 
  - vault route
  - vault `SecretStore` names
  - Since the rosa deployment only contains 1 cluster, we dont use `$env` and `cluster`, simply `cluster` which is `rosa` for us.

### Ops1st related Docs
  - [How to enable external secrets in a namespace](https://github.com/operate-first/apps/blob/master/docs/content/vault_eso/docs/enable_es_in_namespace.md)
  - [How to add groups to vault](https://github.com/operate-first/apps/blob/master/docs/content/vault_eso/docs/onboard_team_to_vault.md)
  - [How to create an external secret](https://github.com/operate-first/apps/blob/master/docs/content/vault_eso/docs/create_external_secret.md)
  - [General Runbook for debugging issues](https://github.com/operate-first/apps/blob/master/docs/content/vault_eso/docs/runbook.md)
