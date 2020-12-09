resource "azurerm_public_ip" "boundary-worker" {
  name                = "boundary-worker-ip"
  resource_group_name = azurerm_resource_group.meetup.name
  location            = azurerm_resource_group.meetup.location
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "boundary-worker" {
  name                = "boundary-worker-nic"
  location            = azurerm_resource_group.meetup.location
  resource_group_name = azurerm_resource_group.meetup.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.meetup.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.boundary-worker.id
  }
}
resource "azurerm_linux_virtual_machine" "boundary-worker" {
  name                = "boundary-worker-machine"
  resource_group_name = azurerm_resource_group.meetup.name
  location            = azurerm_resource_group.meetup.location
  size                = "Standard_B1s"
  admin_username      = "ubuntu"
  network_interface_ids = [
    azurerm_network_interface.boundary-worker.id,
  ]

  depends_on = [
    azurerm_linux_virtual_machine.boundary
  ]

  admin_ssh_key {
    username   = "ubuntu"
    public_key = tls_private_key.master.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }
  connection {
    type = "ssh"
    host = azurerm_public_ip.boundary-worker.ip_address
    user = "ubuntu"
    private_key = tls_private_key.master.private_key_pem
  }
  provisioner "file" {
    content     = <<HCL
kms "aead" {
    purpose   = "worker-auth"
    aead_type = "aes-gcm"
    key       = "8fZBjCUfN0TzjEGLQldGY4+iE9AkOvCfjh7+p0GtRBQ="
    key_id    = "global_worker-auth"
}
listener "tcp" {
    purpose = "proxy"
  address = "0.0.0.0:9202"
    tls_disable = true
}

worker {
  name = "worker"
  description = "A default worker"
  address = "${azurerm_public_ip.boundary-worker.ip_address}"

  # Workers must be able to reach controllers on :9202
  controllers = [
    "${azurerm_public_ip.boundary.ip_address}:9201"
  ]

  public_addr = "${azurerm_public_ip.boundary-worker.ip_address}"
}
HCL
    destination = "/tmp/boundary-worker.hcl"
  }
  provisioner "file" {
    source = "boundary"
    destination = "/tmp/boundary"
  }
  provisioner "file" {
    source = "scripts/boundary.sh"
    destination = "/tmp/setup.sh"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo mv /tmp/boundary-worker.hcl /etc/boundary-worker.hcl",
      "sudo mv /tmp/boundary /usr/local/bin/boundary",
      "sudo chmod a+x /usr/local/bin/boundary",
      "chmod a+x /tmp/setup.sh && sudo /tmp/setup.sh worker"
    ]
  }
}
