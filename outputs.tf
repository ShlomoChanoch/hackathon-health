output "instance_id" {
  value = oci_core_instance.health.id
}

output "public_ip" {
  value = oci_core_instance.health.public_ip
}

output "ssh_user" {
  value = "ubuntu"
}

output "ssh_private_key_path" {
  value = pathexpand("~/.ssh/health-${local.timestamp}")
}

output "ssh_command" {
  value = "ssh -i ~/.ssh/health-${local.timestamp} ubuntu@${oci_core_instance.health.public_ip}"
}

output "vcn_id" {
  value = oci_core_vcn.health.id
}

output "subnet_id" {
  value = oci_core_subnet.health.id
}