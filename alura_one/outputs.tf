output "instance_id" {
  value = oci_core_instance.vm.id
}

output "public_ip" {
  value = oci_core_instance.vm.public_ip
}

output "ssh_user" {
  value = "opc"
}

output "ssh_private_key_path" {
  value = local_sensitive_file.ssh_private_key.filename
}

output "ssh_command" {
  value = "ssh -o PubkeyAcceptedKeyTypes=+ssh-ed25519 -i ${local_sensitive_file.ssh_private_key.filename} opc@${oci_core_instance.vm.public_ip}"
}

output "subnet_id" {
  value = var.subnet_id
}

output "vcn_id" {
  value = var.vcn_id
}
