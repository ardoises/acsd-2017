package = "editor"
version = "master-1"
source  = {
  url    = "git+https://github.com/ardoises/acsd-2017.git",
  branch = "master",
}

description = {
  summary    = "Ardoises Editor: simplified version",
  detailed   = [[]],
  homepage   = "https://github.com/ardoises/acsd-2017",
  license    = "MIT/X11",
  maintainer = "Alban Linard <alban@linard.fr>",
}

dependencies = {
  "lua >= 5.1",
  "busted",
  "cluacov",
  "copas",
  "layeredata",
  "luacheck",
  "luacov",
}

build = {
  type    = "builtin",
  modules = {
    ["editor"] = "src/editor.lua",
  },
}
