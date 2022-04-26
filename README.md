# Authenticated Cloud Run applications with GKE (with Istio) as their backend

_In this tutorial we are going to deploy a publicly accessible front-end application in Google Cloud Run which needs to consume privately hosted microservices running on Google Kubernetes Engine, during their application modernization joirney, many organizations realize that the user-experience or front-end components of their application need to change more often than the backend services itself, they also realize that if they were to quickly build and provision new front-end experiences consuming a matured set of services they have built over the years, they would be placed in much more competitive position in the market._

_A hypothetical company, Acme.com is a leading retailer who has a set of privately hosted microservices on GKE, by private we mean, they are not exposed to the internet but are meant for consumption from trusted internal applications only, as a rule of thumb, they do not allow direct "ingress" from the internet to these services, if there are other applications which are internet facing and want to consume data and functionality these microservices offer, they must connect to these services privately and authenticate themselves before being able to invoke the service endpoints. _

_Matech department of Acme.com decides to launch a new application in response to a lucartive customer acquisition opportunity in the market, they believe that through the existing set of services (in GKE) they should be able mine enough data and information to power an attractive front-end experience, they choose Google Cloud Run as the platform of choice to host front-end applications, given it's simplicity, pay-as-you-execute model, ability to scale while responding to 'bursty' load profile and all that with minimal infrastructure management, yes Martech team do not have K8 experts on their team!_

_As this proposal reaches the IT admins of the GKE services team, they have few concerns:_
_1. How do we trust the martech applications?
2. How do we make sure that our services are never exposed to the internet as martech apps consume them?_


