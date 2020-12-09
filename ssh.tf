resource "tls_private_key" "master" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

output "ssh-key" {
  value = tls_private_key.master.private_key_pem
  sensitive = true
}