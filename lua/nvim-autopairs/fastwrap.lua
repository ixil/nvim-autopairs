local utils = require('nvim-autopairs.utils')
local log = require('nvim-autopairs._log')
local npairs = require('nvim-autopairs')
local M = {}

local default_config = {
    map = '<M-e>',
    chars = { '{', '[', '(', '"', "'" },
    pattern = [=[[%'%"%>%]%)%}%,%`]]=],
    interpattern = [=[[(%s%w)]]=],
    end_key = '$',
    end_is_end = true, -- always treat end_key as eol
    avoid_move_to_end = true, -- choose your move behaviour for non-alphabetical end_keys' 
    before_key = 'h',
    after_key = 'l',
    cursor_pos_before = true,
    keys = 'qwertyuiopzxcvbnmasdfghjkl',
    highlight = 'Search',
    highlight_grey = 'Comment',
    manual_position = true,
    use_virt_lines = true
}

M.ns_fast_wrap = vim.api.nvim_create_namespace('autopairs_fastwrap')

local config = {}

M.setup = function(cfg)
    if config.chars == nil then
        config = vim.tbl_extend('force', default_config, cfg or {}) or {}
        npairs.config.fast_wrap = config
    end
end

function M.getchar_handler()
    local ok, key = pcall(vim.fn.getchar)
    if not ok then
        return nil
    end
    if key ~= 27 and type(key) == 'number' then
        local key_str = vim.fn.nr2char(key)
        return key_str
    end
    return nil
end

--- At position col in the line, returns true if the closing pair should be offset due to the previous character being a closing bracket, or quotes.
function M.should_offset(line, col, char, prev_char)
    --CHECK: Not sure the is_in_quotes makes sense here?
    return utils.is_quote(char) or ( utils.is_close_bracket(char) and utils.is_in_quotes(line, col, prev_char))
end

M.key_amongst = {
    left = {},    -- *a* b c    d
    between = {}, -- a *b* c    d
    singular = {}, -- a b c    *d*
    right = {},   -- a b *c*    d
    -- )]

M.show = function(line)
    line = line or utils.text_get_current_line(0)
    log.debug(line)
    local row, col = utils.get_cursor()
    local prev_char = utils.text_cusor_line(line, col, 1, 1, false)
    local closing_pair = ''

    local nextKey = function()
        local index = 0
        local iter = function()
            index = index + 1
            return config.keys:sub(index, index)
        end
        return iter
    end

    if utils.is_in_table(config.chars, prev_char) then
        local rules = npairs.get_buf_rules()
        for _, rule in pairs(rules) do
            if rule.start_pair == prev_char then
                closing_pair = rule.end_pair
            end
        end
        if closing_pair == '' then
            return
        end
        local list_pos = {} --holds target locations
        local index = 1
        local str_length = #line
        -- local interpattern = [=[(%s%w)]=]
        -- from cursor_0 to end of line, check if previous char is ' ', "%w", or current in in pattern
        local i = col
        local line_matches = {}
        while i < #line+1  do --CHECK: off-by one?
            local offset = -1
            local sii, eii, sm = string.find(line:sub(i+1, -1), config.interpattern, i, false)
            local spi, epi, pm = string.find(line:sub(i+1, -1), config.pattern, i, false)
            i = math.min(eii or #line, epi or #line) -- skip ahead to next match

            if config.manual_position then 
                -- TODO: do something with this?
            end

            -- note this is unsorted
            if spi and sii ~= spi then
                -- TODO: is len useful?
                table.insert(line_matches, {(col + spi + offset), {match = pm, len = epi-spi, offset = offset}})
            elseif sii then
                -- Move after a quote/closing bracket / being inside a quote?
                --TODO: Should this go before or after the narrowing of locations
                if not config.manual_position and M.should_offset(line, col+sii, sm[1], line:sub(col+sii, col+sii)) then
                    offset = 0
                end
                table.insert(line_matches, {(col + sii+offset), {match = sm, len = eii-sii, offset = offset}})
            end
        end
        table.insert(line_matches, {str_length, {match = '', len = 0, offset=0}}) -- always add end of line

        -- Sort matches
        local line_pos = {}
        for n in pairs(line_matches) do table.insert(line_pos, n) end
        table.sort(line_pos)

        local adjacent = false
        local span = 0 
        for j,i in ipairs(line_pos) do
            local m = line_matches[line_pos[i]]
            prev_char = line:sub(line_pos[i]-1, line_pos[i])

            if last + 1 == line_pos[i] then
                adjacent = true
            else
                adjacent = false
                if run then
                    list_pos[last_item].key_position = key_amongst.right
                end
                run = false
            end

            if line_matches[last].match == m.match and adjacent then
                span = span + 1
            -- continue
            else
                span = 0
                if adjacent then
                else
                end
            if last_match and last_match.col+1 == i and not adjacent then
                --adjacent
                adjacent = true
                last_item = list_pos
                table.insert(list_pos, {col = line_pos[i]+m.offset, key = nextKey(), pos = end_pos, char = m.match, span = span})
            end

            run = adjacent
            last = line_pos[i]
            end
        end

            -----------------------------------
            -- TODO: extract into function
                -----------------------------------

                -- TODO: Move the key logic outside, this also duplicates the manual end_key insertion
                if config.manual_position and i == str_length then
                    key = config.end_key
                end

                table.insert(
                    list_pos,
                    { col = i + offset, key = key, char = char, pos = i }
                )
        end
        log.debug(list_pos)

        local end_col, end_pos
    -- TODO: the non-manual_position?
        if config.manual_position then
            end_col = str_length + offset
            end_pos = str_length
        else
            end_col = str_length + 1
            end_pos = str_length + 1
        end

        -- add end_key to list extmark
        if #list_pos == 0 or list_pos[#list_pos].key ~= config.end_key then
            table.insert(
                list_pos,
                { col = end_col, key = config.end_key, pos = end_pos, char = config.end_key }
            )
        end

        -- Create a whitespace string for the current line which replaces every non whitespace
        -- character with a space and preserves tabs, so we can use it for highlighting with
        -- virtual lines so that highlighting lines up correctly.
        -- The string is limited to the last position in list_pos
        local whitespace_line = line:sub(1, list_pos[#list_pos].end_pos):gsub("[^ \t]", " ")

        M.highlight_wrap(list_pos, row, col, #line, whitespace_line)
        vim.defer_fn(function()
            -- get the first char
            --TODO: add logic to detect if two characters are necessary or just one
            local char = #list_pos == 1 and config.end_key or M.getchar_handler()
            vim.api.nvim_buf_clear_namespace(0, M.ns_fast_wrap, row, row + 1)

            -- FIXME: add logic to avoid duplicate key locations
            for _, pos in pairs(list_pos) do
                -- handle end_key specially
                if char == config.end_key and char == pos.key and config.end_is_end then
                    vim.print("Run to end!")
                    -- M.highlight_wrap({pos = pos.pos, key = config.end_key}, row, col, #line, whitespace_line)
                    local move_end_key = (not config.avoid_move_to_end and char == string.upper(config.end_key))
                    M.move_bracket(line, pos.col+1, closing_pair, move_end_key)
                    break
                end
                local hl_mark = {
                    { pos = pos.pos - 1, key = config.before_key },
                    { pos = pos.pos + 1, key = config.after_key },
                }
                if config.manual_position and (char == pos.key or char == string.upper(pos.key)) then
                    M.highlight_wrap(hl_mark, row, col, #line, whitespace_line)
                    M.choose_pos(row, line, pos, closing_pair)
                    break
                end
                if char == pos.key then
                    M.move_bracket(line, pos.col, closing_pair, false)
                    break
                end
                if char == string.upper(pos.key) then
                    M.move_bracket(line, pos.col, closing_pair, true)
                    break
                end
            end
            vim.cmd('startinsert')
        end, 10)
        return
    end
    vim.cmd('startinsert')
end

M.choose_pos = function(row, line, pos, end_pair)
    vim.defer_fn(function()
        -- select a second key
        local char =
            pos.char == nil and config.before_key
            or pos.char == config.end_key and config.after_key
            or M.getchar_handler()
        vim.api.nvim_buf_clear_namespace(0, M.ns_fast_wrap, row, row + 1)
        if not char then return end
        local change_pos = false
        local col = pos.col
        if char == string.upper(config.before_key) or char == string.upper(config.after_key) then
            change_pos = true
        end
        if char == config.after_key or char == string.upper(config.after_key) then
            col = pos.col + 1
        end
        M.move_bracket(line, col, end_pair, change_pos)
        vim.cmd('startinsert')
    end, 10)
end

M.existing_end_bracket = function(line, i, end_pair)
    -- Determine if at location i within the line end_pair already exists
 return line:sub(i, end_pair:len()) == end_pair
end

M.move_bracket = function(line, target_pos, end_pair, change_pos)
    log.debug(target_pos)
    line = line or utils.text_get_current_line(0)
    local row, col = utils.get_cursor()
    local _, next_char = utils.text_cusor_line(line, col, 1, 1, false)
    -- remove an autopairs if that exist
    -- FIXME: should be redundant if already fixed elsewhere
    if next_char == end_pair then
        line = line:sub(1, col) .. line:sub(col + 2, #line)
        target_pos = target_pos - 1
    end

    line = line:sub(1, target_pos) .. end_pair .. line:sub(target_pos + 1, #line)
    vim.api.nvim_set_current_line(line)
    if change_pos then
        vim.api.nvim_win_set_cursor(0, { row + 1, target_pos + (config.cursor_pos_before and 0 or 1) })
    end
end

M.highlight_wrap = function(tbl_pos, row, col, end_col, whitespace_line)
    local bufnr = vim.api.nvim_win_get_buf(0)
    if config.use_virt_lines then
        local virt_lines = {}
        local start = 0
        local left_col = vim.fn.winsaveview().leftcol
        if left_col > 0 then
            vim.fn.winrestview({ leftcol = 0 })
        end
        for _, pos in ipairs(tbl_pos) do
            virt_lines[#virt_lines + 1] = { whitespace_line:sub(start + 1, pos.pos - 1), 'Normal' }
            virt_lines[#virt_lines + 1] = { pos.key, config.highlight }
            start = pos.pos
        end
        vim.api.nvim_buf_set_extmark(bufnr, M.ns_fast_wrap, row, 0, {
            virt_lines = { virt_lines },
            hl_mode = 'blend',
        })
    else
        if config.highlight_grey then
            vim.highlight.range(
                bufnr,
                M.ns_fast_wrap,
                config.highlight_grey,
                { row, col },
                { row, end_col },
                {}
            )
        end
        for _, pos in ipairs(tbl_pos) do
            vim.api.nvim_buf_set_extmark(bufnr, M.ns_fast_wrap, row, pos.pos - 1, {
                virt_text = { { pos.key, config.highlight } },
                virt_text_pos = 'overlay',
                hl_mode = 'blend',
            })
        end
    end
end

return M
