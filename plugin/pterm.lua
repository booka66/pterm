if vim.g.loaded_pterm then
	return
end
vim.g.loaded_pterm = true

-- Auto-setup if not explicitly called
vim.api.nvim_create_autocmd("VimEnter", {
	callback = function()
		if not vim.g.pterm_setup_called then
			vim.g.pterm_setup_called = true
			require("pterm").setup()
		end
	end,
})