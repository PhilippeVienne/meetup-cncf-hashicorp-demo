locals {
  k3sMasterOptions = [
    "--node-name \"meetup-master\"",
    "--with-node-id",
    "--node-ip \"${azurerm_network_interface.meetup.private_ip_address}\"",
    "--node-external-ip \"${azurerm_public_ip.meetup.ip_address}\"",
    "--tls-san \"${azurerm_public_ip.meetup.ip_address}\"",
    "--tls-san \"${azurerm_network_interface.meetup.private_ip_address}\"",
    "--advertise-address \"${azurerm_network_interface.meetup.private_ip_address}\"",
    "--advertise-port \"6443\"",
    "--node-label \"k3s-role=master\"",
  ]
}

resource "null_resource" "k3s" {
  depends_on = [
    azurerm_linux_virtual_machine.meetup
  ]

  triggers = {
    host: azurerm_linux_virtual_machine.meetup.id,
    options: md5(join(" ", local.k3sMasterOptions))
  }

  provisioner "remote-exec" {
    inline = [
      "sudo service k3s stop",
      "sudo rm -rf /etc/rancher/k3s /var/lib/rancher/k3s/server/manifests/* /var/lib/rancher/k3s/agent /etc/systemd/system/k3s.service",
      "curl -sfL https://get.k3s.io | sh -s - server ${join(" ", local.k3sMasterOptions)}",
    ]
  }

  connection {
    type = "ssh"
    host = azurerm_public_ip.meetup.ip_address
    user = "ubuntu"
    private_key = tls_private_key.master.private_key_pem
  }
}

data "external" "kubeconfig" {
  program = [
    "/usr/bin/bash",
    "${path.module}/scripts/k3s_info.sh"]

  depends_on = [
    null_resource.k3s
  ]

  query = {
    file = "/etc/rancher/k3s/k3s.yaml"

    host = azurerm_public_ip.meetup.ip_address
    user = "ubuntu"
    private_key = tls_private_key.master.private_key_pem
  }
}

output "kubeconfig" {
  value = replace(data.external.kubeconfig.result.content, "https://127.0.0.1", "https://${azurerm_public_ip.meetup.ip_address}")
  sensitive = true
}