variable cloud_name_os_leader {
  type    = string
  default = "google-us-east4"
}
variable cloud_name_os_follower {
  type    = string
  default = "google-us-west4"
}
variable os_leader_plan {
  type = string
  default = "business-4"
}

variable os_follower_plan {
  type = string
  default = "business-4"
}

variable "project" {
  type = string
  default = "mparikh-demo"
}
variable "maint_dow" {
  type    = string
  default = "saturday"
}

variable "maint_time" {
  type    = string
  default = "10:00:00"
}