provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

# ------------------------------------------------------------------
# Data sources
# ------------------------------------------------------------------
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_core_images" "ubuntu_2404" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = var.shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# ------------------------------------------------------------------
# Chave SSH ed25519 gerada localmente (sem passphrase)
# ------------------------------------------------------------------
resource "tls_private_key" "ssh" {
  algorithm = "ED25519"
}

resource "local_sensitive_file" "ssh_private_key" {
  content         = tls_private_key.ssh.private_key_openssh
  filename        = pathexpand("~/.ssh/health-${local.timestamp}")
  file_permission = "0600"
}

resource "local_sensitive_file" "ssh_public_key" {
  content         = tls_private_key.ssh.public_key_openssh
  filename        = pathexpand("~/.ssh/health-${local.timestamp}.pub")
  file_permission = "0644"
}

# ------------------------------------------------------------------
# VCN 10.42.0.0/16
# ------------------------------------------------------------------
resource "oci_core_vcn" "health" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = ["10.42.0.0/16"]
  display_name   = "health-${local.timestamp}"
  dns_label      = "healthvcn"
}

# ------------------------------------------------------------------
# Internet Gateway
# ------------------------------------------------------------------
resource "oci_core_internet_gateway" "health" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.health.id
  display_name   = "health-igw-${local.timestamp}"
  enabled        = true
}

# ------------------------------------------------------------------
# Route Table padrão: 0.0.0.0/0 -> IGW
# ------------------------------------------------------------------
resource "oci_core_default_route_table" "health" {
  manage_default_resource_id = oci_core_vcn.health.default_route_table_id

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.health.id
  }
}

# ------------------------------------------------------------------
# Security List padrão
#   TCP 22 do ssh_cidr
#   TCP 80, 443 e demo_port de 0.0.0.0/0
# ------------------------------------------------------------------
resource "oci_core_default_security_list" "health" {
  manage_default_resource_id = oci_core_vcn.health.default_security_list_id

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    protocol  = "6" # TCP
    source    = var.ssh_cidr
    stateless = false
    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    protocol  = "6"
    source    = "0.0.0.0/0"
    stateless = false
    tcp_options {
      min = 80
      max = 80
    }
  }

  ingress_security_rules {
    protocol  = "6"
    source    = "0.0.0.0/0"
    stateless = false
    tcp_options {
      min = 443
      max = 443
    }
  }

  ingress_security_rules {
    protocol  = "6"
    source    = "0.0.0.0/0"
    stateless = false
    tcp_options {
      min = var.demo_port
      max = var.demo_port
    }
  }

  # ICMP opcional (facilita debug)
  ingress_security_rules {
    protocol  = "1"
    source    = "0.0.0.0/0"
    stateless = false
    icmp_options {
      type = 3
      code = 4
    }
  }
}

# ------------------------------------------------------------------
# Subnet 10.42.0.0/24 com IP público permitido na VNIC
# ------------------------------------------------------------------
resource "oci_core_subnet" "health" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.health.id
  cidr_block                 = "10.42.0.0/24"
  display_name               = "health-subnet-${local.timestamp}"
  dns_label                  = "healthsub"
  route_table_id             = oci_core_vcn.health.default_route_table_id
  security_list_ids          = [oci_core_vcn.health.default_security_list_id]
  prohibit_public_ip_on_vnic = false
}

# ------------------------------------------------------------------
# Compute Instance — Ubuntu 24.04, IP público, shape flexível
# ------------------------------------------------------------------
resource "oci_core_instance" "health" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[var.availability_domain_index].name
  display_name        = "health-${local.timestamp}"
  shape               = var.shape

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_2404.images[0].id
    boot_volume_size_in_gbs = 50
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.health.id
    display_name     = "health-vnic-${local.timestamp}"
    assign_public_ip = true
    hostname_label   = "health"
  }

  metadata = {
    ssh_authorized_keys = tls_private_key.ssh.public_key_openssh
    user_data           = base64encode(file("${path.module}/cloud-init.yaml"))
  }

  freeform_tags = {
    Project   = "hackinova"
    Name      = "health-${local.timestamp}"
    ManagedBy = "terraform"
  }

  lifecycle {
    ignore_changes = [metadata["user_data"]]
  }
}