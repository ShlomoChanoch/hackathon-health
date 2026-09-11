variable "tenancy_ocid" {
  description = "OCID do tenancy"
  type        = string
}

variable "user_ocid" {
  description = "OCID do usuário"
  type        = string
}

variable "fingerprint" {
  description = "Fingerprint da API key OCI"
  type        = string
}

variable "private_key_path" {
  description = "Caminho da chave privada da API OCI"
  type        = string
}

variable "region" {
  description = "Região OCI"
  type        = string
  default     = "sa-saopaulo-1"
}

variable "compartment_ocid" {
  description = "OCID do compartment onde os recursos serão criados"
  type        = string
}

variable "ssh_cidr" {
  description = "CIDR permitido para SSH (--ssh-cidr)"
  type        = string
}

variable "demo_port" {
  description = "Porta extra de demonstração (--demo-port)"
  type        = number
}

variable "shape" {
  description = "Shape da instância (--shape)"
  type        = string
  default     = "VM.Standard.E4.Flex"
}

variable "ocpus" {
  description = "Número de OCPUs (--ocpus)"
  type        = number
  default     = 1
}

variable "memory" {
  description = "Memória em GB (--memory)"
  type        = number
  default     = 8
}

variable "availability_domain_index" {
  description = "Índice de Availability Domain"
  type        = number
  default     = 0
}

# Timestamp para nomear recursos e a chave SSH
locals {
  timestamp = formatdate("YYYYMMDDhhmmss", timestamp())
}