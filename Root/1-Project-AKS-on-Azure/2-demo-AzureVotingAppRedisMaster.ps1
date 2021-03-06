$var = Get-Content ($pwd.path +"/Root/1-Project-AKS-on-Azure/var.json") | ConvertFrom-Json

$aks = az aks show -n $var.aks_name -g $var.aks_rg | ConvertFrom-Json
if (!$aks)
{
. .\Root\BaseAKSInfra\BaseAKS-External.ps1
}
#get aks credentials
az aks get-credentials -n $var.aks_name -g $var.aks_rg --overwrite-existing --verbose
#Show current Context
Write-Host -ForegroundColor Green "Current Context"
kubectl config get-contexts
#show kube svc
Write-Host -ForegroundColor Green "AKS Deployed Services"
kubectl get svc
#show nodes
Write-Host -ForegroundColor Green "AKS Nodes"
kubectl get nodes
#show pods
Write-Host -ForegroundColor Green "AKS running Pods"
kubectl get pods -A
#show namespace
Write-Host -ForegroundColor Green "AKS Namespaces"
kubectl get ns --show-labels
#show cluster info
Write-Host -ForegroundColor Green "AKS Cluster-info"
kubectl cluster-info
# Create acr
$acr_name = $("acr" + (get-random))
az acr create -g $var.aks_rg --name $acr_name --sku Basic
az acr build -r $acr_name -g $var.aks_rg -t azure-vote-front:v1  .\Root\1-Project-AKS-on-Azure\azure-voting-app-redis-master\azure-vote\
az aks update -n $var.aks_name -g $var.aks_rg --attach-acr $acr_name
$vote = @"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: azure-vote-back
spec:
  replicas: 1
  selector:
    matchLabels:
      app: azure-vote-back
  template:
    metadata:
      labels:
        app: azure-vote-back
    spec:
      nodeSelector:
        "beta.kubernetes.io/os": linux
      containers:
      - name: azure-vote-back
        image: redis
        ports:
        - containerPort: 6379
          name: redis
---
apiVersion: v1
kind: Service
metadata:
  name: azure-vote-back
spec:
  ports:
  - port: 6379
  selector:
    app: azure-vote-back
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: azure-vote-front
spec:
  replicas: 1
  selector:
    matchLabels:
      app: azure-vote-front
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
  minReadySeconds: 5 
  template:
    metadata:
      labels:
        app: azure-vote-front
    spec:
      nodeSelector:
        "beta.kubernetes.io/os": linux
      containers:
      - name: azure-vote-front
        image: $($acr_name + ".azurecr.io/azure-vote-front:v1")
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 250m
          limits:
            cpu: 500m
        env:
        - name: REDIS
          value: "azure-vote-back"
---
apiVersion: v1
kind: Service
metadata:
  name: azure-vote-front
spec:
  type: LoadBalancer
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 80
  selector:
    app: azure-vote-front
"@
$vote | kubectl apply -f -
#get service ip
Write-Host "Service IP for voting App" -ForegroundColor Green
kubectl get service azure-vote-front -o=jsonpath='{.status.loadBalancer.ingress[0].ip}'
# Prompt user to manually modify the script
Read-Host "Modify config_file.cfg file and press enter"
# Push modified image to acr
az acr build -r $acr_name -g $var.aks_rg -t azure-vote-front:v2  .\Root\1-Project-AKS-on-Azure\azure-voting-app-redis-master\azure-vote\
# Prompt host with the image name
write-host "Image $($acr_name + ".azurecr.io/azure-vote-front:v2") has been push to acr"
Write-Host "Use kubectl set image deployment azure-vote-front azure-vote-front=$($acr_name + ".azurecr.io/azure-vote-front:v2") to update the deployment"

