.PHONY: dev clean test lint format docs deploy update-submodules

VIMRUNTIME := $(shell nvim --headless --clean -c 'lua io.write(vim.env.VIMRUNTIME)' -c 'qa')

dev:
	mkdir -p ~/.local/share/nvim/site/pack/dev/start/tree.nvim
	stow -d .. -t ~/.local/share/nvim/site/pack/dev/start/tree.nvim tree.nvim

clean:
	rm -rf ~/.local/share/nvim/site/pack/dev

test:
	nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run()"

lint:
	VIMRUNTIME="$(VIMRUNTIME)" lua-language-server --check=./lua --checklevel=Warning --configpath=$(CURDIR)/.luarc.json
	VIMRUNTIME="$(VIMRUNTIME)" lua-language-server --check=./tests --checklevel=Warning --configpath=$(CURDIR)/.luarc.json

format:
	# https://github.com/JohnnyMorganz/StyLua#usage
	stylua .

update-submodules:
	git submodule update --init --recursive --remote

docs:
	mkdir -p ./doc
	./deps/ts-vimdoc.nvim/scripts/docgen.sh README.md doc/tree.txt tree
	nvim --headless -c "helptags doc/" -c "qa"

deploy: test lint format docs
