provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = true
    }
  }
}

data "azurerm_client_config" "current" {}
provider "random" {
}
provider "null" {
}

resource "azurerm_resource_group" "MyRG" {
  name     = "MyRG"
  location = "Central US"
}

variable "servers" {
  type        = number
  description = "Enter the number of servers to be created"
  default     = 1
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet"
  location            = azurerm_resource_group.MyRG.location
  resource_group_name = azurerm_resource_group.MyRG.name
  address_space       = ["10.10.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
  count                = var.servers
  name                 = "subnet-${count.index}"
  resource_group_name  = azurerm_resource_group.MyRG.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.${count.index}.0/24"]
}
resource "azurerm_public_ip" "pub_ip" {
  count               = var.servers
  name                = "pub_ip-${count.index}"
  resource_group_name = azurerm_resource_group.MyRG.name
  location            = azurerm_resource_group.MyRG.location
  allocation_method   = "Dynamic"
}
resource "azurerm_network_interface" "nic" {
  count               = var.servers
  name                = "nic-${count.index}"
  location            = azurerm_resource_group.MyRG.location
  resource_group_name = azurerm_resource_group.MyRG.name

  ip_configuration {
    name                          = "ip"
    subnet_id                     = azurerm_subnet.subnet[count.index].id
    public_ip_address_id          = azurerm_public_ip.pub_ip[count.index].id
    private_ip_address_allocation = "Dynamic"
  }
}
resource "random_password" "pass" {
  length           = 7
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
  upper            = true
}

resource "azurerm_linux_virtual_machine" "vm" {
  count               = var.servers
  name                = "vm-${count.index}"
  resource_group_name = azurerm_resource_group.MyRG.name
  location            = azurerm_resource_group.MyRG.location

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }
  size           = "Standard_E2bds_v5"
  admin_username = "abhi1"
  admin_password = random_password.pass.result
  os_disk {
    name                 = "os_disk-${count.index}"
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }
  network_interface_ids           = [azurerm_network_interface.nic[count.index].id]
  disable_password_authentication = false
}
resource "null_resource" "install_apache" {
  count = var.servers
  provisioner "remote-exec" {
    connection {
      host     = azurerm_linux_virtual_machine.vm[count.index].public_ip_address
      user     = azurerm_linux_virtual_machine.vm[count.index].admin_username
      password = random_password.pass.result
      type     = "ssh"
    }
    inline = ["sudo apt-get update -y && sudo apt-get install -y apache2"]
  }
}

#output "vm" {
#  value  = random_password.pass.result
#}

resource "azurerm_key_vault" "vt" {
  count                       = var.servers
  name                        = "vt-key-${count.index}"
  resource_group_name         = azurerm_resource_group.MyRG.name
  location                    = azurerm_resource_group.MyRG.location
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  sku_name = "standard"
  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Get",
    ]

    secret_permissions = [
      "Get",
      "Set",
      "Delete",
      "Purge",
      "Recover",
    ]

    storage_permissions = [
      "Get",
    ]
  }
}
resource "azurerm_network_security_group" "SG" {
  count               = var.servers
  name                = "SG1-${count.index}"
  location            = azurerm_resource_group.MyRG.location
  resource_group_name = azurerm_resource_group.MyRG.name

  security_rule {
    name                       = "ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "22"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}
resource "azurerm_subnet_network_security_group_association" "NSGA" {
  count                     = var.servers
  subnet_id                 = azurerm_subnet.subnet[count.index].id
  network_security_group_id = azurerm_network_security_group.SG[count.index].id
}

