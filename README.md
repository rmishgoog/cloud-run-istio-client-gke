#### Authenticate Cloud Run web applications to private GKE services with Istio Ingress Gateway (with mTLS) and Envoy

Serverless compute is awesome and it's extremely popular with developers who just want to write application code and prefer managed infrastructure as much as possible. Cloud Run (fully managed) on Google Cloud has been an instant hit among orgs who are looking at increasing the development velocity and    innovation at scale without having to go through the churn of provisioning, configuring and managing the infrastructure which is either a cumbersome job or create dependencies on other teams within the organization. Even further, these orgs are also fairly aware of keeping the "portability", "consistency" and "platform neutrality" of their applications intact and thus choose containers as a preferred mode of building, shipping and deploying the applications.

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

Clone the source code to your workstation:
```
git clone https://github.com/rmishgoog/cloud-run-istio-client-gke.git
```
Authenticate the gcloud CLI, follow the instructions, you will be asked to follow the Google OAuth flow:
```
gcloud auth login:
```
Make sure that gcloud SDK is appropriately configured for your account and project, run the below command and check the active account:
```
gcloud auth list
```
Run the below command to see the active configuration for gcloud CLI:
```
gcloud config list
```
If you do not see the right project selected you can always set it with:
```
gcloud config set project <your-correct-project-id>
```
Finally, update the Application Default Credentials (ADCs) to be used by the CLI while reaching out Google Cloud APIs
```
gcloud auth application-default login
```
Above command has no effect on credentials set using gcloud auth login, it only updates a special file at a certain location with auth info and project/billing context which can be used while calling the Google Cloud APIs, you can very well authenticate as a service account if you do not wish to execute the provisioning as your "owner" account.

If you are working out of Google Cloud Shell, you can use the below command as "one-does-it-all", since it does not have a browser installed:
```
gcloud auth login --activate --no-launch-browser -quiet --update-adc
```
