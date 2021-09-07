#######
# AVN #
#######

variable "aiven_api_token" {
  description = "Aiven API token"
  type        = string
}

variable "aiven_project_name" {
  description = "Project Name"
  type        = string
}

variable "cloud_name" {
  description = "Cloud Name"
  type        = string
}

#########
# Kafka #
#########

variable "kafka_service_name" {
  description = "Kafka Service Name"
  type        = string
}

######
# DB #
######

variable "db_service_name" {
  description = "Database Service Name"
  type        = string
}

variable "redis_service_name" {
  description = "Redis Service Name"
  type        = string
}

########
# O11Y #
########

variable "o11y_service_name" {
  description = "Observability Namespace"
  type        = string
}
