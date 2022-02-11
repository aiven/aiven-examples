
variable aiven_api_token {
	type = string
}

variable project {
	type = string
}

variable primary_cloud {
	type = string
	default = "google-asia-southeast2"
}

variable remote_cloud {
	type = string
	default = "aws-ap-southeast-1"
}

variable "google_project" {
	type = string
}

variable "gcs_bucket" {
	type = string
}
