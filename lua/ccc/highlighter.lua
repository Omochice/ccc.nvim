local api = vim.api
local fn = vim.fn

local config = require("ccc.config")
local utils = require("ccc.utils")
local rgb2hex = require("ccc.output.hex").str

---@class Highlighter
---@field pickers ColorPicker[]
---@field ns_id integer
---@field aug_id integer
---@field is_defined table<string, boolean> #Set. Keys are hexes.
---@field ft_filter table<string, boolean>
---@field events string[]
---@field enabled boolean
local Highlighter = {}

function Highlighter:init()
    self.pickers = config.get("pickers")
    self.ns_id = api.nvim_create_namespace("ccc-highlighter")
    self.is_defined = {}
    local highlighter_config = config.get("highlighter")
    local filetypes = highlighter_config.filetypes
    local ft_filter = {}
    if #filetypes == 0 then
        for _, v in ipairs(highlighter_config.excludes) do
            ft_filter[v] = false
        end
        setmetatable(ft_filter, {
            __index = function()
                return true
            end,
        })
    else
        for _, v in ipairs(filetypes) do
            ft_filter[v] = true
        end
    end
    self.ft_filter = ft_filter
    self.events = highlighter_config.events
end

function Highlighter:enable()
    if self.pickers == nil then
        self:init()
    end
    self.enabled = true

    self:update()
    self.aug_id = api.nvim_create_augroup("ccc-highlighter", {})
    api.nvim_create_autocmd(self.events, {
        group = self.aug_id,
        pattern = "*",
        callback = function()
            self:update()
        end,
    })
end

function Highlighter:update()
    api.nvim_buf_clear_namespace(0, self.ns_id, 0, -1)
    if not self.ft_filter[vim.bo.filetype] then
        return
    end
    local start_row = fn.line("w0") - 1
    local end_row = fn.line("w$")
    for i, line in ipairs(api.nvim_buf_get_lines(0, start_row, end_row, false)) do
        local row = start_row + i - 1
        local init = 1
        while true do
            local start, end_, RGB
            for _, picker in ipairs(self.pickers) do
                local s_, e_, rgb = picker.parse_color(line, init)
                if s_ and (start == nil or s_ < start) then
                    start = s_
                    end_ = e_
                    RGB = rgb
                end
            end
            if start == nil then
                break
            end
            ---@cast RGB number[]
            local hex = rgb2hex(RGB)
            local hl_name = "CccHighlighter" .. hex:sub(2)
            if not self.is_defined[hex] then
                local highlight = utils.create_highlight(hex)
                api.nvim_set_hl(0, hl_name, highlight)
                self.is_defined[hex] = true
            end
            api.nvim_buf_add_highlight(0, self.ns_id, hl_name, row, start - 1, end_)
            init = end_ + 1
        end
    end
end

function Highlighter:disable()
    self.enabled = false
    api.nvim_buf_clear_namespace(0, self.ns_id, 0, -1)
    api.nvim_del_augroup_by_id(self.aug_id)
end

function Highlighter:toggle()
    if self.enabled then
        self:disable()
    else
        self:enable()
    end
end

return Highlighter
