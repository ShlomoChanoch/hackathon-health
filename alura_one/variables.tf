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
  default     = "us-ashburn-1"
}

variable "compartment_ocid" {
  description = "OCID do compartment onde a VCN já existe e a VM será criada"
  type        = string
}

variable "vcn_id" {
  description = "OCID da VCN já existente"
  type        = string
}

variable "subnet_id" {
  description = "OCID da subnet já existente onde a VM será criada"
  type        = string
}

variable "nsg_id" {
  description = "OCID do NSG já existente"
  type        = string
}

variable "subnet_cidr" {
  description = "CIDR da subnet já existente (informativo)"
  type        = string
  default     = "10.0.1.0/24"
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
  description = "Shape da instância"
  type        = string
  default     = "VM.Standard.A1.Flex"
}

variable "ocpus" {
  description = "Número de OCPUs"
  type        = number
  default     = 2
}

variable "memory" {
  description = "Memória em GB"
  type        = number
  default     = 12
}

variable "availability_domain_index" {
  description = "Índice de Availability Domain"
  type        = number
  default     = 0
}

variable "name_prefix" {
  description = "Prefixo dos nomes dos recursos e da chave SSH"
  type        = string
  default     = "mediflow"
}
