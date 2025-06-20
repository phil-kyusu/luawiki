local M = {}

-- Utility functions
local function ind(s, i) return string.sub(s, i, i) end
local function starts(s, pre) return string.sub(s, 1, #pre) == pre end
local function ends(s, post) return string.sub(s, -#post) == post end

local function replace_line(row, new)
  vim.api.nvim_buf_set_lines(0, row - 1, row, true, { new })
end

local function keymap_a(mode, lhs, rhs, opts)
  opts = opts or { buffer = 0 }
  if type(rhs) == "function" then
    local orig = rhs
    rhs = function(...)
      local win_conf = vim.api.nvim_win_get_config(0)
      if win_conf.relative ~= "" then
        return opts.expr and lhs or nil
      end
      return orig(...)
    end
  end
  vim.keymap.set(mode, lhs, rhs, opts)
end

-- Toggle TODO
function M.todo()
  local row, _ = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_buf_get_lines(0, row - 1, row, {})[1] or ""
  local new = ""
  local function istodo(line)
    local i = line:find("-")
    if not i then return 0, 0 end
    local sub = line:sub(i)
    if starts(sub, "- [ ] ") then return 1, i - 1 end
    if starts(sub, "- [X] ") then return 2, i - 1 end
    return 0, i - 1
  end

  local todo_info, spaces = istodo(line)
  if todo_info == 0 then
    if line == "" then
      replace_line(row, "- [ ] ")
      vim.api.nvim_feedkeys("A", "n", false)
    end
    return
  end

  line = line:sub(spaces + 1)
  new = todo_info == 1 and "- [X] " or "- [ ] "
  new = string.rep(" ", spaces) .. new .. line:sub(7)
  replace_line(row, new)
end

-- Continue TODO
function M.continue_todo()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(0, row - 1, row, {})[1]
  local function istodo(line)
    local i = line:find("-")
    if not i then return 0, 0 end
    local sub = line:sub(i)
    if starts(sub, "- [ ] ") then return 1, i - 1 end
    if starts(sub, "- [X] ") then return 2, i - 1 end
    return 0, i - 1
  end

  local res, spaces = istodo(line)
  if res == 0 then return false end
  local rmi = vim.api.nvim_replace_termcodes("cc0<C-D>", true, true, true)
  if line:sub(spaces) == "- [ ] " then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, true, true) .. rmi, "n", false)
  else
    vim.api.nvim_feedkeys(
      vim.api.nvim_replace_termcodes("<CR><Esc>", true, true, true) ..
      rmi .. string.rep(" ", spaces) .. "- [ ] ",
      "n", false
    )
  end
  return true
end

-- Navigation
local Depth = {}
function M.link(filetype)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_buf_get_lines(0, row - 1, row, {})[1]
  local s, e = col, col + 1
  local filemap = M.config.filemaps[filetype]

  while s > 0 and ind(line, s) ~= ' ' do s = s - 1 end
  while e <= #line and ind(line, e) ~= ' ' do e = e + 1 end

  local block = line:sub(s, e):gsub("^%s+", ""):gsub("%s+$", "")
  if starts(block, filemap.linkstart) and ends(block, filemap.linkstop) then
    table.insert(Depth, vim.api.nvim_buf_get_name(0))
    vim.cmd("e " .. filemap.getlink(block))
  elseif #block > 0 then
    vim.api.nvim_buf_set_text(0, row - 1, s, row - 1, e - 1, { filemap.formatlink(block) })
  end
end

function M.goback()
  if #Depth > 0 then vim.cmd("e " .. table.remove(Depth)) end
end

-- Setup
M.config = {}
local defaults = {
  mappings = {
    todo = "<S-CR>",
    backwards = "<BS>",
    follow = "<CR>",
  },
  filemaps = {
    markdown = {
      pattern = { "*.md" },
      linkstart = "[",
      linkstop = ")",
      getlink = function(b)
        local i = b:find("%(")
        return b:sub(i + 1, #b - 1)
      end,
      formatlink = function(b) return "[" .. b .. "](" .. b .. ".md)" end,
    },
    wiki = {
      pattern = { "*.wiki" },
      linkstart = "[[",
      linkstop = "]]",
      getlink = function(b)
        local word = b:sub(3, #b - 2)
        return ends(word, ".md") and word or word .. ".wiki"
      end,
      formatlink = function(b) return "[[" .. b .. "]]" end,
    }
  }
}

function M.setup(user_opts)
  M.config = vim.tbl_deep_extend("force", {}, defaults, user_opts or {})

  for filetype, tbl in pairs(M.config.filemaps) do
    vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
      pattern = tbl.pattern,
      callback = function()
        vim.schedule(function()
          keymap_a("n", M.config.mappings.follow, function() M.link(filetype) end)
          keymap_a("n", M.config.mappings.backwards, M.goback)
          if M.config.mappings.todo then
            keymap_a("n", M.config.mappings.todo, M.todo)
            keymap_a("i", "<CR>", function()
              if not M.continue_todo() then return "<CR>" end
            end, { expr = true, noremap = true, buffer = 0 })
          end
        end)
      end
    })
  end
end

return M
