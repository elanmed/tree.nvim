local M = {}

function M.check()
  if vim.fn.executable "tree" == 1 then
    vim.health.ok "tree is installed"
  else
    vim.health.error("tree is not installed", {
      "Install tree: https://en.wikipedia.org/wiki/Tree_(command)",
    })
  end
end

return M
