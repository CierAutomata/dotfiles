require("core.options")
require("core.keymaps")
require("config.lazy")
require('matugen').setup()
require('plugin_config.lsp_config')

vim.lsp.enable("lua-language-server")
