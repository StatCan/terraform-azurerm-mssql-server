data "azurerm_key_vault" "sqlhstkv" {
  count = var.kv_enable ? 1 : 0

  name                = var.kv_name
  resource_group_name = var.kv_rg
}

data "azurerm_key_vault_secret" "sqlhstsvc" {
  count = var.kv_enable ? 1 : 0

  name         = "sqlhstsvc"
  key_vault_id = data.azurerm_key_vault.sqlhstkv[count.index].id
}

data "azurerm_key_vault_secret" "storageaccountname" {
  count = var.kv_enable ? 1 : 0

  name         = "storageaccountname"
  key_vault_id = data.azurerm_key_vault.sqlhstkv[count.index].id
}

data "azurerm_storage_account" "storageaccountinfo" {
  count = var.kv_enable ? 1 : 0

  name                = data.azurerm_key_vault_secret.storageaccountname[count.index].value
  resource_group_name = var.sa_resource_group_name
}
