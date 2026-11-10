output "vm_id" {
  description = "EC2 instance ID of the k3s node."
  value       = aws_instance.k3s.id
}

output "vm_private_ip" {
  description = "Private IP of the k3s node."
  value       = aws_instance.k3s.private_ip
}

output "vm_public_ip" {
  description = "Public IP of the k3s node, or an empty string."
  value       = aws_instance.k3s.public_ip
}
