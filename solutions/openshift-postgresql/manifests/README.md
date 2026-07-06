# Managed PostgreSQL for OpenShift with Aiven

Running a database inside your OpenShift cluster means taking on operational responsibility: storage provisioning, backups, upgrades, failover. For many teams that overhead is not the point; the application is.

This example shows how to connect an application running on OpenShift to [Aiven for PostgreSQL](https://aiven.io/postgresql), a fully managed database that lives outside your cluster. You choose how to provision the database: through the Aiven console, or directly from OpenShift using the Aiven Operator.

Your workloads stay on OpenShift. The database operations (provisioning, backups, scaling, upgrades) are handled by Aiven.

> **Not what you're looking for?** This example is for OpenShift users who want a managed database for their cluster workloads. If you are looking to run application workloads on Aiven's infrastructure, see [Aiven Apps](https://aiven.io/apps).

## How it works

```
OpenShift cluster                         Aiven (external)
|                                         |
+-- Aiven Operator  ---- HTTPS API -----> |  Aiven for PostgreSQL
|   +-- watches PostgreSQL CRD            |  (managed outside the cluster)
|       +-- writes connection Secret <--- |
|                                         |
+-- demo-app Deployment                   |
    +-- reads DATABASE_URL from Secret    |
    +-- connects to PostgreSQL ---------->|
    +-- Route (TLS edge termination)
```

The connection Secret is the bridge between OpenShift and Aiven. Whether you create it manually (Option A) or let the Aiven Operator create it for you (Option B), the application deployment is identical.

## Prerequisites

- An OpenShift cluster (4.12 or later). [Developer Sandbox](https://developers.redhat.com/developer-sandbox) provides a free shared cluster and works for Option A. Option B requires cluster-admin access. If you do not have a suitable cluster, see [Running OpenShift locally with CRC](#running-openshift-locally-with-crc).
- An [Aiven account](https://console.aiven.io/signup). The free tier (`free` plan) is used throughout — no credit card required.
- `oc` CLI logged in to your cluster. Confirm with `oc whoami`.
- `helm` (v3 or later) for Option B.
- Docker if you want to build and push the application image yourself (see [Building the image](#building-the-image)).

---

## Option A: Create the database in the Aiven console

This option works on any OpenShift cluster including the Developer Sandbox. You provision the database through the Aiven console and paste the connection URI into a Kubernetes Secret. No cluster-admin access required.

### 1. Create the PostgreSQL service

In the [Aiven console](https://console.aiven.io):

1. Click **Create service** and select **PostgreSQL**
2. Choose any cloud provider and region
3. Select the **Free** plan
4. Give the service a name and click **Create service**

Wait for the state to show **Running** (roughly 2 to 3 minutes). Then open the service and copy the **Service URI** from the Overview tab. It looks like:

```
postgres://avnadmin:...@host:port/defaultdb?sslmode=require
```

### 2. Create the connection Secret

Use `read` to avoid the token appearing in your shell history:

```bash
read -s PG_URI
oc create secret generic demo-pg-connection \
  --from-literal=PG_DATABASE_URI="$PG_URI" \
  -n YOUR_NAMESPACE
unset PG_URI
```

Skip to [Deploy the application](#deploy-the-application).

---

## Option B: Create the database from OpenShift

This option uses the [Aiven Operator for Kubernetes](https://aiven.io/docs/tools/kubernetes). The operator watches Aiven-specific CRDs and calls the Aiven API on your behalf. You define the database you want as a Kubernetes manifest, and the operator provisions it and writes the connection Secret into your namespace automatically.

This requires cluster-admin access. If you already have an OpenShift cluster where you can install operators, use that. If not, see [Running OpenShift locally with CRC](#running-openshift-locally-with-crc).

### 1. Install the Aiven Operator

The Aiven Operator requires [cert-manager](https://cert-manager.io) and is installed via Helm. Add the Helm repositories:

```bash
helm repo add aiven https://aiven.github.io/aiven-charts
helm repo add jetstack https://charts.jetstack.io
helm repo update
```

Install cert-manager:

```bash
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true

oc rollout status deployment/cert-manager -n cert-manager
```

Install the Aiven Operator CRDs and operator:

```bash
helm install aiven-operator-crds aiven/aiven-operator-crds \
  --namespace operators \
  --create-namespace

helm install aiven-operator aiven/aiven-operator \
  --namespace operators
```

Verify the operator pod is running:

```bash
oc get pods -n operators
```

> **Note:** The Aiven Operator is listed on OperatorHub, but the version in CRC's community catalog is significantly outdated and does not install cleanly on current OpenShift versions. The Helm install above is the recommended approach for CRC and self-managed clusters.

> **Note:** The operator must start after the CRDs are registered. If you see an error like `controller SecretFinalizerGCController: unable to add index for secret ref fields` in the operator logs, the operator started before the CRDs were ready. Restart it with `oc rollout restart deployment/aiven-operator -n operators`.

### 2. Add your Aiven API token

Generate a token in the Aiven console under **User profile**, then **Authentication**, then **Generate token**. Set the expiry to the maximum available value or no expiry; short-lived tokens will cause the operator to fail mid-reconcile after provisioning the service.

Use `read` to avoid the token appearing in your shell history:

```bash
read -s AIVEN_TOKEN
oc create secret generic aiven-token \
  --from-literal=token="$AIVEN_TOKEN" \
  --dry-run=client -o yaml | oc apply -f - -n aiven-pg-demo
unset AIVEN_TOKEN
```

> The token is only used by the operator to call the Aiven API. It is never passed to the application.

### 3. Provision the PostgreSQL service

Apply the manifest, substituting your Aiven project name and preferred cloud region:

```bash
sed \
  -e 's/YOUR_AIVEN_PROJECT/your-project-name/' \
  -e 's/YOUR_CLOUD_AND_REGION/google-europe-west1/' \
  manifests/02-postgresql-service.yaml | oc apply -f - -n aiven-pg-demo
```

Common cloud and region values:

| Provider | Example value |
|---|---|
| Google Cloud | `google-europe-west1`, `google-us-east1` |
| AWS | `aws-eu-west-1`, `aws-us-east-1` |
| Azure | `azure-germanywestcentral`, `azure-eastus` |

The `free` plan is a single-node instance with 1GB storage and 1GB RAM, no backups, and no high availability. Services automatically power off during inactivity. It requires no credit card and is available on all three providers.

Watch the service come up (roughly 2 to 3 minutes on the free tier):

```bash
oc get postgresql demo-pg -n aiven-pg-demo --watch
```

When `STATE` shows `RUNNING`, the operator writes the connection details into a Secret named `demo-pg-connection`. Verify:

```bash
oc get secret demo-pg-connection -n aiven-pg-demo
```

You should see keys including `PG_DATABASE_URI`, `PG_HOST`, `PG_PORT`, `PG_USER`, and `PG_PASSWORD`.

If the operator logs show `[401 ServiceGet]: Expired db token`, the token expired mid-reconcile. Update the secret with a fresh token (see step 2) and the operator will retry automatically.

---

## Deploy the application

Once the `demo-pg-connection` Secret exists (created manually via Option A, or by the operator via Option B) the application deployment is the same.

```bash
oc apply -f manifests/03-app-deployment.yaml
oc rollout status deployment/demo-app
```

Retrieve the Route URL:

```bash
oc get route demo-app -o jsonpath='{.spec.host}'
```

## Try it

```bash
ROUTE=$(oc get route demo-app -o jsonpath='{.spec.host}')

# Health check
curl https://$ROUTE/healthz

# Create an item
curl -X POST https://$ROUTE/items \
  -H 'Content-Type: application/json' \
  -d '{"name": "hello from OpenShift"}'

# List items
curl https://$ROUTE/items
```

The FastAPI interactive docs are available at `https://$ROUTE/docs`.

---

## Replace this app with your own workload

The demo app in `app/main.py` is a starting point. To connect your own application to the same database, consume the `demo-pg-connection` Secret in your Deployment:

```yaml
env:
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: demo-pg-connection
        key: PG_DATABASE_URI
```

Individual connection parameters are also available as `PG_HOST`, `PG_PORT`, `PG_USER`, `PG_PASSWORD`, and `PG_DATABASE` if your application expects them separately.

To extend the demo app rather than replace it, edit `app/main.py`, build a new image, and update the `image:` field in `manifests/03-app-deployment.yaml`. See [Building the image](#building-the-image) for the correct build flags.

---

## OpenShift-specific notes

### Security Context Constraints

OpenShift's `restricted` SCC requires containers to run as a non-root user. Each namespace is assigned a UID range (visible in the `openshift.io/sa.scc.uid-range` annotation on the project), and OpenShift assigns a UID from that range at runtime, overriding any `USER` directive in the Dockerfile. For this reason the Deployment does not set `runAsUser`; hardcoding a UID outside the namespace's allowed range will cause the pod to be rejected.

The Dockerfile still sets `USER 1001` as a sensible non-root default for local development and non-OpenShift Kubernetes clusters.

### Routes vs Ingress

The manifests use an OpenShift `Route` resource for external access with TLS edge termination. If you are adapting this example to plain Kubernetes, replace the `Route` with a standard `Ingress` resource pointing to the `demo-app` Service on port 80.

### Namespace fields in manifests

The manifests in this repo do not include a `namespace:` field. Resources are created in whichever project is currently active (`oc project`). Pass `-n YOUR_NAMESPACE` explicitly to `oc apply` if you want to target a specific namespace.

## Building the image

The manifest references a pre-built image. To build and push your own:

```bash
docker build \
  --platform linux/amd64 \
  --provenance=false \
  -t your-registry/openshift-aiven-pg-demo:v1 \
  app/

docker push your-registry/openshift-aiven-pg-demo:v1
```

Then update the `image:` field in `manifests/03-app-deployment.yaml`.

> `--platform linux/amd64` is required when building on Apple Silicon. `--provenance=false` prevents Docker from pushing a multi-arch manifest list that includes an attestation entry with `architecture: unknown`, which causes image pull failures on OpenShift. Use a versioned tag (e.g. `v1`) rather than `latest` to avoid registry CDN caching issues.

## Cleaning up

```bash
# Option B only: delete the Aiven service (terminates the managed PostgreSQL instance)
oc delete postgresql demo-pg -n aiven-pg-demo

# All options: delete application resources and secrets
oc delete -f manifests/03-app-deployment.yaml
oc delete secret demo-pg-connection aiven-token -n aiven-pg-demo
```

## Running OpenShift locally with CRC

[OpenShift Local (CRC)](https://developers.redhat.com/products/openshift-local/overview) runs a single-node OpenShift cluster in a VM on your laptop, giving you full cluster-admin access and OperatorHub without needing a cloud account.

Follow the [official installation guide](https://docs.redhat.com/en/documentation/red_hat_openshift_local) to install and start CRC. Once running, configure `oc` and log in:

```bash
eval $(crc oc-env)
oc login -u kubeadmin -p $(crc console --credentials | grep kubeadmin | awk '{print $NF}')
```

CRC does not include an `operators` namespace by default. Create it before installing the operator:

```bash
oc new-project operators
```

Then continue from [Option B](#option-b-create-the-database-from-openshift).

## Useful links

- [Aiven Operator for Kubernetes documentation](https://aiven.io/docs/tools/kubernetes)
- [Aiven Operator Helm chart](https://github.com/aiven/aiven-charts)
- [Aiven for PostgreSQL documentation](https://aiven.io/docs/products/postgresql)
- [Red Hat Developer Sandbox](https://developers.redhat.com/developer-sandbox)
- [OpenShift Local (CRC) documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_local)
