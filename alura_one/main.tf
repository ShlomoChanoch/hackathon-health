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

# Imagem fixa: Oracle-Linux-9.8-aarch64-2026.07.20-0 (us-ashburn-1)
# Oracle Linux 9 padrão, ARM (aarch64), para o VM.Standard.A1.Flex (Always Free).
# Fonte: https://docs.oracle.com/iaas/images/oracle-linux-9x/oracle-linux-9-8-aarch64-2026-07-20-0.htm
# O OCID muda por região: se trocar a região, pegue o OCID da mesma página.
locals {
  image_ocid = "ocid1.image.oc1.iad.aaaaaaaasa3tan7k3zh5lb4g7ntg2cqsuwvwgwbkf4efgybjbbephwc2pj7a"
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
# Compute Instance — Oracle Linux 9.8 (aarch64), IP público, shape flexível
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
    # Só OCIDs e nomes vão no user_data; os segredos a VM lê do Vault no boot.
    user_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
      repo_ssh_url           = var.repo_ssh_url
      ocir_user              = var.ocir_user
      deploy_key_secret_ocid = var.deploy_key_secret_ocid
      ocir_token_secret_ocid = var.ocir_token_secret_ocid
    }))
  }

  freeform_tags = {
    Project   = "mediflow"
    Name      = local.nome
    ManagedBy = "terraform"
  }

  # Tag que coloca a VM no dynamic group Mediflow/mediflow-vm.
  # O namespace Mediflow e a key Instances precisam existir antes do apply.
  defined_tags = {
    "Mediflow.Instances" = "mediflow-vm"
  }

  lifecycle {
    ignore_changes = [
      metadata["user_data"],
      # Tag defaults da OCI: sem isto, todo plan tentaria removê-las
      defined_tags["Oracle-Tags.CreatedBy"],
      defined_tags["Oracle-Tags.CreatedOn"],
    ]
  }
}

# ------------------------------------------------------------------
# DuckDNS: aponta mediflow-oci.duckdns.org para o IP público da VM.
# Roda na SUA máquina (precisa de curl), no apply, sempre que o IP muda
# (VM nova ou -replace). O DuckDNS responde OK ou KO.
# ------------------------------------------------------------------
resource "terraform_data" "duckdns" {
  triggers_replace = [oci_core_instance.vm.public_ip]

  provisioner "local-exec" {
    command = "test \"$(curl -s --max-time 30 'https://www.duckdns.org/update?domains=${var.duckdns_domain}&token=${var.duckdns_token}&ip=${oci_core_instance.vm.public_ip}')\" = OK"
  }
}
