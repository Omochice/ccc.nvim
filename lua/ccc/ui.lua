local api = vim.api

local set_hl = api.nvim_set_hl
local add_hl = api.nvim_buf_add_highlight

local Color = require("ccc.color")
local config = require("ccc.config")
local utils = require("ccc.utils")

---@alias input_mode "RGB" | "HSL"
---@alias output_mode "RGB" | "HSL" | "ColorCode"

---@class UI
---@field color Color
---@field input_mode input_mode
---@field output_mode output_mode
---@field bufnr integer
---@field win_id integer
---@field ns_id integer
---@field row integer 1-index
---@field start_col integer 1-index
---@field end_col integer 1-index
---@field is_insert boolean
---@field already_open boolean
local UI = {}

local opts = {
    height = 4,
}

function UI:init()
    self.input_mode = self.input_mode or config.get("default_input_mode")
    self.output_mode = self.output_mode or config.get("default_output_mode")
    self.color = Color.new(self.input_mode)
    self.ns_id = self.ns_id or api.nvim_create_namespace("ccc")
    local cursor_pos = api.nvim_win_get_cursor(0)
    self.row = cursor_pos[1]
    self.start_col = cursor_pos[2] + 1
    self.end_col = cursor_pos[2]
end

---@param insert boolean
function UI:open(insert)
    if self.already_open then
        return
    end
    self.already_open = true
    self:init()
    self.is_insert = insert
    if not insert then
        self:pick()
    end
    if self.bufnr == nil then
        self.bufnr = api.nvim_create_buf(false, true)
    end
    opts.width = 7 + config.get("bar_len")
    local win_opts = vim.tbl_extend("error", opts, config.get("win_opts"))
    for k, v in pairs(win_opts) do
        if type(v) == "function" then
            win_opts[k] = v()
        end
    end
    self.win_id = api.nvim_open_win(self.bufnr, true, win_opts)
    self:update()

    local mappings = config.get("mappings")
    for lhs, rhs in pairs(mappings) do
        vim.keymap.set("n", lhs, rhs, { nowait = true, buffer = self.bufnr })
    end
    if insert then
        utils.feedkey("<Esc>")
    end
    vim.opt_local.buftype = "nofile"
end

function UI:close()
    if self.win_id == nil then
        return
    end
    local mappings = config.get("mappings")
    for lhs, _ in pairs(mappings) do
        vim.keymap.del("n", lhs, { buffer = self.bufnr })
    end
    api.nvim_win_close(self.win_id, true)
    if self.is_insert then
        vim.cmd("startinsert")
    end
    api.nvim_win_set_cursor(0, { self.row, self.start_col - 1 })
    self.already_open = false
end

function UI:quit()
    self:close()
end

function UI:complete()
    self:close()
    if self.is_insert then
        self:insert()
    else
        self:replace()
    end
end

function UI:insert()
    vim.api.nvim_feedkeys(self:output(), "n", false)
end

function UI:replace()
    local line = api.nvim_get_current_line()
    local new_line = line:sub(1, self.start_col - 1) .. self:output() .. line:sub(self.end_col + 1)
    api.nvim_set_current_line(new_line)
end

local function update_end(is_point, start, bar_char_len, point_char_len)
    if is_point then
        return start + point_char_len
    else
        return start + bar_char_len
    end
end

function UI:highlight_rgb()
    local R, G, B = self.color:get_rgb()
    local bar_char = config.get("bar_char")
    local point_char = config.get("point_char")
    local bar_len = config.get("bar_len")
    local point_idx_R = utils.ratio(R, 255, bar_len)
    local point_idx_G = utils.ratio(G, 255, bar_len)
    local point_idx_B = utils.ratio(B, 255, bar_len)
    local start_R, start_G, start_B = 7, 7, 7
    local end_R, end_G, end_B
    for i = 0, bar_len - 1 do
        end_R = update_end(i == point_idx_R, start_R, #bar_char, #point_char)
        end_G = update_end(i == point_idx_G, start_G, #bar_char, #point_char)
        end_B = update_end(i == point_idx_B, start_B, #bar_char, #point_char)

        local r_color = Color:colorcode(utils.round((i + 0.5) * 255 / bar_len), G, B)
        local g_color = Color:colorcode(R, utils.round((i + 0.5) * 255 / bar_len), B)
        local b_color = Color:colorcode(R, G, utils.round((i + 0.5) * 255 / bar_len))
        set_hl(0, "CccR" .. i, { fg = r_color })
        set_hl(0, "CccB" .. i, { fg = g_color })
        set_hl(0, "CccG" .. i, { fg = b_color })
        add_hl(0, self.ns_id, "CccR" .. i, 0, start_R, end_R)
        add_hl(0, self.ns_id, "CccB" .. i, 1, start_G, end_G)
        add_hl(0, self.ns_id, "CccG" .. i, 2, start_B, end_B)

        start_R, start_G, start_B = end_R, end_G, end_B
    end
end

function UI:highlight_hsl()
    local H, S, L = self.color:get_hsl()
    local bar_char = config.get("bar_char")
    local point_char = config.get("point_char")
    local bar_len = config.get("bar_len")
    local point_idx_H = utils.ratio(H, 360, bar_len)
    local point_idx_S = utils.ratio(S, 100, bar_len)
    local point_idx_L = utils.ratio(L, 100, bar_len)
    local start_H, start_S, start_L = 7, 7, 7
    local end_H, end_S, end_L
    for i = 0, bar_len - 1 do
        end_H = update_end(i == point_idx_H, start_H, #bar_char, #point_char)
        end_S = update_end(i == point_idx_S, start_S, #bar_char, #point_char)
        end_L = update_end(i == point_idx_L, start_L, #bar_char, #point_char)

        local h_color = Color:colorcode(utils.hsl2rgb((i + 0.5) * 360 / bar_len, S, L))
        local s_color = Color:colorcode(utils.hsl2rgb(H, (i + 0.5) * 100 / bar_len, L))
        local l_color = Color:colorcode(utils.hsl2rgb(H, S, (i + 0.5) * 100 / bar_len))
        set_hl(0, "CccH" .. i, { fg = h_color })
        set_hl(0, "CccS" .. i, { fg = s_color })
        set_hl(0, "CccL" .. i, { fg = l_color })
        add_hl(0, self.ns_id, "CccH" .. i, 0, start_H, end_H)
        add_hl(0, self.ns_id, "CccS" .. i, 1, start_S, end_S)
        add_hl(0, self.ns_id, "CccL" .. i, 2, start_L, end_L)

        start_H, start_S, start_L = end_H, end_S, end_L
    end
end

function UI:update()
    api.nvim_buf_clear_namespace(0, self.ns_id, 0, -1)
    api.nvim_buf_set_lines(self.bufnr, 0, 4, false, self:buffer())
    if self.input_mode == "RGB" then
        self:highlight_rgb()
    else
        self:highlight_hsl()
    end
    local bg = self.color:colorcode()
    local fg = bg > "#800000" and "#000000" or "#ffffff"
    set_hl(0, "CccOutput", { fg = fg, bg = bg })
    local start = api.nvim_buf_get_lines(0, 3, 4, true)[1]:find("%S") - 1
    add_hl(0, self.ns_id, "CccOutput", 3, start, -1)
end

function UI:buffer()
    local buffer = {}
    local bar_len = config.get("bar_len")
    local output = self:output()
    if self.input_mode == "RGB" then
        local R, G, B = self.color:get_rgb()
        buffer = {
            table.concat({ "R:", ("%3d"):format(R), utils.create_bar(R, 255, bar_len) }, " "),
            table.concat({ "G:", ("%3d"):format(G), utils.create_bar(G, 255, bar_len) }, " "),
            table.concat({ "B:", ("%3d"):format(B), utils.create_bar(B, 255, bar_len) }, " "),
            string.rep(" ", opts.width - #output) .. output,
        }
    elseif self.input_mode == "HSL" then
        local H, S, L = self.color:get_hsl()
        buffer = {
            table.concat({ "H:", ("%3d"):format(H), utils.create_bar(H, 360, bar_len) }, " "),
            table.concat({ "S:", ("%3d"):format(S), utils.create_bar(S, 100, bar_len) }, " "),
            table.concat({ "L:", ("%3d"):format(L), utils.create_bar(L, 100, bar_len) }, " "),
            string.rep(" ", opts.width - #output) .. output,
        }
    end
    return buffer
end

function UI:output()
    return self.color:output(self.output_mode)
end

---@param int integer
---@param min integer
---@param max integer
---@return integer
local function fix_overflow(int, min, max)
    if int < min then
        return min
    elseif int > max then
        return max
    end
    return int
end

---@param delta integer
function UI:delta(delta)
    local lnum = api.nvim_win_get_cursor(0)[1]
    if self.input_mode == "RGB" then
        local R, G, B = self.color:get_rgb()
        if lnum == 1 then
            R = fix_overflow(R + delta, 0, 255)
        elseif lnum == 2 then
            G = fix_overflow(G + delta, 0, 255)
        elseif lnum == 3 then
            B = fix_overflow(B + delta, 0, 255)
        end
        self.color:set_rgb(R, G, B)
    else
        local H, S, L = self.color:get_hsl()
        if lnum == 1 then
            H = fix_overflow(H + delta, 0, 360)
        elseif lnum == 2 then
            S = fix_overflow(S + delta, 0, 100)
        elseif lnum == 3 then
            L = fix_overflow(L + delta, 0, 100)
        end
        self.color:set_hsl(H, S, L)
    end
    self:update()
end

function UI:set_percent(percent)
    local lnum = api.nvim_win_get_cursor(0)[1]
    if self.input_mode == "RGB" then
        local R, G, B = self.color:get_rgb()
        if lnum == 1 then
            R = utils.round(255 * percent / 100)
        elseif lnum == 2 then
            G = utils.round(255 * percent / 100)
        elseif lnum == 3 then
            B = utils.round(255 * percent / 100)
        end
        self.color:set_rgb(R, G, B)
    else
        local H, S, L = self.color:get_hsl()
        if lnum == 1 then
            H = utils.round(360 * percent / 100)
        elseif lnum == 2 then
            S = percent
        elseif lnum == 3 then
            L = percent
        end
        self.color:set_hsl(H, S, L)
    end
    self:update()
end

local colorcode_pattern =
    "#([0-9a-fA-F][0-9a-fA-F])([0-9a-fA-F][0-9a-fA-F])([0-9a-fA-F][0-9a-fA-F])"
local rgb_pattern = "rgb%((%d+),%s*(%d+),%s*(%d+)%)"
local hsl_pattern = "hsl%((%d+),%s*(%d+)%%,%s*(%d+)%%%)"

function UI:pick()
    ---@type string
    local current_line = api.nvim_get_current_line()
    local cursor_col = api.nvim_win_get_cursor(0)[2] + 1
    local s, e, cap1, cap2, cap3 = current_line:find(colorcode_pattern)
    if s and s <= cursor_col and cursor_col <= e then
        self.start_col = s
        self.end_col = e
        local R, G, B = tonumber(cap1, 16), tonumber(cap2, 16), tonumber(cap3, 16)
        self.color:set(self.input_mode, "RGB", R, G, B)
    end
    s, e, cap1, cap2, cap3 = current_line:find(rgb_pattern)
    if s and s <= cursor_col and cursor_col <= e then
        self.start_col = s
        self.end_col = e
        local R, G, B = tonumber(cap1, 10), tonumber(cap2, 10), tonumber(cap3, 10)
        self.color:set(self.input_mode, "RGB", R, G, B)
    end
    s, e, cap1, cap2, cap3 = current_line:find(hsl_pattern)
    if s and s <= cursor_col and cursor_col <= e then
        self.start_col = s
        self.end_col = e
        local H, S, L = tonumber(cap1, 10), tonumber(cap2, 10), tonumber(cap3, 10)
        self.color:set(self.input_mode, "HSL", H, S, L)
    end
end

function UI:input_mode_toggle()
    if self.input_mode == "RGB" then
        self.input_mode = "HSL"
        self.color:rgb2hsl()
    else
        self.input_mode = "RGB"
        self.color:rgb2hsl()
    end
    self:update()
end

function UI:output_mode_toggle()
    if self.output_mode == "RGB" then
        self.output_mode = "HSL"
    elseif self.output_mode == "HSL" then
        self.output_mode = "ColorCode"
    else
        self.output_mode = "RGB"
    end
    self:update()
end

return UI
