package = "lua-mods-libs"
version = "1.0.2"
source = {
   url = "https://github.com/0-F/lua-mods-libs.git"
}
description = {
   summary = "lua-mods-libs",
   detailed = "",
   license = "MIT"
}
dependencies = {
   "lua >= 5.4",
}
build = {
   type = "builtin",
   modules = {
      ["logging"] = "logging.lua",
      ["utils"] = "utils.lua"
   }
}