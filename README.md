# Authenticated Cloud Run applications with GKE (with Istio) as their backend

_In this tutorial we are going to deploy a publicly accessible front-end application in Google Cloud Run which needs to consume privately hosted microservices running on Google Kubernetes Engine, during their application modernization joirney, many organizations realize that the user-experience or front-end components of their application need to change more often than the backend services itself, they also realize that if they were to quickly build and provision new front-end experiences consuming a matured set of services they have built over the years, they would be placed in much more competitive position in the market._

_A hypothetical company, Acme.com is a leading retailer who has a set of privately hosted microservices on GKE, by private we mean, they are not exposed to the internet but are meant for consumption from trusted internally developed applications only, as a rule of thumb, they do not allow direct "ingress" from the internet to these services, if there are other applications which are internet facing and want to consume data and functionality these microservices offer, they must connect to these services privately and authenticate themselves before being able to invoke the service endpoints._

_Martech department of Acme.com decides to launch a new application in response to a lucartive customer acquisition opportunity in the market, they believe that through the existing set of services (in GKE) they should be able mine enough data and information to power an attractive front-end experience, they choose Google Cloud Run as the platform of choice to host front-end applications, given it's simplicity, pay-as-you-execute model, ability to scale while responding to 'bursty' load profile and all that with minimal infrastructure management, yes Martech team do not have K8 experts on their team! They are mostly application developers who are looking for a quick-to-launch compute solution with fully managed infrastructure and Google Cloud Run stood out, they prefer to build containers which are consistent and portable between environments._

_At this point, GKE services team is having concerns around trusting the martech apps, authenticating them, allowing private-only communication, unfortunately they don't have any API gateway of sorts, neither it's feasible to implement one, however, they do have Istio! In the remaining tutorial, we will explore how a Cloud Run hosted application will authenticate with Istio ingress gateway using mTLS and will use serverless VPC access to communicate with a L4 internal load balancer privately, behind which the Istio ingress gateway will process and route the incoming traffic._

_It's important to note that while to many an API gateway solution may sounds like ideal, API gateways are not just technical components, they need to be more strategic placement in the architecture, primarily exposing business capabilities over fine-grained data services, you would typically bring a more orchestrated and abstracted API as a coarse-grained endpoint to the API gateway over exposing individual services which can serve a data point but may or maynot represent a business capability of an organization._

_Thoughtfully, the GKE services team decides to leverage Istio ingress gateway as the sole entrypoint to the services that application clients on Cloud Run want to consume, they already had the ingress gateway available behind an internal load balancer, the ingress gateway is already requiring mTLS for incoming requests. For the web front-end clients, they provision a set of Envoy proxies, configured with certficates and keys to authenticate to ingress gateway and decide to run these proxies on Cloud Run as containers! These proxy services are they only entrypoint to ingress gateways and they reach into ingress gateways through serverless connectors, thus over a private network._

_Client web apps, in turn use service accounts (with invoker IAM) role to access Cloud Run containers running Envoy proxies (proxies are not exposed to web but can be invoked by another Cloud Run service authenticated to do so). This architecture yields several benefits_

_1.Martech teams gains speed to market by deploying to Cloud Run while focusing solely on application logic
2.GKE services team do not have to change anything they possess today neither they need to provision infrastructure to host authenticated proxies, they can also get benefits of Cloud Run's fully managed infrastructure
3.Given Envoy's amazing capabilities to act as edge-proxies and side-cars, martech apps are relieved from building networking logic, resiliency, observability and traffic routing mechanism into their code, Envoy does that for them
4.And of course, they do not need API gateways for such one-off deployments_
