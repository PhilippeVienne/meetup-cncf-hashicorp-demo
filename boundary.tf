resource "azurerm_public_ip" "boundary" {
  name                = "boundary-ip"
  resource_group_name = azurerm_resource_group.meetup.name
  location            = azurerm_resource_group.meetup.location
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "boundary" {
  name                = "boundary-nic"
  location            = azurerm_resource_group.meetup.location
  resource_group_name = azurerm_resource_group.meetup.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.meetup.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.boundary.id
  }
}

resource "random_password" "db-password" {
  length = 45
  special = false
}

resource "azurerm_postgresql_server" "boundary" {
  name                = "db-meetup-demo"
  location            = azurerm_resource_group.meetup.location
  resource_group_name = azurerm_resource_group.meetup.name

  sku_name = "B_Gen5_2"

  storage_mb                   = 5120
  backup_retention_days        = 7
  geo_redundant_backup_enabled = false
  auto_grow_enabled            = false

  administrator_login          = "admindb"
  administrator_login_password = random_password.db-password.result
  version                      = "11"
  ssl_enforcement_enabled      = false
}

resource "azurerm_postgresql_database" "boundary" {
  name                = "boundary"
  resource_group_name = azurerm_resource_group.meetup.name
  server_name         = azurerm_postgresql_server.boundary.name
  charset             = "UTF8"
  collation           = "fr-FR"
}

resource "azurerm_postgresql_firewall_rule" "boundary-private" {
  name                = "boundary"
  resource_group_name = azurerm_resource_group.meetup.name
  server_name         = azurerm_postgresql_server.boundary.name
  start_ip_address    = azurerm_network_interface.boundary.private_ip_address
  end_ip_address      = azurerm_network_interface.boundary.private_ip_address
}

resource "azurerm_postgresql_firewall_rule" "boundary-public" {
  name                = "boundary-public"
  resource_group_name = azurerm_resource_group.meetup.name
  server_name         = azurerm_postgresql_server.boundary.name
  start_ip_address    = azurerm_public_ip.boundary.ip_address
  end_ip_address      = azurerm_public_ip.boundary.ip_address
}

resource "azurerm_linux_virtual_machine" "boundary" {
  name                = "boundary-machine"
  resource_group_name = azurerm_resource_group.meetup.name
  location            = azurerm_resource_group.meetup.location
  size                = "Standard_B1s"
  admin_username      = "ubuntu"
  network_interface_ids = [
    azurerm_network_interface.boundary.id,
  ]

  depends_on = [
    azurerm_postgresql_database.boundary,
    azurerm_postgresql_firewall_rule.boundary-private,
    azurerm_postgresql_firewall_rule.boundary-public
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
    host = azurerm_public_ip.boundary.ip_address
    user = "ubuntu"
    private_key = tls_private_key.master.private_key_pem
  }
  provisioner "file" {
    content     = <<HCL
kms "aead" {
    purpose   = "root"
    aead_type = "aes-gcm"
    key       = "sP1fnF5Xz85RrXyELHFeZg9Ad2qt4Z4bgNHVGtD6ung="
    key_id    = "global_root"
}

kms "aead" {
    purpose   = "worker-auth"
    aead_type = "aes-gcm"
    key       = "8fZBjCUfN0TzjEGLQldGY4+iE9AkOvCfjh7+p0GtRBQ="
    key_id    = "global_worker-auth"
}

kms "aead" {
    purpose   = "recovery"
    aead_type = "aes-gcm"
    key       = "8fZBjCUfN0TzjEGLQldGY4+iE9AkOvCfjh7+p0GtRBQ="
    key_id    = "global_recovery"
}
controller {
  name = "controller"
  description = "Demo Controller"
  database {
    url = "postgresql://${azurerm_postgresql_server.boundary.administrator_login}%40${azurerm_postgresql_server.boundary.name}:${azurerm_postgresql_server.boundary.administrator_login_password}@${azurerm_postgresql_server.boundary.fqdn}:5432/${azurerm_postgresql_database.boundary.name}"
  }
  public_cluster_addr = "${azurerm_public_ip.boundary.ip_address}"
}
listener "tcp" {
  purpose = "api"
  address = "0.0.0.0:9200"
  tls_disable = true
}
listener "tcp" {
  purpose = "cluster"
  address = "0.0.0.0:9201"
  tls_disable = true
}
listener "tcp" {
  purpose = "proxy"
  address = "0.0.0.0:9202"
  tls_disable = true
}
HCL
    destination = "/tmp/boundary-controller.hcl"
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
      "sudo mv /tmp/boundary-controller.hcl /etc/boundary-controller.hcl",
      "sudo mv /tmp/boundary /usr/local/bin/boundary",
      "sudo chmod a+x /usr/local/bin/boundary",
      "chmod a+x /tmp/setup.sh && sudo /tmp/setup.sh controller"
    ]
  }
}

terraform {
  required_providers {
    boundary = {
      source = "hashicorp/boundary"
      version = "0.1.0"
    }
  }
}

provider "boundary" {
  addr = "http://${azurerm_public_ip.boundary.ip_address}:9200"
  recovery_kms_hcl = <<HCL
kms "aead" {
    purpose   = "recovery"
    aead_type = "aes-gcm"
    key       = "8fZBjCUfN0TzjEGLQldGY4+iE9AkOvCfjh7+p0GtRBQ="
    key_id    = "global_recovery"
}
HCL
}

resource "boundary_scope" "org" {
  depends_on = [azurerm_linux_virtual_machine.boundary]
  name                     = "meetup_org"
  description              = "Meetup Organization"
  scope_id                 = "global"
  auto_create_admin_role   = true
  auto_create_default_role = true
}

resource "boundary_scope" "project" {
  name                     = "demo_one"
  description              = "Demo Project"
  scope_id                 = boundary_scope.org.id
  auto_create_admin_role   = true
  auto_create_default_role = true
}


resource "boundary_host_catalog" "k3s" {
  name        = "k3s"
  description = "k3s catalog"
  scope_id    = boundary_scope.project.id
  type        = "static"
}

resource "boundary_host" "k3s" {
  name            = "k3s-host"
  host_catalog_id = boundary_host_catalog.k3s.id
  address         = azurerm_network_interface.meetup.private_ip_address
  type = "static"
}

resource "boundary_host_set" "k3s" {
  name            = "machine"
  host_catalog_id = boundary_host_catalog.k3s.id
  type        = "static"

  host_ids = [
    boundary_host.k3s.id,
  ]
}

resource "boundary_target" "k3s-ssh" {
  name         = "k3s-ssh"
  description  = "SSH Target"
  type        = "tcp"
  default_port = "22"
  scope_id     = boundary_scope.project.id
  host_set_ids = [
    boundary_host_set.k3s.id
  ]
}

resource "boundary_target" "k3s" {
  name         = "k3s"
  type        = "tcp"
  description  = "Kubernetes Target"
  default_port = "6443"
  scope_id     = boundary_scope.project.id
  host_set_ids = [
    boundary_host_set.k3s.id
  ]
  session_connection_limit = -1
  session_max_seconds      = 300
}

resource "boundary_user" "meetup" {
  name     = "meetup"
  scope_id = boundary_scope.org.id
}

resource "boundary_role" "admin-project" {
  scope_id = boundary_scope.org.id
  grant_scope_id = boundary_scope.project.id
  grant_strings = ["id=*;type=*;actions=*"]
  principal_ids  = [boundary_user.meetup.id, "u_auth"]
  name        = "admin-project"
  description = "Project Admin"
}

resource "boundary_role" "admin-org" {
  scope_id = "global"
  grant_scope_id = boundary_scope.org.id
  grant_strings = ["id=*;type=*;actions=*"]
  principal_ids  = [boundary_user.meetup.id, "u_auth"]
  name        = "admin-org"
  description = "Org Admin"
}

resource "boundary_auth_method" "password" {
  scope_id = boundary_scope.org.id
  name = "meetup-auth"
  description="Meetup Authentication"
  type     = "password"
}

resource "boundary_account" "meetup" {
  auth_method_id = boundary_auth_method.password.id
  type           = "password"
  login_name     = "meetup"
  password       = "meetup25112020"
}

output "boundary_host" {
  value = azurerm_public_ip.boundary.ip_address
}

output "boundary_login" {
  value = "boundary authenticate password -auth-method-id=${boundary_auth_method.password.id} -login-name=meetup -password=meetup25112020"
}

output "boundary_kube" {
  value = "boundary connect http -target-id ${boundary_target.k3s.id}"
}

output "boundary_export" {
  value = "export BOUNDARY_ADDR=http://${azurerm_public_ip.boundary.ip_address}:9200"
}