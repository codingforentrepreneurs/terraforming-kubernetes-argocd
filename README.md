# Terraforming Kubernetes: Leveraging ArgoCD to Manage and Deploy Applications
In this tutorial series, we'll show you how to implement ArgoCD to manage and deploy applications to your Terraformed Kubernetes cluster running on the Linode Kubernetes Engine (LKE).


## Requirements
- Watch [Terraforming Kubernetes on Linode](https://www.codingforentrepreneurs.com/courses/terraforming-kubernetes-on-linode/) or have some experience managing Kubernetes clusters
- [Git](https://git-scm.com/downloads) installed
- [Terraform](https://developer.hashicorp.com/terraform/downloads) installed
- [Kubectl](https://kubernetes.io/docs/tasks/tools/) installed

## 1. Fork and Clone this Repository

```bash
git clone https://github.com/codingforentrepreneurs/terraforming-kubernetes-argocd
cd terraforming-kubernetes-argocd
```

Create an account on [Linode](https://www.linode.com/cfe) and get an API Key in your linode account [here](https://cloud.linode.com/profile/tokens).

Once you have a key, do the following:

```bash
echo "linode_api_token=\"YOUR_API_KEY\"" >> infra/terraform.tfvars
```

## 2. Terraform Kubernetes

```bash
terraform -chdir=./infra init
terraform -chdir=./infra plan
```
If the plan looks good, run:

```bash
terraform -chdir=./infra apply
```


## 3. Install Ingress Nginx

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.7.0/deploy/static/provider/cloud/deploy.yaml
```

Or if you use _helm_:
```bash
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace
```


## 4. Install Cert Manager
Directly in the [cert-manager](https://cert-manager.io/docs/installation/) docs:
```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.11.0/cert-manager.yaml
```

## 5. Cluster Issuer for Certificates

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: youremail@email.com
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
    - http01:
        ingress:
          class: nginx
```
Change `youremail@email.com` to your email. The http01 solver is great for non-wildcard domains. If you need a wildcard domain, you can consider using the DNS01 solver although that's a bit more complicated to setup. 

ClusterIssuers do not care about namespaces as they are cluster-wide.

## 6. Ingress Manifest

This manifest comes directly from the [ArgoCD docs](https://argo-cd.readthedocs.io/en/stable/operator-manual/ingress/#kubernetesingress-nginx) with one key change: _the host_. I used my domain name `argocd.terraformingkubernetes.com` but you can use any domain name you have control over.

My actual example is in [config/ingress.yaml](./config/ingress.yaml).

```yaml
# https://argo-cd.readthedocs.io/en/stable/operator-manual/ingress/#kubernetesingress-nginx
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
spec:
  rules:
   - host: argocd.terraformingkubernetes.com
     http:
        paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: argocd-server
              port:
                name: https
  tls:
    - hosts:
      - argocd.terraformingkubernetes.com
      secretName: argocd-secret # do not change, this is provided by Argo CD
```


## 7. Patch ArgoCD ConfigMap and Restart Deployment
```bash
kubectl patch configmap argocd-cmd-params-cm -n argocd -p '{"data":{"server.insecure":"true"}}'
kubectl rollout -n argocd restart deployments/argocd-server
```
If you were to review the deployment manifest, you'd see the following:

```yaml
        env:
        - name: ARGOCD_SERVER_INSECURE
          valueFrom:
            configMapKeyRef:
              key: server.insecure
              name: argocd-cmd-params-cm
              optional: true
```
We want to change this to being `true` so that we can access the ArgoCD via our domain that has a cert-manager-issued certificate. If you skip this section, our ingress will not work and run continuous redirects to itself.


## 8. Get the ArgoCD Admin User Password:

```
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

