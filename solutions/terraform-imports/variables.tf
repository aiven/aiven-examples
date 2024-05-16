variable "project" {
    description = "A name for identifying grouped services"
    default = "sa-sandbox"
}

variable "region" {
    description = "The cloud where service will be created"
    default = "google-us-east1"
}

variable "aiven_api_token" {
    description = "The api token for the environment prod or dev"
}
