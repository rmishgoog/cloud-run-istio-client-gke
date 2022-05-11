variable "project" {

}
variable "region" {

}
variable "vpcnetworkname" {

}
variable "proxyname" {
  default = "cloudrun-envoy-proxy"
}
variable "frontendservicename" {
  default = "frontend-api-service"
}

variable "service_account_id" {
  default = "front-end-api-sa"
}