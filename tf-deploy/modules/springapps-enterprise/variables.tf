variable "resource_group" {
  type = string
}

variable "asa_name" {
  type = string
}

variable "location" {
  type = string
}

variable "app_subnet_id" {
  type = string
}

variable "cidr_ranges" {
  type = list(string)
  default = ["10.4.0.0/16", "10.5.0.0/16", "10.3.0.1/16"]
}

variable "svc_subnet_id" {
  type = string
}

variable "config_server_git_setting" {
  type = object ({
    uri          = string
    label        = optional(string)
    http_basic_auth = optional(object({
      username = string
    }))
  })
  description = "the regions you want the Azure Spring Apps backends to be deployed to."
}

variable "git_repo_password" {
  type = string
  sensitive = true
  default = ""
}

variable "virtual_network_id" {
  type = string
}

variable "cert_id" {
  type = string
}

variable "cert_name" {
  type = string
}

variable "spring_cloud_gateway_setting "{
type = object ({
    title           = string
    version         = string
    description     = string
  })
}

variable "sso-client-id" {
  type        = string
  description = "SSO Provider Client ID"
}

variable "sso-client-secret" {
  type        = string
  description = "SSO Provider Client Secret"
}

variable "sso-issuer-uri" {
  type        = string
  description = "SSO Provider Issuer URI"
}

variable "sso-scope" {
  type        = list(string)
  default     = ["openid", "profile", "email"]
  description = "SSO Provider Scope"
}