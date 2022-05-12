provider "google-beta" {
  project = var.project
  region  = var.region
}

resource "google_project_service" "enabled_services" {
  project            = var.project
  service            = each.key
  for_each           = toset(["run.googleapis.com", "vpcaccess.googleapis.com"])
  disable_on_destroy = false

}

resource "google_vpc_access_connector" "connector" {
  name          = "primary-connector"
  provider      = google-beta
  region        = var.region
  ip_cidr_range = "10.8.0.0/28"
  network       = data.google_compute_network.primary_custom_vpc.name
  depends_on    = [google_project_service.enabled_services]
}

data "google_compute_network" "primary_custom_vpc" {
  project = var.project
  name = var.vpcnetworkname
}

resource "google_cloud_run_service" "envoy_proxy_service" {
  name     = var.proxyname
  provider = google-beta
  location = var.region
  project  = var.project
  metadata {
    annotations = {
      "run.googleapis.com/ingress" = "internal"
    }
  }
  template {
    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale"        = "1000"
        "autoscaling.knative.dev/min-scale"       = "3"
        "run.googleapis.com/vpc-access-connector" = google_vpc_access_connector.connector.name
        "run.googleapis.com/vpc-access-egress"    = "all-traffic"
      }
    }
    spec {
      containers {
        env {
          name = "ENVOY_UID"
          value = "0"
        }
        ports {
          container_port = 8080
          protocol = "TCP"

        }
        image = "gcr.io/${var.project}/envoy-proxy:latest"
      }
    }
  }
  traffic {
    percent         = 100
    latest_revision = true
  }
  depends_on = [
    google_project_service.enabled_services
  ]
}

resource "google_service_account" "frontend_service_account" {
  project      = var.project
  account_id   = var.service_account_id
  display_name = "cloud run front-end service account"
}

resource "google_cloud_run_service_iam_binding" "binding" {
  location = google_cloud_run_service.envoy_proxy_service.location
  project  = google_cloud_run_service.envoy_proxy_service.project
  service  = google_cloud_run_service.envoy_proxy_service.name
  role     = "roles/run.invoker"
  members = [
    "serviceAccount:${google_service_account.frontend_service_account.email}",
  ]
}

resource "google_cloud_run_service" "frontend_client_service" {
  name     = var.frontendservicename
  provider = google-beta
  location = var.region
  project  = var.project
  metadata {
    annotations = {
      "run.googleapis.com/ingress" = "all"
    }
  }
  template {
    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale"        = "1000"
        "autoscaling.knative.dev/min-scale"       = "3"
        "run.googleapis.com/vpc-access-connector" = google_vpc_access_connector.connector.name
        "run.googleapis.com/vpc-access-egress"    = "all-traffic"
      }
    }
    spec {
      service_account_name = google_service_account.frontend_service_account.email
      containers {
        image = "gcr.io/${var.project}/fronted-api:latest"
        env {
          name  = "BACKEND_AUDIENCE_URL"
          value = "${google_cloud_run_service.envoy_proxy_service.status[0].url}"
        }
        env {
          name  = "BACKEND_TARGET_URL"
          value = "${google_cloud_run_service.envoy_proxy_service.status[0].url}/persons"
        }
      }
    }
  }
  traffic {
    percent         = 100
    latest_revision = true
  }
  depends_on = [
    google_project_service.enabled_services
  ]
}

resource "google_cloud_run_service_iam_member" "member-secondary-service" {
  location = google_cloud_run_service.frontend_client_service.location
  project  = google_cloud_run_service.frontend_client_service.project
  service  = google_cloud_run_service.frontend_client_service.name
  role     = "roles/run.invoker"
  member   = "user:rmishra-project-owner@rohitmishra.altostrat.com"
}