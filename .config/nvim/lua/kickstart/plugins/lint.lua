return {

	{ -- Linting
		"mfussenegger/nvim-lint",
		event = { "BufReadPre", "BufNewFile" },
		config = function()
			local lint = require("lint")

			lint.linters_by_ft = {
				markdown = { "markdownlint" },
				json = { "jsonlint" },
				terraform = { "tflint" },
				text = { "vale" },
			}

			-- To allow other plugins to add linters to require('lint').linters_by_ft,
			-- instead set linters_by_ft like this:
			-- lint.linters_by_ft = lint.linters_by_ft or {}
			-- lint.linters_by_ft['markdown'] = { 'markdownlint' }
			--
			-- However, note that this will enable a set of default linters,
			-- which will cause errors unless these tools are available:
			-- {
			--   clojure = { "clj-kondo" },
			--   dockerfile = { "hadolint" },
			--   inko = { "inko" },
			--   janet = { "janet" },
			--   markdown = { "vale" },
			--   rst = { "vale" },
			--   ruby = { "ruby" },
			-- }
			--
			-- You can disable the default linters by setting their filetypes to nil:
			-- lint.linters_by_ft['clojure'] = nil
			-- lint.linters_by_ft['dockerfile'] = nil
			-- lint.linters_by_ft['inko'] = nil
			-- lint.linters_by_ft['janet'] = nil
			-- lint.linters_by_ft['json'] = nil
			-- lint.linters_by_ft['markdown'] = nil
			-- lint.linters_by_ft['rst'] = nil
			-- lint.linters_by_ft['ruby'] = nil
			-- lint.linters_by_ft['terraform'] = nil
			-- lint.linters_by_ft['text'] = nil

			lint.linters.kubelinter = {
				cmd = "kube-linter",
				stdin = false,
				args = { "lint", "--format=json" },
				stream = "stdout",
				ignore_exitcode = true,
				parser = function(output)
					local diagnostics = {}
					local ok, decoded = pcall(vim.json.decode, output)
					if not ok or not decoded or not decoded.Reports then
						return diagnostics
					end

					for _, report in ipairs(decoded.Reports) do
						table.insert(diagnostics, {
							lnum = (report.Diagnostic.Range.Start.Line or 1) - 1,
							col = (report.Diagnostic.Range.Start.Column or 1) - 1,
							end_lnum = (report.Diagnostic.Range.End.Line or 1) - 1,
							end_col = (report.Diagnostic.Range.End.Column or 1) - 1,
							severity = vim.diagnostic.severity.WARN,
							message = report.Check .. ": " .. report.Diagnostic.Message,
							source = "kube-linter",
						})
					end

					return diagnostics
				end,
			}

			local function get_linters_for_buffer()
				local bufname = vim.api.nvim_buf_get_name(0)
				local linters = {}

				if bufname:match("%.ya?ml$") then
					if bufname:match("%.gitlab%-ci%.yml$") or bufname:match("/%.gitlab%-ci%.yml$") then
						table.insert(linters, "yamllint")
						return linters
					end

					local k8s_patterns = {
						"_deployment_",
						"_service_",
						"_spc_",
						"_configmap_",
						"_configMap_",
						"_template_",
						"_job_",
						"_secrets_",
						"_role",
						"_clusterRole",
					}

					local is_k8s = bufname:match("/k8s/")
					if not is_k8s then
						for _, pattern in ipairs(k8s_patterns) do
							if bufname:match(pattern) then
								is_k8s = true
								break
							end
						end
					end

					if is_k8s then
						table.insert(linters, "kubelinter")
					end

					table.insert(linters, "yamllint")
				end

				return linters
			end

			-- Create autocommand which carries out the actual linting
			-- on the specified events.
			local lint_augroup = vim.api.nvim_create_augroup("lint", { clear = true })
			vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
				group = lint_augroup,
				callback = function()
					-- Only run the linter in buffers that you can modify in order to
					-- avoid superfluous noise, notably within the handy LSP pop-ups that
					-- describe the hovered symbol using Markdown.
					if vim.bo.modifiable then
						local custom_linters = get_linters_for_buffer()
						if #custom_linters > 0 then
							lint.try_lint(custom_linters)
						else
							lint.try_lint()
						end
					end
				end,
			})

			vim.keymap.set("n", "<leader>l", function()
				local linters = get_linters_for_buffer()
				if #linters > 0 then
					lint.try_lint(linters)
				end
			end, { desc = "Trigger linting for current file" })
		end,
	},
}
