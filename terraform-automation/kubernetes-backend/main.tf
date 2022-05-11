#This will be a new project, remember to authenticate gcloud CLI with gcloud auth application-default login.
provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone
}

# resource "google_compute_project_metadata_item" "metadata_os_login" {
#   key   = "enable-oslogin"
#   value = "true"
# }

#Enable the required services needed for execution
resource "google_project_service" "enabled_services" {
  project            = var.project
  service            = each.key
  for_each           = toset(["compute.googleapis.com", "container.googleapis.com", "containerregistry.googleapis.com"])
  disable_on_destroy = false
}
#Create a custom vpc network.
resource "google_compute_network" "custom_vpc_network" {
  project                 = var.project
  name                    = var.vpcnetworkname
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  depends_on = [
    google_project_service.enabled_services
  ]
}

#Create a subnetwork in us-central1 region.
resource "google_compute_subnetwork" "custom_vpc_subnetwork" {
  project                  = var.project
  name                     = var.vpcsubnetworkname
  region                   = var.region
  network                  = google_compute_network.custom_vpc_network.id
  ip_cidr_range            = "10.100.0.0/24"
  private_ip_google_access = true
  provisioner "local-exec" {
    command = "sleep 60"
  }
  depends_on = [
    google_project_service.enabled_services
  ]
}

#Create a router in the us-central1 region which will be used by the NAT gateway.
resource "google_compute_router" "custom_vpc_regional_router" {
  project = var.project
  name    = var.routername
  network = google_compute_network.custom_vpc_network.name
  region  = var.region
  bgp {
    asn = var.asn
  }
  provisioner "local-exec" {
    command = "sleep 60"
  }
  depends_on = [
    google_project_service.enabled_services
  ]
}

#Create a NAT gateway which uses the router created in the above step.
resource "google_compute_router_nat" "custom_vpc_regional_nat" {
  project                            = var.project
  name                               = var.natgateway
  router                             = google_compute_router.custom_vpc_regional_router.name
  region                             = google_compute_router.custom_vpc_regional_router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  subnetwork {
    name                    = google_compute_subnetwork.custom_vpc_subnetwork.name
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
  depends_on = [
    google_project_service.enabled_services
  ]
}

#Create a custom service account to be used by the nodes in the kubernetes cluster.
resource "google_service_account" "node_service_account" {
  project      = var.project
  account_id   = var.service_account_id
  display_name = "GKE nodes service account"
}

resource "google_project_iam_member" "node_service_account_viewer" {
  project = var.project
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.node_service_account.email}"
}

resource "google_project_iam_member" "node_service_account_metric_writer" {
  project = var.project
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.node_service_account.email}"
}

resource "google_project_iam_member" "node_service_account_log_writer" {
  project = var.project
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.node_service_account.email}"
}

resource "google_project_iam_member" "node_service_account_metadata_writer" {
  project = var.project
  role    = "roles/stackdriver.resourceMetadata.writer"
  member  = "serviceAccount:${google_service_account.node_service_account.email}"
}

#Create a container registry and give the node service account the viewer role.
resource "google_container_registry" "gke_private_container_registry" {
  project  = var.project
  depends_on = [
    google_project_service.enabled_services
  ]
}
# resource "google_storage_bucket_iam_binding" "gke-node-sa-bucket-viewer" {
#   bucket = google_container_registry.gke_private_container_registry.id
#   role = "roles/storage.objectViewer"
#   members = [
#     "serviceAccount:${google_service_account.node_service_account.email}",
#   ]
# }
# resource "google_storage_bucket_iam_member" "gke-node-sa-storage-viewer" {
#   bucket = google_container_registry.gke_private_container_registry.id
#   role   = "roles/storage.objectViewer"
#   member = "serviceAccount:${google_service_account.node_service_account.email}"
# }

#Create the GKE kubernetes cluster, the master will have a public endpoint with no authorized network.
resource "google_container_cluster" "primary_gke_cluster" {
  project                  = var.project
  name                     = var.clustername
  location                 = var.zone
  initial_node_count       = 1
  remove_default_node_pool = true
  network                  = google_compute_network.custom_vpc_network.id
  subnetwork               = google_compute_subnetwork.custom_vpc_subnetwork.id
  networking_mode          = "VPC_NATIVE"
  enable_shielded_nodes = true
  #dummy stuff so that default node pool creation will not fail-starts.
  node_config {
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
  #dummy stuff so that default node pool creation will not fail-end.
  ip_allocation_policy {
    cluster_ipv4_cidr_block  = "10.32.0.0/14"
    services_ipv4_cidr_block = "10.36.0.0/20"
  }
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }
  addons_config {
    http_load_balancing {
      disabled = false
    }
  }
  depends_on = [
    google_project_service.enabled_services
  ]
}

#Create a node-pool and associate it with the cluster. Just a basic cluster with mostly defaults and no fancy stuff floating around.
resource "google_container_node_pool" "primary_gke_cluster_node_pool" {
  project            = var.project
  name               = "np-${var.clustername}-01"
  cluster            = google_container_cluster.primary_gke_cluster.id
  initial_node_count = var.gke_num_nodes
  node_config {
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
    preemptible     = true
    machine_type    = var.machinetype
    service_account = google_service_account.node_service_account.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
  }
  autoscaling {
    min_node_count = 0
    max_node_count = 4
  }
}

output "gke-node-sa-email" {
  value = google_service_account.node_service_account.email
}
output "gcr-bucket-name" {
  value = google_container_registry.gke_private_container_registry.id
}