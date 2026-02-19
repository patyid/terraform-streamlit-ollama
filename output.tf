
output "instance_id" {
  value = aws_instance.cpu_spot.id
}

output "public_ip" {
  value = aws_instance.cpu_spot.public_ip
}

output "public_dns" {
  value = aws_instance.cpu_spot.public_dns
}

output "streamlit_url" {
  value = "http://${aws_instance.cpu_spot.public_ip}:8501"
}

output "ssm_command" {
  value = "aws ssm start-session --target ${aws_instance.cpu_spot.id}"
}

output "ssm_cloudinit_check" {
  value = "aws ssm send-command --instance-ids ${aws_instance.cpu_spot.id} --region ${var.region} --profile paty_admin_profile --document-name AWS-RunShellScript --parameters 'commands=[\"cloud-init status --long || true\",\"sudo tail -200 /var/log/cloud-init-output.log || true\",\"sudo tail -200 /var/log/user-data.log || true\"]' --query Command.CommandId --output text"
}