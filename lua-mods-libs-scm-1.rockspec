package = "lua-mods-libs"
version = "scm-1"
source = {
   url = "git+https://github.com/0-F/lua-mods-libs.git"
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
      ["lua-mods-libs.logging"] = "logging.lua",
      ["lua-mods-libs.utils"] = "utils.lua"
   }
}