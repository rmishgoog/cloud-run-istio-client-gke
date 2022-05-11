variable "gke_num_nodes" {
  default = "4"
}
variable "service_account_id" {
  default = "backend-gke-nodes-sa"
}
variable "clustername" {
  default = "backend-services-primary-cluster"
}
variable "project" {
}
variable "region" {
}
variable "zone" {
}
variable "vpcnetworkname" {
}
variable "vpcsubnetworkname" {
}
variable "natgateway" {
}
variable "routername" {
}
variable "asn" {
  default = 64514
}
variable "machinetype" {
}