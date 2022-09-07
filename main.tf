resource "azurerm_mssql_server" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name

  administrator_login          = var.administrator_login
  administrator_login_password = length(data.azurerm_key_vault_secret.sqlhstsvc) > 0 ? data.azurerm_key_vault_secret.sqlhstsvc[0].value : var.administrator_login_password

  version = var.mssql_version

  minimum_tls_version = var.ssl_minimal_tls_version_enforced

  connection_policy = var.connection_policy

  azuread_administrator {
    login_username = var.active_directory_administrator_login_username
    object_id      = var.active_directory_administrator_object_id
    tenant_id      = var.active_directory_administrator_tenant_id
  }

  identity {
    type = "SystemAssigned"
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}


resource "azurerm_mssql_firewall_rule" "mssql" {
  name                = "AllowAzure"
  server_id         = azurerm_mssql_server.this.id
  start_ip_address    = "142.206.2.0"
  end_ip_address      = "142.206.2.255"
}


resource "azurerm_mssql_firewall_rule" "mssqlclients" {
  count               = length(var.firewall_rules)
  
  name                = azurerm_mssql_server.this.name
  server_id           = azurerm_mssql_server.this.id
  start_ip_address    = var.firewall_rules[count.index]
  end_ip_address      = var.firewall_rules[count.index]
}

resource "azurerm_mssql_virtual_network_rule" "this" {
  for_each            = toset(var.subnets)
  
  name                = "rule${index(var.subnets, each.value)}"
  server_id           = azurerm_mssql_server.this.id
  subnet_id           = each.value
}


resource "azurerm_role_assignment" "this" {
  scope                = data.azurerm_storage_account.storageaccountinfo[0].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_mssql_server.this.identity.0.principal_id

  depends_on = [
    azurerm_mssql_server.this,
    azurerm_mssql_firewall_rule.mssql
  ]
}


resource "azurerm_mssql_server_security_alert_policy" "this" {
  server_name         = azurerm_mssql_server.this.name
  resource_group_name = var.resource_group_name

  storage_endpoint           = var.kv_enable ? null : azurerm_storage_account.this[0].primary_blob_endpoint
  storage_account_access_key = var.kv_enable ? null : azurerm_storage_account.this[0].primary_access_key

  state          = "Enabled"
  retention_days = var.retention_days

  email_addresses = var.emails

  depends_on = [
    azurerm_role_assignment.this
  ]
}

resource "azurerm_mssql_server_extended_auditing_policy" "this" {
  server_id = azurerm_mssql_server.this.id

  storage_endpoint           = var.kv_enable ? data.azurerm_storage_account.storageaccountinfo[0].primary_blob_endpoint : azurerm_storage_account.mssql[0].primary_blob_endpoint
  storage_account_access_key = var.kv_enable ? null : azurerm_storage_account.this[0].primary_access_key

  retention_in_days      = var.retention_days
  log_monitoring_enabled = true

  depends_on = [
    azurerm_role_assignment.this,
    azurerm_mssql_server_security_alert_policy.this
  ]
}
resource "azurerm_mssql_server_vulnerability_assessment" "this" {
  server_security_alert_policy_id = azurerm_mssql_server_security_alert_policy.this.id

  storage_container_path     = var.keyvault_enable ? "${data.azurerm_storage_account.storageaccountinfo[0].primary_blob_endpoint}vulnerability-assessment/" : "${azurerm_storage_account.mssql[0].primary_blob_endpoint}${azurerm_storage_container.mssql[0].name}/"
  storage_account_access_key = var.keyvault_enable ? null : azurerm_storage_account.this[0].primary_access_key

  recurring_scans {
    enabled                   = true
    email_subscription_admins = true
    emails                    = var.emails
  }

  depends_on = [
    azurerm_role_assignment.this,
    azurerm_mssql_server_security_alert_policy.this
  ]

}

# resource "azurerm_private_endpoint" "privateep_server" {
#   name                = "${var.name}endpoint"
#   location            = var.location
#   resource_group_name = var.resource_group
#   subnet_id           = data.azurerm_subnet.Subnet.id

#   private_service_connection {
#     name                           = "${var.name}privateserviceconnection"
#     private_connection_resource_id = azurerm_mssql_server.mssql.id
#     is_manual_connection           = false
#     subresource_names              = ["sqlServer"]
#   }
# }
