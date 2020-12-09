provider "azurerm" {
  version = "~>2.0"
  features {
    virtual_machine {
      delete_os_disk_on_deletion = true
      graceful_shutdown = false
    }
  }
}

resource "azurerm_resource_group" "meetup" {
  name = "meetup-demo"
  location = "West Europe"
}

resource "azurerm_virtual_network" "meetup" {
  name                = "meetup-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.meetup.location
  resource_group_name = azurerm_resource_group.meetup.name
}

resource "azurerm_subnet" "meetup" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.meetup.name
  virtual_network_name = azurerm_virtual_network.meetup.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_public_ip" "meetup" {
  name                = "meetup-ip"
  resource_group_name = azurerm_resource_group.meetup.name
  location            = azurerm_resource_group.meetup.location
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "meetup" {
  name                = "meetup-nic"
  location            = azurerm_resource_group.meetup.location
  resource_group_name = azurerm_resource_group.meetup.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.meetup.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id = azurerm_public_ip.meetup.id
  }
}

locals {
  filterKube = 0
}

resource "azurerm_linux_virtual_machine" "meetup" {
  name                = "meetup-machine"
  resource_group_name = azurerm_resource_group.meetup.name
  location            = azurerm_resource_group.meetup.location
  size                = "Standard_F2s_v2"
  admin_username      = "ubuntu"
  network_interface_ids = [
    azurerm_network_interface.meetup.id,
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
}

resource "azurerm_network_security_group" "kubectl" {
  count = local.filterKube
  name                = "kubernetesSecurityGroup"
  location            = azurerm_resource_group.meetup.location
  resource_group_name = azurerm_resource_group.meetup.name
}

resource "azurerm_network_security_rule" "kubectl" {
  count = local.filterKube

  name                        = "deny-web-kubectl"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "6443"
  source_address_prefix       = "Internet"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.meetup.name
  network_security_group_name = azurerm_network_security_group.kubectl[count.index].name
}

resource "azurerm_network_interface_security_group_association" "kubectl" {
  count = local.filterKube
  network_interface_id = azurerm_network_interface.meetup.id
  network_security_group_id = azurerm_network_security_group.kubectl[count.index].id
}