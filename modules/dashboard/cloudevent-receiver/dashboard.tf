module "subscription" {
  for_each = var.triggers

  source = "../sections/subscription"
  title  = "Events ${each.key}"

  subscription_prefix   = each.value.subscription_prefix
  alert_threshold       = each.value.alert_threshold
  notification_channels = each.value.notification_channels
}

module "errgrp" {
  source       = "../sections/errgrp"
  title        = "Service Error Reporting"
  project_id   = var.project_id
  service_name = var.service_name
}

module "logs" {
  source = "../sections/logs"
  title  = "Service Logs"
  filter = ["resource.type=\"cloud_run_revision\""]
}

module "http" {
  source       = "../sections/http"
  title        = "HTTP"
  filter       = ["resource.type=\"cloud_run_revision\""]
  service_name = var.service_name
}

module "grpc" {
  source       = "../sections/grpc"
  title        = "GRPC"
  filter       = []
  service_name = var.service_name
}

module "github" {
  source = "../sections/github"
  title  = "GitHub API"
  filter = []
}

module "resources" {
  source        = "../sections/resources"
  title         = "Resources"
  filter        = ["resource.type=\"cloud_run_revision\"", "resource.labels.service_name=\"${var.service_name}\""]
  cloudrun_name = var.service_name

  notification_channels = var.notification_channels
}

module "width" { source = "../sections/width" }

module "layout" {
  // This funky for_each just creates one instance when split_triggers is false
  for_each = var.split_triggers ? {} : {(var.service_name): ""}
  source = "../sections/layout"
  sections = concat(
    [for key in sort(keys(var.triggers)) : module.subscription[key].section],
    [
      module.errgrp.section,
      module.logs.section,
    ],
    var.sections.http ? [module.http.section] : [],
    var.sections.grpc ? [module.grpc.section] : [],
    var.sections.github ? [module.github.section] : [],
    [module.resources.section],
  )
}

module "dashboard-json" {
  for_each = var.split_triggers ? {} : {(var.service_name): ""}

  source = "../json"

  // This funky for_each just creates one instance when split_triggers is false
  object = {
    displayName = "Cloud Event Receiver: ${each.key}"
    labels = merge({
      "service" : ""
      "eventing" : ""
    }, var.labels)
    dashboardFilters = [{
      filterType  = "RESOURCE_LABEL"
      stringValue = each.key
      labelKey    = "service_name"
    }]

    // https://cloud.google.com/monitoring/api/ref_v3/rest/v1/projects.dashboards#mosaiclayout
    mosaicLayout = {
      columns = module.width.size,
      tiles   = module.layout[each.key].tiles,
    }
  }
}

resource "google_monitoring_dashboard" "dashboard" {
  for_each = var.split_triggers ? {} : {(var.service_name): ""}

  dashboard_json = module.dashboard-json[each.key].json
}

// Google cloud has a limit of 50 widgets per dashboard so we create a dashboard
// per trigger so services (like the recorder) with large amounts of triggers
// do not hit the widget limit.
//
// This module is opt-in and will replace the layout module above
module "trigger_layout" {
  for_each = var.split_triggers ? var.triggers : {}
  source   = "../sections/layout"
  sections = concat([module.subscription[each.key].section],
    [
      module.errgrp.section,
      module.logs.section,
    ],
    var.sections.http ? [module.http.section] : [],
    var.sections.grpc ? [module.grpc.section] : [],
    var.sections.github ? [module.github.section] : [],
    [module.resources.section],
  )
}

// Google cloud has a limit of 50 widgets per dashboard so we create a dashboard
// per trigger so services (like the recorder) with large amounts of triggers
// do not hit the widget limit.
//
// This resource is opt-in and will replace the dashboard resource above
module "trigger-dashboard-jsons" {
  for_each = var.split_triggers ? var.triggers : {}

  source = "../json"

  object = {
    displayName = "Cloud Event Receiver: ${var.service_name} (${each.key})"
    labels = merge({
      "service" : ""
      "eventing" : ""
    }, var.labels)
    dashboardFilters = [{
      filterType  = "RESOURCE_LABEL"
      stringValue = var.service_name
      labelKey    = "service_name"
    }]

    // https://cloud.google.com/monitoring/api/ref_v3/rest/v1/projects.dashboards#mosaiclayout
    mosaicLayout = {
      columns = module.width.size
      tiles   = module.trigger_layout[each.key].tiles,
    }
  }
}

resource "google_monitoring_dashboard" "trigger_dashboards" {
  for_each = var.split_triggers ? var.triggers : {}

  dashboard_json = module.trigger-dashboard-jsons[each.key].json
}
