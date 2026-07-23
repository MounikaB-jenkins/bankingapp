output "alb_dns_name" {
  description = "DNS name of the application load balancer"
  value       = aws_lb.app.dns_name
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = aws_db_instance.postgres.address
}

output "secret_arn" {
  description = "ARN of the RDS credentials secret"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "monitoring_public_ip" {
  description = "Public IP of the monitoring instance"
  value       = aws_instance.monitoring.public_ip
}

# Monitoring service URLs
output "prometheus_url" {
  description = "URL to access Prometheus"
  value       = "http://${aws_instance.monitoring.public_ip}:9090"
}

output "grafana_url" {
  description = "URL to access Grafana (default creds: admin/admin)"
  value       = "http://${aws_instance.monitoring.public_ip}:3000"
}

output "alertmanager_url" {
  description = "URL to access Alertmanager"
  value       = "http://${aws_instance.monitoring.public_ip}:9093"
}

output "node_exporter_port" {
  description = "Node Exporter port for metrics scraping"
  value       = 9100
}
