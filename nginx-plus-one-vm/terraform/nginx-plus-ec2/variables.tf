variable "aws_region" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ssh_public_key" {
  type = string
}

variable "ssh_cidr" {
  type    = string
  default = "0.0.0.0/0"
}

variable "name_prefix" {
  type    = string
  default = "nginx-plus"
}

variable "tags" {
  type    = map(string)
  default = {}
}
