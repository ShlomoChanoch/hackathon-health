provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
  region           = var.region
}

# ------------------------------------------------------------------
# Timestamp fixo (gerado uma vez, no primeiro apply)
# ------------------------------------------------------------------
resource "time_static" "criacao" {}

locals {
  timestamp = formatdate("YYYYMMDDhhmmss", time_static.criacao.rfc3339)
  nome      = "${var.name_prefix}-${local.timestamp}"
}

# ------------------------------------------------------------------
# Data sources
# ------------------------------------------------------------------
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# Imagem fixa: Oracle-Linux-8.10-aarch64-2026.06.15-0 (us-ashburn-1)
# Oracle Linux 8 padrão, ARM (aarch64), para o VM.Standard.A1.Flex (Always Free).
locals {
  image_ocid = "ocid1.image.oc1.iad.aaaaaaaaiwubmcqc7ol27ixzqbiyz2qzzds4vkt2rjncauty2hsjezzb7oeq"
}

# ------------------------------------------------------------------
# Chave SSH ed25519 gerada localmente (sem passphrase)
# ------------------------------------------------------------------
resource "tls_private_key" "ssh" {
  algorithm = "ED25519"
}

resource "local_sensitive_file" "ssh_private_key" {
  content         = tls_private_key.ssh.private_key_openssh
  filename        = pathexpand("~/.ssh/${local.nome}")
  file_permission = "0600"
}

resource "local_sensitive_file" "ssh_public_key" {
  content         = tls_private_key.ssh.public_key_openssh
  filename        = pathexpand("~/.ssh/${local.nome}.pub")
  file_permission = "0644"
}

# ------------------------------------------------------------------
# Compute Instance — Oracle Linux 8.10 (aarch64), IP público, shape flexível
# ------------------------------------------------------------------
resource "oci_core_instance" "vm" {
  compartment_id      = var.compartment_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[var.availability_domain_index].name
  display_name        = local.nome
  shape               = var.shape

  shape_config {
    ocpus         = var.ocpus
    memory_in_gbs = var.memory
  }

  source_details {
    source_type             = "image"
    source_id               = local.image_ocid
    boot_volume_size_in_gbs = 50
  }

  create_vnic_details {
    subnet_id        = var.subnet_id
    display_name     = "${local.nome}-vnic"
    assign_public_ip = true
    hostname_label   = "mediflow"
    nsg_ids          = [var.nsg_id] # NSG já provisionado (fora do Terraform)
  }

  metadata = {
    ssh_authorized_keys = tls_private_key.ssh.public_key_openssh
    user_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
      demo_port = var.demo_port
    }))
  }

  freeform_tags = {
    Project   = "mediflow"
    Name      = local.nome
    ManagedBy = "terraform"
  }

  lifecycle {
    ignore_changes = [metadata["user_data"]]
  }
}
