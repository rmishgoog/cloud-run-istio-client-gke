#### Authenticate Cloud Run web applications to private GKE services with Istio Ingress Gateway (with mTLS) and Envoy

_Serverless compute is awesome and it's extremely popular with developers who just want to write application code and prefer managed infrastructure as much as possible. Cloud Run (fully managed) on Google Cloud has been an instant hit among orgs who are looking at increasing the development velocity and    innovation at scale without having to go through the churn of provisioning, configuring and managing the infrastructure which is either a cumbersome job or create dependencies on other teams within the organization. Even further, these orgs are also fairly aware of keeping the "portability", "consistency" and "platform neutrality" of their applications intact and thus choose containers as a preferred mode of building, shipping and deploying the applications._

_Google Cloud Run checks all the boxes when it comes to having a compute option on cloud which is "container first", scalable, comes with zero infrastructure/netoworking/storage management and built completely on top of open standards like k-native and kubernetes. Now, that's all good, but as a matter of fact, Kubernetes has sort of evolved into the defacto starndard of building "cloud native" infrastructure and been around us for a while, much before the likes of Cloud Run or k-native in general were popular, organizations who bet heavily on kubernetes, have built enterprise grade APIs, served via microservices type modern applications, running on kubernetes as containers. As these organizations get introduced to serverless compute platforms like Cloud Run, they often want to adopt them for releasing their differentiating user experiences faster (speed to market) but to hydrate these experiences with data, they often need to access the services and APIs they have been running on kubernetes for sometime (in this case assume it's the GKE or Google Kubernetes Engine). But, Cloud Run being managed and run completely by Google Cloud on your behalf, how can these orgs ensure that their shiny/new web apps are accessinng the GKE services in a private and secure manner? Thant is:_

1. _All of the service to service (includin Cloud Run to GKE) communication is authenticated._
2. _All of the service to service communication is done over the private network as much as possible._
3. _One or more Cloud Run services/applications must also authenticate with each other every single time they communicate._

_In this exercise we will go through a similar scenario where an enterprise is looking to innvoate through web applications or APIs deployed quickly and without much friction from infrastructure management side but yet can re-use the data and functionality available as enterprise services hosted on Google Kubernetes Engine (GKE), they must connect their web based public APIs or applications securely and privately to the GKE hosted services, as the norm suggests. While one can think of using an API gateway, but this enterprise has ruled it out because they prefer to expose only coarse grained "business functions" through API gateway and not granular data services which were not made to be available publicly or outside the cluster._

_The system architecture will look like this:_

1. _A web based API (we will call it front-end api) running on Cloud Run._
2. _Envoy Proxy running on Cloud Run as a container, Envoy will act as a gateway to GKE services, front-end api will authenticate using it's service account's auth token to the Cloud Run service hosting Envoy, this service account has been authorized to invoke Envoy Cloud Run service through Cloud IAM._
3. _GKE cluster is hosting a service (let's call it back-end api), the cluster also has Istio service mesh installed and Istio's ingress gateway acts as the entry point for all the traffic entering into the cluster._
4. _Unlike the default ingress gateway configuration which rolls upto an external network load balancer on Google Cloud, we will be exposing it as an internal (and regional) TCP/UDP load balancer._
5. _Ingress gateway has been confiured for "Mutual TLS" or mTLS with CA cert and server certificate/key supplied it it as a Kubernetes secret._
6. _Since Envoy on Cloud Run is acting as a gateway for the front-end api and running on managed infrastruture outside of the private network, we want Envoy to authenticate using client certificates for the Istio ingress gateway (that is, using mTLS) and since Istio ingress gateway is internal only, Envoy must communicate over private RFC1918 IPs._
7. _In this exercise, Envoy container will be supplied with the required certificates and keys and will establish private connectivity to Istio ingress gateway usin "serverless VPC access" vpc connector._
8. _Also, make a note that Envoy Cloud Run service has been configured as an "internal only" service which needs authentication, so the front-end api must provide auth information, must have the right role to invoke the service and use the VPC connector for reaching into the Envoy service._
9. _Lastly, the front-end api, is open to public and can be invoked from anywhere on the internet, while an ideal example would be a truste web-ui, for this exercies, I will stick to a simple REST API calling another (which is in GKE) through a proxy._

##### Execution steps:

Pre-requisites:
1. _Must have access to Google Cloud Platform, you can also sign-up for a free trial with upto $300 free credit on your cloud spends, we will use Terraform for most of the provisioning work and thus you can reliably destroy the resources that you create, free tier may have some quota restrictions on vCPUs and disk size, you can always adjust the no. of nodes in GKE cluster and disk size if needed._
2. _A Google Cloud project with billing enabled, your account should have project owner role on the project, though it's a best practice to follow the principle of least priviliges, for this exercise, the focus is not IAM, we will just use a generic premitive role of owner to execute the resources._
3. _Access to Google Cloud shell, you can log into Google Cloud console and open up your cloud shell instance to execute all the steps from within your browser OR you can alternatively use gcloud SDK installed on your machine/workstation, please note that this exercise makes use of terraform. git, kubectl docker and helm, Google Cloud shell comes installed with all these utilities, else you need to have them installed on your workstation_.
4. _Working knowledge of Kubernetes and Istio is sufficient._
5. _Lastly, time to complete this exercise._

_Clone the source code to your workstation:_
```
git clone https://github.com/rmishgoog/cloud-run-istio-client-gke.git
```
_Authenticate the gcloud CLI, follow the instructions, you will be asked to follow the Google OAuth flow:_
```
gcloud auth login:
```
_Make sure that gcloud SDK is appropriately configured for your account and project, run the below command and check the active account:_
```
gcloud auth list
```
_Run the below command to see the active configuration for gcloud CLI:_
```
gcloud config list
```
_If you do not see the right project selected you can always set it with:_
```
gcloud config set project <your-correct-project-id>
```
_Finally, update the Application Default Credentials (ADCs) to be used by the CLI while reaching out Google Cloud APIs:_
```
gcloud auth application-default login
```
_Above command has no effect on credentials set using gcloud auth login, it only updates a special file at a certain location with auth info and project/billing context which can be used while calling the Google Cloud APIs, you can very well authenticate as a service account if you do not wish to execute the provisioning as your "owner" account._

_If you are working out of Google Cloud Shell, you can use the below command as "one-does-it-all", since it does not have a browser installed:_
```
gcloud auth login --activate --no-launch-browser -quiet --update-adc
```
##### Foundational infrastructure with Terraform and gcloud:
_We will begin with provisioning the basic back-end infrastructure, that is a custom network, a subnetwork, a GKE cluster etc:_
```
cd terraform-automation/kubernetes-backend/
```
_In this directory, create a file terraform.tfvars and provide values for the following variables:_
```
project           = "<your-project-name>"
region            = "<choosen google cloud region"
zone              = "<choosen google cloud zone in the region"
vpcnetworkname    = "<name of your vpc network>"
vpcsubnetworkname = "<name of your subnetwork>"
natgateway        = "<name of your nat gateway>"
routername        = "<name of your regional router>"
machinetype       = "e2-medium"
#Feel free to change the machine type, I would recommend having minimum 4 vCPUs
```
_There's a variables.tf file and you are welcome to change the values here as appropriate, like the number of nodes or name of the cluster._

_Once the values are set, init the terraform so that it can grab the provider plugins etc:_
```
terraform init
```
_Generate a plan and make sure there are no fundamental errors:_
```
terraform plan
```
_Run the terraform configurations:_
```
terraform apply -auto-approve
```
_Once terraform has completed the provisioning, you have the basic set-up you need for the backend, running this terraform configuration also creates a custom custom service account to be used by the nodes in the cluster and also a GCR registry which wil house the container images:_
```
terraform output
```
_Don't copy the text below, it will be different for your project:_
```
gcr-bucket-name = "artifacts.rmishra-serverless-sandbox.appspot.com"
gke-node-sa-email = "backend-gke-nodes-sa@rmishra-serverless-sandbox.iam.gserviceaccount.com"
```
_Assign the service account the "object viewer" role on the Google Cloud Storage thus created as a result of provisioning GCR._
```
gsutil iam ch serviceAccount:<your-service-account-email>:objectViewer gs://<your gcs bucket name>
```
_Next, let's authenticate kubectl CLI because we are going to need it for installing Istio components and as well as our own kubernetes resources:_
```
gcloud container clusters get-credentials backend-services-primary-cluster --zone us-central1-a
```
_The cluster name and zone are the same as I have used in terraform variables, if you choose a different name/zone, please update and execute._

Before moving to the Istio installation, you need to execute the below commands to open up the port 15017, the firewall rules created by GKE do not do so and thus it will prevent the controlplane to invoke the mutating webhook for sidecar injection.
```
gcloud compute firewall-rules list --filter="name~gke-backend-services-primary-cluster-[0-9a-z]*-master"
```
```
gcloud compute firewall-rules update <your-firewall-rule-name-from-above> --allow tcp:10250,tcp:443,tcp:15017
```
##### Istio installtion with Helm:
We will be using Helm to install Istio, feel free to use your preferred method of installation, like istioctl (but you need to download the binaries):
```
helm repo add istio https://istio-release.storage.googleapis.com/charts
```
```
helm repo update
```
```
kubectl create ns istio-system
```
```
helm install istio-base istio/base -n istio-system --kubeconfig <path-to-kube-config>
```
Under your home directory, look for ~/.kube/config, typically this is the config that kubectl will use to determine current cluster's context but you can always provide your own. You can also run the below command to check if you are going after the right cluster:
```
kubectl config current-context
```
```
helm install istiod istio/istiod -n istio-system --wait --kubeconfig <path-to-kube-config>
```
```
kubectl create namespace istio-ingress
```
```
kubectl label namespace istio-ingress istio-injection=enabled
```
_Now, this is where it will get a little interesting, if you just deploy the Ingress Gateway resource as it ships with Istio OSS, it exposes the gateway as a service of type LoadBalancer, which rolls up to an external Network (L4) load balancer on Google Cloud (implementation will vary between cloud providers). However, going back to our business scenario, this is out and out a private GKE cluster with no externally accesible services or endpoints, everything must come through trusted sources and over private networks (either the same network as the GKE cluster is in, or a peered network or a network connected via a VPN or Cloud Interconnect._

_To fulfill this scenario, we will override the helm values and add annotations which will tell GKE to provision the Istio ingress gateway as an internal load balancer (TCP/UDP) on Google Cloud, for simplicity, we will fetch the ILB IPs from the same subnet as the GKE cluster is using._

```
cd ../../istio-helm-overrides-app-manifests/helm-override/
```
```
helm install istio-ingress istio/gateway -n istio-ingress --wait -f ingress-gateway-config.yaml --kubeconfig <path-to-kube-config>
```
_You can verify the Ingress gateway provisioned as a result of the above command, home->kubernetes engine->services and ingress_.

##### Generate certificates and keys for mTLS configurations and securing the Ingress Gateway
_We will simply use opnessl (if you are not on a Linux machine, please follow the instruction in Istio documentation under secure gateways._
```
cd ..
```
```
openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -subj '/O=example Inc./CN=example.com' -keyout example.com.key -out example.com.crt
```
```
openssl req -out services.example.com.csr -newkey rsa:2048 -nodes -keyout services.example.com.key -subj "/CN=services.example.com/O=services organization"
```
```
openssl x509 -req -sha256 -days 365 -CA example.com.crt -CAkey example.com.key -set_serial 0 -in services.example.com.csr -out services.example.com.crt
```
```
kubectl create -n istio-ingress secret generic service-credential --from-file=tls.key=services.example.com.key \
--from-file=tls.crt=services.example.com.crt --from-file=ca.crt=example.com.crt
```
_At this point, you created server certificate keys, also a root CA which we use for signing the CSRs._

_Next, we are going to build the back-end api application and make the container image available in GCR, then we will return to this place:_
```
cd ../../back-end-app/
```
```
gcloud auth configure-docker
```
```
sudo docker build -t gcr.io/<your-project-name>/backend-api:latest .
```
```
docker push gcr.io/rmishra-serverless-sandbox/backend-api:latest
```
_Also, go ahead and build the front-end api, you will be running it in Cloud Run, which comes later but you can opt to build and push the container image now itself._
```
cd ../front-end-app/
```
```
sudo docker build -t gcr.io/rmishra-serverless-sandbox/fronted-api:latest .
```
```
docker push gcr.io/rmishra-serverless-sandbox/fronted-api:latest
```
_Now that the backend-api image is available, we will go back to deploying the our Kubernetes resources._
```
cd ../istio-helm-overrides-app-manifests/custom-service-manifest/
```
_Open the gke-backend-kubernetes-resources.yaml and make sure you update the image URL. Basically just update the project under which your gcr registry is._
```
kubectl apply -f gke-backend-kubernetes-resources.yaml
```
_Next, deploy the gateway and the virtual service._
```
kubectl apply -f gke-backend-istio-resources.yaml
```
_At this point in time, your back-end is fully ready to serve it's consumers and Ingress Gateway is configured to perform mTLS with the connecting clients, but who is the client?_

_Take a look at the architecture, the front-end api does not connect to the GKE backend directly, instead it connects to an internal only Envoy proxy services, also running on Cloud Run, this Envoy instance is going to act as an authenticated client to the Ingress Gateway and will use VPC connector for establishing a private connection to the VPC where the internal load balancer fronting the Ingress Gateway resies. This frees up the web apis to build and store backend authtentication skeletons each time, for them, Envoy will always be the entrypoint, no matter where the backend is._

_So, over to configuring Envoy then! But we need the client certificates and ca certificate (we created that already) in order for Envoy to successfully handle the mTLS with the ingress gateway._

```
cd ..
```
```
openssl req -out client.example.com.csr -newkey rsa:2048 -nodes -keyout client.example.com.key -subj "/CN=client.example.com/O=client organization"
```
```
openssl x509 -req -sha256 -days 365 -CA example.com.crt -CAkey example.com.key -set_serial 1 -in client.example.com.csr -out client.example.com.crt
```
_Copy these client certificates to the envoy-proxy directory._
```
cp client.example.com.crt ../envoy-proxy/
```
```
cp client.example.com.key ../envoy-proxy/
```
```
cp example.com.crt ../envoy-proxy/
```
```
rm client.example.com.crt&& \
rm client.example.com.key
```
_Now, let's go to the Envoy directory, build and deploy the Envoy proxy image to gcr.io_
```
cd ../envoy-proxy/
```
_Please, update the IP of the internal load balancer in the envoy.yaml as allocated to your resource, in a more real world scenario, you would use a resolvable DNS name and also configure Envoy to do SAN based matching based upon your certificates, for demo/learning purposes, I have not used that, neither I own a domain to have real signed certificates with CN and SAN issued to me._
```
endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: <your ILB address>
                port_value: 443
```
_Now, build the image using the docker file provided._
```
sudo docker build -t gcr.io/rmishra-serverless-sandbox/envoy-proxy:latest .
```
```
docker push gcr.io/rmishra-serverless-sandbox/envoy-proxy:latest
```
_Awesome, we have got the Envoy and front-end api pushed, next is to deploy Cloud Run services with front-end api and Envoy containers._
```
cd ../terraform-automation/cloud-run-envoy-proxy/
```
_Create a terraform.tfvars file and customize it per your environment._
```
project        = "<your-project>"
region         = "<your cloud run region, keep it same as GKE cluster>"
vpcnetworkname = "<name of the vpc where GKE cluster is running, this will be used for vpc connectors>"
```
_Pay attention to this resource block in the main.tf file (do not copy)._
```
resource "google_cloud_run_service_iam_member" "member-secondary-service" {
  location = google_cloud_run_service.frontend_client_service.location
  project  = google_cloud_run_service.frontend_client_service.project
  service  = google_cloud_run_service.frontend_client_service.name
  role     = "roles/run.invoker"
  member   = "user:<my project-owner account email who is authenticated with gcloud>"
}
```
_I am deliberately using my developer account, while building the demo, I choose not to expose my service to anyone on the internet and must authenticate the incoming request, I get charged for Cloud Run executions. You can however choose to expose this to "allUsers" as member, while creating the above binding for front-end api._

Run the terraform code:
```
terraform init
```
```
terraform plan
```
```
terraform apply -auto-approve
```
_Once the terraform has finished provisioning your Cloud Run services, you will have the following:_
1. _A front-end service running the front-end api, this needs to call the GKE backend through Envoy._
2. _A proxy service, this is your Envoy proxy, this will negotiate mTLS with Istio Ingress Gateway and reach into ILB over private network, for this purpose (private connectivity) it uses a VPC connector which is also provisioned by terraform._
3. _Envoy service needs authentication and authorization before front-end api can invoke it. Thus through terraform we also create a service account for the front-end api and associate the run.invoker IAM role with this service account on the Envoy proxy service._
4. _The application code in the front-end api uses Google client auth lib to generate an auth token automatically associates with the outbound request to Envoy Cloud Run service, not that you don't have to do anything like token validation or TLS termination in Envoy itself, Cloud Run takes care of it._
5. _It shall also be noted that Envoy service is internal and thus the front-end service must also access it via the VPC connector, read more on ingress controls for Cloud Run in Google's documentation._

_Now, that the services are ready, it's time to test, go to the Google Cloud console->serverless->Cloud Run. Click the front-end api and note down the URI for the front-end api. Our backend service responds at "/persons". Let's give it a try, remember to change the URL to your service!_

```
curl -H "Authorization: Bearer $(gcloud auth print-identity-token)" https://frontend-api-service-wnyq7tk2pa-uc.a.run.app/persons
```
And voila!
```
[
    {
        "id": "1",
        "name": "Nathan Daniels",
        "city": "Plainfield",
        "state": "IL",
        "zip": 60490
    },
    {
        "id": "2",
        "name": "James Baldwin",
        "city": "Naperville",
        "state": "IL",
        "zip": 60540
    },
    {
        "id": "3",
        "name": "Rachel Brown",
        "city": "Bolingbrook",
        "state": "IL",
        "zip": 60440
    }
]
```
You can also add -v option to curl command if you want to see all the good stuff like TLS handshake, verion of TLS used, Envoy added headres etc.

That's it! Feel free to destroy the infrastructure to avoid billing!

```
terraform destroy -auto-approve
```
```
cd ../kubernetes-backend/
```
```
terraform destroy -auto-approve
```
This shall reclaim the kubernetes cluster, networking components and Cloud Run services which would have been major contributors to your billing. If there's anything you provisioned outside of terraform for testing purposes, you need to remove it manually.

#### The opinions, code, configurations etc. are purely for demo and learning puproses and personal with no support or SLAs. Google Cloud is not liable to provide any production or non-production support, patches, security fixes etc. for any of the artifacts used or created in this exercise.
