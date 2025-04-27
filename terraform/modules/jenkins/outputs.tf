output "jenkins_url" {
  description = "URL to access Jenkins"
  value       = "http://${aws_instance.jenkins.public_ip}:8080"
}

output "jenkins_instance_id" {
  description = "Instance ID of the Jenkins server"
  value       = aws_instance.jenkins.id
}

output "jenkins_security_group_id" {
  description = "Security group ID of the Jenkins server"
  value       = aws_security_group.jenkins.id
}

output "jenkins_public_ip" {
  description = "Public IP of the Jenkins server"
  value       = aws_instance.jenkins.public_ip
}

output "jenkins_setup_command" {
  description = "Command to check Jenkins setup status"
  value       = "ssh -i ${var.private_key_path} ec2-user@${aws_instance.jenkins.public_ip} 'cat /tmp/jenkins_setup.log'"
}

output "jenkins_status" {
  description = "Information about Jenkins configuration status"
  value       = "Jenkins is configured with secure authentication. Admin username: ${var.jenkins_admin_username}, Password: (sensitive)"
}