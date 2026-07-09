---@diagnostic disable: undefined-field

local parser = {};
local health = require("markview.health");

---@type [ integer, integer ][] List of line ranges to ignore.
parser.ignore_ranges = {};
--- Cached parse results, keyed by buffer.
--- Each entry: { tick = changedtick, from, to, content, sorted }.
--- A parse is reused when tick/from/to all match (see parser.init).
parser.cached = {};

--- Creates ignore ranges from a list of parsed items.
---@param language string
---@param items table[]
---@return [ integer, integer ][]
parser.create_ignore_range = function (language, items)
	---|fS

	local _r = {};

	if language == "markdown" then
		-- Do not parse things inside code block.
		for _, item in ipairs(items["markdown_code_block"] or {}) do
			table.insert(_r, { item.range.row_start, item.range.row_end })
		end
	elseif language == "asciidoc" then
		for _, item in ipairs(items["asciidoc_code_block"] or {}) do
			table.insert(_r, { item.range.row_start, item.range.row_end })
		end
	elseif language == "typst" then
		-- Do not parse things inside raw block.
		for _, item in ipairs(items["typst_raw_block"] or {}) do
			table.insert(_r, { item.range.row_start, item.range.row_end })
		end
	end

	parser.ignore_ranges = vim.list_extend(parser.ignore_ranges, _r);
	return _r;

	---|fE
end

--- Wrapper for `vim.tbl_extend()` that also extends lists.
---@param tbl_1 table
---@param tbl_2 table
---@return table
parser.deep_extend = function (tbl_1, tbl_2)
	---|fS

	for k, v in pairs(tbl_2) do
		if tbl_1[k] then
			if vim.islist(v) and vim.islist(tbl_1[k]) then
				tbl_1[k] = vim.list_extend(tbl_1[k], v);
			elseif type(v) == "table" and type(tbl_1[k]) == "table" then
				tbl_1[k] = parser.deep_extend(tbl_1[k], v);
			else
				tbl_1[k] = v;
			end
		else
			tbl_1[k] = v;
		end
	end

	return tbl_1;

	---|fE
end

--- Checks if a node should be ignored.
---@param TSTree TSTree
---@return boolean
parser.should_ignore = function (TSTree)
	---|fS

	local t_start, _, t_stop, _ = TSTree:root():range();

	for _, range in ipairs(parser.ignore_ranges) do
		if t_start >= range[1] and t_stop <= range[2] then
			return true;
		end
	end

	return false;

	---|fE
end

--[[
Checks if a `yaml block` should be ignored.

This is to prevent rendering inside `code blocks` in **markdown**.
]]
---@param root vim.treesitter.LanguageTree
---@param TSTree TSTree
---@return boolean
parser.should_ignore_yaml = function (root, TSTree)
	---|fS

	if root:lang() ~= "markdown" then
		return false;
	end

	---@diagnostic disable-next-line: missing-fields
	local metadata = root:named_node_for_range({ TSTree:root():range() }, {});
	if metadata then
		return metadata:type() ~= "minus_metadata";
	end

	return true;

	---|fE
end

---@type markview.parsed
parser.content = {};
---@type markview.parsed_sorted
parser.sorted = {};

--- Structural copy of a parsed "view" ({ [lang] = { node, ... } }).
---
--- Copies only the CONTAINER tables (the outer lang map and each per-language
--- list) so the caller can table.remove()/insert() entries without touching the
--- shared original. Node entries themselves are shared by reference, NOT copied:
--- they hold tree-sitter userdata (TSNode) that vim.deepcopy() cannot handle,
--- and renderer.filter() only ever reorders/removes list entries, never mutates
--- a node in place. Used to hand out cache copies (see parser.init).
---@generic T
---@param view T
---@return T
parser.copy_view = function (view)
	if type(view) ~= "table" then
		return view;
	end

	local out = {};

	for lang, list in pairs(view) do
		if type(list) == "table" then
			local copy = {};
			for i, node in ipairs(list) do
				copy[i] = node;
			end
			out[lang] = copy;
		else
			out[lang] = list;
		end
	end

	return out;
end

--- Initializes the parsers on the specified buffer
--- Parsed data is stored as a "view" in renderer.lua
---
---@param buffer number
---@param from integer?
---@param to integer?
---@param cache boolean?
---@return markview.parsed
---@return markview.parsed_sorted
parser.init = function (buffer, from, to, cache)
	---|fS

	-- Content cache: on an unchanged buffer (same changedtick) and identical
	-- range, the parse result is byte-identical, so reuse it and skip the whole
	-- parse. changedtick bumps on any edit, invalidating the entry implicitly.
	-- This is the common case for a hybrid-mode cursor move that does not scroll
	-- (range is viewport-derived, not cursor-derived).
	local tick = vim.api.nvim_buf_get_changedtick(buffer);
	local hit = parser.cached[buffer];

	if cache ~= false and hit and hit.tick == tick and hit.from == from and hit.to == to then
		-- Return COPIES, not the cached tables themselves. Callers mutate the
		-- returned content in place -- notably hybrid mode, where
		-- renderer.filter() does table.remove() on the per-language node lists to
		-- hide nodes around the cursor. Handing out the cached reference would let
		-- that removal corrupt the cache: the next cursor move (same changedtick,
		-- same viewport range) hits the cache and gets the already-pruned table,
		-- so nodes hidden under the previous cursor position never come back
		-- until a scroll changes the range and forces a fresh parse.
		parser.content = parser.copy_view(hit.content);
		parser.sorted = parser.copy_view(hit.sorted);
		parser.ignore_ranges = hit.ignore_ranges or {};
		return parser.content, parser.sorted;
	end

	local _parsers = {
		asciidoc = require("markview.parsers.asciidoc"),
		asciidoc_inline = require("markview.parsers.asciidoc_inline"),
		comment = require("markview.parsers.comment");
		markdown = require("markview.parsers.markdown");
		markdown_inline = require("markview.parsers.markdown_inline");
		html = require("markview.parsers.html");
		latex = require("markview.parsers.latex");
		typst = require("markview.parsers.typst");
		yaml = require("markview.parsers.yaml");
	};

	-- Clear the previous contents
	parser.content = {};
	parser.sorted = {};
	parser.ignore_ranges = {};

	if not pcall(vim.treesitter.get_parser, buffer) then
		-- Couldn't call parser retrieval function.
		return parser.content, parser.sorted;
	end

	local root_parser = vim.treesitter.get_parser(buffer);

	if not root_parser then
		-- Can't find root parser.
		return parser.content, parser.sorted;
	end

	root_parser:parse(true);

	--[[
		WARN: Recursion when parsing `asciidoc_inline` trees

		`cathaysia/tree-sitter-asciidoc` uses `#injection.include-children` for it's inline parser.
		This causes the same text to be parsed multiple times,

		FIX(asciidoc_inline): Check parse range

		Check if a parser range has been parsed before. If it has, do not parse again.
	]]
	_parsers.asciidoc_inline.parsed_ranges = {};

	---|fS "chore: Announce start of parsing"
	---@type integer Start time
	local start = vim.uv.hrtime();

	health.print({
		from = "parsers.lua",
		fn = "init()",

		message = string.format("Parsing(start): %d", buffer),
		nest = true,
	});

	---|fE

	-- Normalized inclusive line bounds for the tree-overlap test below.
	-- `from`/`to` may be nil or `to == -1` (meaning end-of-buffer).
	local ov_from = from or 0;
	local ov_to = (to == nil or to < 0) and math.huge or to;

	root_parser:for_each_tree(function (TSTree, language_tree)
		language_tree:parse(true);

		local language = language_tree:lang();
		-- Skip trees whose range does not overlap [from, to]. On a large buffer
		-- this avoids running per-language extraction over thousands of injection
		-- trees (e.g. one markdown_inline tree per line) that lie outside the
		-- rendered range. Whole-buffer trees (the markdown root) always overlap
		-- and are never skipped, so ignore-range detection is unaffected.
		local ts_start, _, ts_end = TSTree:root():range();
		if ts_end < ov_from or ts_start > ov_to then
			return;
		end
		local content, sorted = {}, {};

		if language == "yaml" and not parser.should_ignore_yaml(root_parser, TSTree) then
			content, sorted = _parsers[language].parse(buffer, TSTree, from, to);
			parser.create_ignore_range(language, sorted)
		elseif _parsers[language] and not parser.should_ignore(TSTree) then
			content, sorted = _parsers[language].parse(buffer, TSTree, from, to);
			parser.create_ignore_range(language, sorted)
		end

		parser.content[language] = vim.list_extend(parser.content[language] or {}, content);
		parser.sorted[language] = parser.deep_extend(parser.sorted[language] or {}, sorted);
	end)

	if cache ~= false then
		-- Store COPIES, decoupled from the returned parser.content/sorted. The
		-- caller mutates the returned tables in place (hybrid mode removes nodes
		-- around the cursor via renderer.filter), so caching the live references
		-- would let that mutation corrupt the freshly-stored entry -- see the
		-- matching copy on the cache-hit path above.
		parser.cached[buffer] = {
			tick = tick,
			from = from,
			to = to,
			content = parser.copy_view(parser.content),
			sorted = parser.copy_view(parser.sorted),
			ignore_ranges = parser.ignore_ranges,
		};
	end

	---|fS "chore: Announce end of parsing"
	---@type integer End time
	local now = vim.uv.hrtime();

	health.print({
		message = string.format("Parsing total(%d): %dms", buffer, (now - start) / 1e6),
		back = true,
	});

	---|fE

	return parser.content, parser.sorted;

	---|fE
end

-- Chore: This is for backwards compatibility.
parser.parse = parser.init;


--[[ Parses various `links` from `buffer`. ]]
---
---@param buffer number
parser.parse_links = function (buffer)
	---|fS

	local _parsers = {
		markdown = require("markview.parsers.links.markdown");
		-- markdown_inline = require("markview.parsers.markdown_inline");
		html = require("markview.parsers.links.html");
		-- latex = require("markview.parsers.latex");
		-- typst = require("markview.parsers.typst");
		-- yaml = require("markview.parsers.yaml");
	};

	-- Clear link references.
	require("markview.links").clear(buffer);

	if not pcall(vim.treesitter.get_parser, buffer) then
		-- Couldn't call parser retrieval function.
		return;
	end

	local root_parser = vim.treesitter.get_parser(buffer);

	if not root_parser then
		-- Can't find root parser.
		return parser.content, parser.sorted;
	end

	root_parser:parse(true);

	---|fS "chore: Announce start of parsing"
	---@type integer Start time
	local start = vim.uv.hrtime();

	health.print({
		from = "parsers.lua",
		fn = "init()",

		message = string.format("Parsing links: %d", buffer),
		nest = true,
	});

	---|fE

	root_parser:for_each_tree(function (TSTree, language_tree)
		language_tree:parse(true);

		local language = language_tree:lang();

		if _parsers[language] and not parser.should_ignore(TSTree) then
			_parsers[language].parse(buffer, TSTree);
		end
	end)

	---|fS "chore: Announce end of parsing"
	---@type integer End time
	local now = vim.uv.hrtime();

	health.print({
		from = "parsers.lua",
		fn = "init()",

		message = string.format("Parsing links total(%d): %dms", buffer, (now - start) / 1e6),
		back = true,
	});

	---|fE

	---|fE
end

return parser;
