# Configure the Microsoft Azure Provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
  backend "azurerm" {
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

locals {
  azure-metadeta = "azure.extensions"
}

data "azurerm_client_config" "current" {}

# Resource Group
resource "azurerm_resource_group" "grp" {
  name     = "${var.project_name}-grp"
  location = var.resource_group_location
}

# Log Analiytics Workspace for App Insights
resource "azurerm_log_analytics_workspace" "asa_workspace" {
  name                = "${var.project_name}-workspace"
  location            = azurerm_resource_group.grp.location
  resource_group_name = azurerm_resource_group.grp.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

# Application Insights for ASA Service
resource "azurerm_application_insights" "asa_app_insights" {
  name                = "${var.project_name}-appinsights"
  location            = azurerm_resource_group.grp.location
  resource_group_name = azurerm_resource_group.grp.name
  workspace_id        = azurerm_log_analytics_workspace.asa_workspace.id
  application_type    = "web"
}

# Azure Spring Cloud Service (ASA Service)
resource "azurerm_spring_cloud_service" "asa_service" {
  name = var.asa_name
  network {
    app_subnet_id = var.app_subnet_id
    cidr_ranges = var.cidr_ranges
    service_runtime_subnet_id = var.svc_subnet_id
  }
  resource_group_name      = azurerm_resource_group.grp.name
  location = var.location
  sku_name                 = "E0"
  service_registry_enabled = true
  build_agent_pool_size    = "S2"
  trace {
    connection_string = azurerm_application_insights.asa_app_insights.connection_string
    sample_rate       = 10.0
  }
}

# Gets the Azure Spring Apps internal load balancer IP address once it is deployed
data "azurerm_lb" "asc_internal_lb" {
  resource_group_name = "ap-svc-rt_${azurerm_spring_cloud_service.asa.name}_${azurerm_spring_cloud_service.asa.location}"
  name                = "kubernetes-internal"
  depends_on = [
    azurerm_spring_cloud_service.asa
  ]
}

# Create DNS zone
resource "azurerm_private_dns_zone" "private_dns_zone" {
  name                = "private.azuremicroservices.io"
    resource_group_name      = azurerm_resource_group.grp.name
}

# Link DNS to Azure Spring Apps virtual network
resource "azurerm_private_dns_zone_virtual_network_link" "private_dns_zone_link_asc" {
  name                  = "asc-dns-link"
    resource_group_name      = azurerm_resource_group.grp.name
  private_dns_zone_name = azurerm_private_dns_zone.private_dns_zone.name
  virtual_network_id    = var.virtual_network_id
}

# Creates an A record that points to Azure Spring Apps internal balancer IP
resource "azurerm_private_dns_a_record" "internal_lb_record" {
  name                = "*"
  zone_name           = azurerm_private_dns_zone.private_dns_zone.name
  resource_group_name      = azurerm_resource_group.grp.name
  ttl                 = 300
  records             = [data.azurerm_lb.asc_internal_lb.private_ip_address]
}

resource "azurerm_spring_cloud_certificate" "asa_cert" {
  name                     = var.cert_name
  resource_group_name      = azurerm_resource_group.grp.name
  service_name             = azurerm_spring_cloud_service.asa.name
  key_vault_certificate_id = var.cert_id
}

# Configure Diagnostic Settings for ASA
resource "azurerm_monitor_diagnostic_setting" "asa_diagnostic" {
  name                       = "${var.project_name}-diagnostic"
  target_resource_id         = azurerm_spring_cloud_service.asa_service.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.asa_workspace.id

  enabled_log {
    category = "ApplicationConsole"
    retention_policy {
      enabled = false
      days    = 0
    }
  }
  enabled_log {
    category = "SystemLogs"
    retention_policy {
      enabled = false
      days    = 0
    }
  }
  enabled_log {
    category = "IngressLogs"
    retention_policy {
      enabled = false
      days    = 0
    }
  }

  metric {
    category = "AllMetrics"
    enabled  = true
    retention_policy {
      enabled = false
      days    = 0
    }
  }
}

# Configure Application Configuration Service for ASA
resource "azurerm_spring_cloud_configuration_service" "asa_config_svc" {
  name                    = "default"
  spring_cloud_service_id = azurerm_spring_cloud_service.asa_service.id
  repository {
    name     = "petclinic-config"
    label    = var.config_server_git_setting.label
    //TODO: Uncomment below line after changing the pattern
    //patterns = ["catalog/default", "catalog/key-vault", "identity/default", "identity/key-vault", "payment/default"]
    uri      = var.config_server_git_setting.uri
  }
}

# Configure Tanzu Build Service for ASA
resource "azurerm_spring_cloud_builder" "asa_builder" {
  name                    = "no-bindings-builder"
  spring_cloud_service_id = azurerm_spring_cloud_service.asa_service.id
  build_pack_group {
    name           = "default"
    build_pack_ids = ["tanzu-buildpacks/nodejs", "tanzu-buildpacks/dotnet-core", "tanzu-buildpacks/go", "tanzu-buildpacks/python"]
  }
  stack {
    id      = "io.buildpacks.stacks.bionic"
    version = "full"
  }
}

# Configure Gateway for ASA
resource "azurerm_spring_cloud_gateway" "asa_gateway" {
  name                    = "default"
  spring_cloud_service_id = azurerm_spring_cloud_service.asa_service.id
  api_metadata {
    description = var.spring_cloud_gateway_setting.description
    title       = var.spring_cloud_gateway_setting.title
    version     = var.spring_cloud_gateway_setting.version
  }
  cors {
    allowed_origins = ["*"]
  }
  sso {
    client_id     = var.sso-client-id
    client_secret = var.sso-client-secret
    issuer_uri    = var.sso-issuer-uri
    scope         = var.sso-scope
  }

  public_network_access_enabled = true
  instance_count                = 2
}

# Configure Api Portal for ASA
resource "azurerm_spring_cloud_api_portal" "asa_api" {
  name                    = "default"
  spring_cloud_service_id = azurerm_spring_cloud_service.asa_service.id
  gateway_ids             = [azurerm_spring_cloud_gateway.asa_gateway.id]
  sso {
    client_id     = var.sso-client-id
    client_secret = var.sso-client-secret
    issuer_uri    = var.sso-issuer-uri
    scope         = var.sso-scope
  }

  public_network_access_enabled = true
}

# Create ASA Apps Service
resource "azurerm_spring_cloud_app" "asa_app_service" {
  name = lookup(zipmap(var.asa_apps,
    tolist([var.asa_order_service,
      var.asa_cart_service,
    var.asa_frontend])),
  var.asa_apps[count.index])

  resource_group_name = azurerm_resource_group.grp.name
  service_name        = azurerm_spring_cloud_service.asa_service.name
  is_public           = true

  identity {
    type = "SystemAssigned"
  }
  count = length(var.asa_apps)
  depends_on = [azurerm_monitor_diagnostic_setting.asa_diagnostic, azurerm_spring_cloud_configuration_service.asa_config_svc,
  azurerm_spring_cloud_builder.asa_builder, azurerm_spring_cloud_gateway.asa_gateway, azurerm_spring_cloud_api_portal.asa_api]
}


# Create ASA Apps Service with Tanzu Component binds
resource "azurerm_spring_cloud_app" "asa_app_service_bind" {
  name = lookup(zipmap(var.asa_apps_bind,
    tolist([var.asa_catalog_service,
      var.asa_payment_service,
    var.asa_identity_service])),
  var.asa_apps_bind[count.index])

  resource_group_name = azurerm_resource_group.grp.name
  service_name        = azurerm_spring_cloud_service.asa_service.name
  is_public           = true

  identity {
    type = "SystemAssigned"
  }

  addon_json = jsonencode({
    applicationConfigurationService = {
      resourceId = azurerm_spring_cloud_configuration_service.asa_config_svc.id
    }
    serviceRegistry = {
      resourceId = azurerm_spring_cloud_service.asa_service.service_registry_id
    }
  })

  count = length(var.asa_apps_bind)
  depends_on = [azurerm_monitor_diagnostic_setting.asa_diagnostic, azurerm_spring_cloud_configuration_service.asa_config_svc,
  azurerm_spring_cloud_builder.asa_builder, azurerm_spring_cloud_gateway.asa_gateway, azurerm_spring_cloud_api_portal.asa_api]
}

# Create ASA Apps Deployment
resource "azurerm_spring_cloud_build_deployment" "asa_app_deployment" {
  name = "default"
  spring_cloud_app_id = concat(azurerm_spring_cloud_app.asa_app_service,
  azurerm_spring_cloud_app.asa_app_service_bind)[count.index].id
  build_result_id = "<default>"

  quota {
    cpu    = "1"
    memory = "1Gi"
  }
  count = sum([length(var.asa_apps), length(var.asa_apps_bind)])
}

# Activate ASA Apps Deployment
resource "azurerm_spring_cloud_active_deployment" "asa_app_deployment_activation" {
  spring_cloud_app_id = concat(azurerm_spring_cloud_app.asa_app_service,
  azurerm_spring_cloud_app.asa_app_service_bind)[count.index].id
  deployment_name = azurerm_spring_cloud_build_deployment.asa_app_deployment[count.index].name

  count = sum([length(var.asa_apps), length(var.asa_apps_bind)])
}



# Create Routing for Order Service
resource "azurerm_spring_cloud_gateway_route_config" "asa_app_order_routing" {
  name                    = var.asa_order_service
  spring_cloud_gateway_id = azurerm_spring_cloud_gateway.asa_gateway.id
  spring_cloud_app_id     = azurerm_spring_cloud_app.asa_app_service[0].id
  route {
    description            = "Creates an order for the user."
    filters                = ["StripPrefix=0"]
    order                  = 200
    predicates             = ["Path=/order/add/{userId}", "Method=POST"]
    sso_validation_enabled = true
    title                  = "Create an order."
    token_relay            = true
    classification_tags    = ["order"]
  }
  route {
    description            = "Lookup all orders for the given user"
    filters                = ["StripPrefix=0"]
    order                  = 201
    predicates             = ["Path=/order/{userId}", "Method=GET"]
    sso_validation_enabled = true
    title                  = "Retrieve User's Orders."
    token_relay            = true
    classification_tags    = ["order"]
  }
  depends_on = [azurerm_spring_cloud_active_deployment.asa_app_deployment_activation]
}



# Create Routing for Frontend
resource "azurerm_spring_cloud_gateway_route_config" "asa_app_frontend_routing" {
  name                    = var.asa_frontend
  spring_cloud_gateway_id = azurerm_spring_cloud_gateway.asa_gateway.id
  spring_cloud_app_id     = azurerm_spring_cloud_app.asa_app_service[2].id
  route {
    filters             = ["StripPrefix=0"]
    order               = 1000
    predicates          = ["Path=/**", "Method=GET"]
    classification_tags = ["frontend"]
  }
  depends_on = [azurerm_spring_cloud_active_deployment.asa_app_deployment_activation]
}

